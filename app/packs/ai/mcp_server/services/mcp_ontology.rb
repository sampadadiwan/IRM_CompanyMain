# frozen_string_literal: true

# Semantic layer for the MCP tools.
#
# Loads one YAML ontology per entity from app/packs/ai/mcp_server/ontology and turns it into
# (a) each tool's name and `description`, (b) each tool's JSON input schema, and (c) a
# validator for the arguments an AI client actually sends.
#
# Why this exists: the tool descriptions were hand-written prose listing attributes,
# predicates and scopes, and they drifted from the models. Ransack's
# `ignore_unknown_conditions` defaults to true and this app never overrides it, so a
# condition naming an attribute the model does not expose is *dropped* rather than
# rejected -- the tool returns every row the user can see and the AI client presents that as
# a filtered answer. Three separate variants of that bug were live in the descriptions:
#
#   * attributes that do not exist at all (`status`, `verified` on CapitalCall;
#     `rule_for` on AccountEntry) -- silently ignored, unfiltered rows returned;
#   * sort keys that are not ransackable (`call_amount_cents desc`) -- silently ignored,
#     so "top 5 by amount" returned an arbitrary 5;
#   * attributes that are ransackable but whose SQL references a column that does not
#     exist -- these raise StatementInvalid instead (fixed at the model, and recorded in
#     the ontology so the history is not lost).
#
# Generating the description from the same file the validator reads makes the two
# impossible to disagree; the Cucumber drift guard asserts both against the models.
#
# @see McpOntology::Entity#validate_query
# @see McpOntology::Tool#description
class McpOntology
  class UnknownEntity < StandardError; end
  class UnknownTool < StandardError; end

  ONTOLOGY_DIR = Rails.root.join("app/packs/ai/mcp_server/ontology")

  # Ransack predicates offered per field type. A field may narrow this with its own
  # `filter:` list in the YAML. Deliberately conservative: `matches` on free text invites
  # expensive leading-wildcard scans from a model that is guessing.
  PREDICATES_BY_TYPE = {
    "string" => %w[eq not_eq cont not_cont start end in not_in null not_null],
    "text" => %w[eq cont not_cont null not_null],
    "date" => %w[eq not_eq gt gteq lt lteq null not_null],
    "datetime" => %w[eq not_eq gt gteq lt lteq null not_null],
    "money" => %w[eq not_eq gt gteq lt lteq],
    "percent" => %w[eq not_eq gt gteq lt lteq],
    "decimal" => %w[eq not_eq gt gteq lt lteq null not_null],
    "integer" => %w[eq not_eq gt gteq lt lteq in not_in null not_null],
    "boolean" => %w[eq true false],
    "enum" => %w[eq not_eq in not_in],
    "reference" => %w[eq not_eq in not_in]
  }.freeze

  # Field types worth offering as a group_by dimension. Amounts and free text are excluded:
  # grouping by them produces roughly one group per row.
  GROUPABLE_TYPES = %w[boolean reference enum string date].freeze

  # Types that can be summed.
  SUMMABLE_TYPES = %w[money decimal integer percent].freeze

  # FundAssistantDataManager#perform_aggregation treats an aggregate_field of "id" as
  # "count rows" rather than "sum a column", and requires an aggregate_field even for
  # group_by. Offering it in the enum is what lets a client ask for "calls per fund".
  COUNT_FIELD = "id"

  # Keys the tool layer injects into the query hash AFTER validation. A client that puts
  # one inside `query` is routing around the validated top-level argument, and all three
  # reach a sink that will not catch it: `s` is dropped silently by Ransack, while
  # `aggregate_field` and `group_by` are interpolated as raw SQL by perform_aggregation.
  # They are rejected here and named as the argument to use instead.
  RESERVED_QUERY_KEYS = {
    "s" => "sort",
    "aggregate_field" => "aggregate_field",
    "group_by" => "group_by_field"
  }.freeze

  MAX_ROWS = FundAssistantDataManager::DEFAULT_QUERY_LIMIT

  # Arguments shared across tools, describing the tool layer's contract rather than any one
  # entity's domain -- which is why they live here and not in the YAML. A tool opts into
  # them by naming them in its `params:`, optionally overriding any key.
  SHARED_PARAMS = {
    "fund_ids" => {
      "type" => "array", "items" => { "type" => "integer" },
      "description" => "Restrict to these fund IDs. Resolve fund names to IDs with list_funds first."
    },
    "folio_ids" => {
      "type" => "array", "items" => { "type" => "string" },
      "description" => "Restrict to these folio IDs (a folio is one investor's commitment in one fund). " \
                       "Find them with list_capital_commitments."
    },
    "portfolio_company_id" => {
      "type" => "integer",
      "description" => "Portfolio company ID. Find it with list_portfolio_companies using " \
                       "{ investor_name_cont: 'name' }."
    },
    "portfolio_company_ids" => {
      "type" => "array", "items" => { "type" => "integer" },
      "description" => "Portfolio company IDs. Find them with list_portfolio_companies using " \
                       "{ investor_name_cont: 'name' }."
    },
    "commitment_id" => {
      "type" => "integer",
      "description" => "Capital commitment ID. Find it with list_capital_commitments."
    },
    "fund_id" => {
      "type" => "integer",
      "description" => "Fund ID. Find it with list_funds using { name_cont: 'fund name' }."
    },
    "document_id" => {
      "type" => "integer",
      "description" => "Document ID. Find it with list_documents."
    }
  }.freeze

  class << self
    # @param name [Symbol, String] entity name, matching the YAML filename
    # @return [McpOntology::Entity]
    def [](name)
      entities.fetch(name.to_s) { raise UnknownEntity, "No MCP ontology for entity #{name.inspect}" }
    end

    # @param name [Symbol, String] tool name as declared under an entity's `tools:`
    # @return [McpOntology::Tool]
    def tool(name)
      tools.fetch(name.to_s) { raise UnknownTool, "No MCP ontology for tool #{name.inspect}" }
    end

    def entity_names = entities.keys
    def tool_names = tools.keys

    def entities
      return build_entities if Rails.env.development?

      @entities ||= build_entities
    end

    def tools
      @tools = nil if Rails.env.development?
      @tools ||= entities.values.flat_map { |e| e.tools.to_a }.to_h
    end

    def reload!
      @entities = nil
      @tools = nil
    end

    private

    # Memoized in every environment except development, where editing a .yml should take
    # effect without a server restart. Note each tool's `description` is captured in its
    # class body at load time, so a dev reload of the tool class is what re-renders it.
    def build_entities
      Dir[ONTOLOGY_DIR.join("*.yml")].to_h do |path|
        entity = Entity.new(YAML.safe_load_file(path))
        [entity.name, entity]
      end
    end
  end

  # One entity's ontology: the domain facts, shared by every tool that reads that entity.
  class Entity
    attr_reader :raw

    def initialize(raw)
      @raw = raw
    end

    def name = raw.fetch("entity")
    def label = raw.fetch("label")
    def model_name = raw.fetch("model")
    def summary = raw.fetch("description")
    def fields = raw["fields"] || {}
    def returned_only = raw["returned_only"] || {}
    def unavailable = raw["unavailable"] || {}
    def relationships = raw["relationships"] || {}
    def measures = raw["measures"] || {}
    def caveats = raw["caveats"] || []
    def scope_spec = raw.fetch("scopes", nil)

    def tools
      @tools ||= raw.fetch("tools").to_h { |tool_name, spec| [tool_name, Tool.new(self, tool_name, spec)] }
    end

    # @param field [String]
    # @return [Array<String>] Ransack predicates allowed on that field
    def predicates_for(field)
      spec = fields.fetch(field)
      spec["filter"] || PREDICATES_BY_TYPE.fetch(spec.fetch("type"))
    end

    def sortable_fields = fields.select { |_, spec| spec["sortable"] }.keys

    def aggregatable_fields
      fields.select { |_, spec| spec.fetch("aggregatable", SUMMABLE_TYPES.include?(spec["type"])) }.keys
    end

    def groupable_fields
      fields.select { |_, spec| spec.fetch("groupable", GROUPABLE_TYPES.include?(spec["type"])) }.keys
    end

    # Every "field asc"/"field desc" string Ransack will actually honour. Emitted as a JSON
    # Schema enum so a client that respects the schema cannot invent a sort key.
    def sort_options
      sortable_fields.flat_map { |f| ["#{f} asc", "#{f} desc"] }
    end

    # Scope names read from the HasScope query object itself rather than the YAML, so the
    # advertised list cannot drift from what `unrecognized_scope_error` will accept.
    def scope_names
      return [] if scope_spec.nil?

      scope_spec.fetch("query_class").constantize.scopes_configuration.keys.map(&:to_s)
    end

    def scope_descriptions = scope_spec&.fetch("descriptions", {}) || {}
    def compound_scopes? = scope_spec&.fetch("compound", false) || false

    # ---- Validation ---------------------------------------------------------------

    # Checks a client-supplied Ransack hash against the ontology.
    #
    # @param query [Hash] the client's `query` argument
    # @return [String, nil] an error message, or nil when every condition is usable
    def validate_query(query)
      problems = (query || {}).keys.map(&:to_s).filter_map do |key|
        if (argument = RESERVED_QUERY_KEYS[key])
          next "`#{key}` cannot be passed inside `query` — use the top-level `#{argument}` argument."
        end

        condition_error(key)
      end
      return nil if problems.empty?

      "#{problems.join(' ')} Filterable attributes: #{fields.keys.join(', ')}."
    end

    # @return [String, nil] why this single condition key cannot be used
    def condition_error(key)
      attribute, predicate = split_condition(key)

      if (spec = unavailable[attribute])
        hint = spec["use_instead"] ? " Use `#{spec['use_instead']}` instead." : ""
        return "`#{key}` is not usable: #{spec['reason'].squish}#{hint}"
      end

      if returned_only.key?(attribute)
        return "`#{key}` cannot be filtered or sorted: #{attribute} is computed after the " \
               "query, so it is only available on returned rows."
      end

      return "`#{key}` is not a known attribute of #{label.downcase}." unless fields.key?(attribute)

      return nil if predicate && predicates_for(attribute).include?(predicate)

      allowed = predicates_for(attribute).join(", ")
      if predicate.nil?
        "`#{key}` is missing a predicate — write `#{key}_eq` (allowed on #{attribute}: #{allowed})."
      else
        "`#{predicate}` is not an allowed predicate on #{attribute} (allowed: #{allowed})."
      end
    end

    # Splits "call_amount_gteq" into ["call_amount", "gteq"]. Matches the longest known
    # attribute name first so a field whose name ends in a predicate-like word (…_in, …_end)
    # is not mis-split.
    def split_condition(key)
      known = fields.keys + returned_only.keys + unavailable.keys
      attribute = known.select { |f| key == f || key.start_with?("#{f}_") }.max_by(&:length)
      return [key, nil] if attribute.nil?
      return [attribute, nil] if attribute == key

      [attribute, key.delete_prefix("#{attribute}_")]
    end

    # ---- Shared description sections -----------------------------------------------

    def filters_section
      return if fields.empty?

      lines = fields.map do |field, spec|
        "- #{field} (#{type_phrase(spec)}) — #{spec['description'].squish} " \
          "Predicates: #{predicates_for(field).join(', ')}."
      end
      "Filterable attributes, passed in `query` as attribute_predicate keys " \
        "(e.g. { \"#{fields.keys.first}_eq\": … }):\n#{lines.join("\n")}"
    end

    def returned_only_section
      return if returned_only.empty?

      lines = returned_only.map do |field, spec|
        formula = spec["formula"] ? " (= #{spec['formula']})" : ""
        "- #{field}#{formula} — #{spec['description'].squish}"
      end
      "Returned on every row but NOT filterable, sortable or aggregatable:\n#{lines.join("\n")}"
    end

    def unavailable_section
      return if unavailable.empty?

      lines = unavailable.map do |field, spec|
        hint = spec["use_instead"] ? " Use `#{spec['use_instead']}`." : ""
        "- #{field} — #{spec['reason'].squish}#{hint}"
      end
      "Do NOT use these — the call will be rejected:\n#{lines.join("\n")}"
    end

    def relationships_section
      return if relationships.empty?

      lines = relationships.map do |assoc, spec|
        tool = spec["resolve_with"] ? " Tool: #{spec['resolve_with']}." : ""
        "- #{assoc} (#{spec['cardinality'].tr('_', '-')} #{spec['target']}) — #{spec['note'].squish}#{tool}"
      end
      "Related data:\n#{lines.join("\n")}"
    end

    def measures_section
      return if measures.empty?

      lines = measures.map { |m, spec| "- #{m} = #{spec['expression']} — #{spec['description'].squish}" }
      "Measure definitions (use these, do not invent your own):\n#{lines.join("\n")}"
    end

    def caveats_section
      return if caveats.empty?

      "Important:\n#{caveats.map { |c| "- #{c.squish}" }.join("\n")}"
    end

    def type_phrase(spec)
      case spec["type"]
      when "money" then "money in #{spec['currency']}, filtered in major units"
      when "percent" then "percent, #{spec['scale']}"
      when "reference" then "id of a #{spec['target']}"
      when "enum" then "one of: #{Array(spec['values']).join(', ')}"
      else spec["type"]
      end
    end
  end

  # One tool over one entity. `kind: list` gets the Ransack query surface; `kind: detail`
  # takes a single key and returns one record.
  class Tool
    attr_reader :entity, :name, :spec

    def initialize(entity, name, spec)
      @entity = entity
      @name = name
      @spec = spec
    end

    def kind = spec.fetch("kind")
    def list? = kind == "list"
    def summary = spec.fetch("summary")
    def notes = Array(spec["notes"])
    def param_names = params_spec.keys
    def required_params = params_spec.select { |_, o| o.is_a?(Hash) && o["required"] }.keys
    def queryable? = spec.fetch("queryable", list?)
    def aggregatable? = spec.fetch("aggregatable", list?)
    def aggregate_required? = spec.fetch("aggregate_required", false)
    def require_one_of = Array(spec["require_one_of"])
    def returns = spec["returns"] || {}

    # An empty YAML key parses as nil, which `fetch`'s default never sees.
    def params_spec = spec["params"] || {}

    # ---- Generated tool surface ----------------------------------------------------

    def description
      sections =
        if list?
          [headline, notes_section, scopes_section,
           (entity.filters_section if queryable?),
           entity.returned_only_section, entity.unavailable_section,
           entity.relationships_section, entity.measures_section,
           usage_section, entity.caveats_section]
        else
          [headline, notes_section, returns_section, entity.relationships_section,
           entity.caveats_section]
        end
      sections.compact_blank.join("\n\n")
    end

    def input_schema
      properties = declared_params
      properties = properties.merge(list_params) if list?
      required = required_params
      required += ["aggregate"] if aggregate_required?
      { properties: properties, required: required }
    end

    # ---- Validation ----------------------------------------------------------------

    # One check for everything a client can get wrong, so a tool body stays three lines.
    #
    # @return [String, nil] an error message, or nil when the call is usable
    def validate_call(query: nil, sort: nil, scope: nil, aggregate: nil,
                      aggregate_field: nil, group_by_field: nil)
      if queryable? && (query_error = entity.validate_query(query))
        return query_error
      end

      if aggregate.present? && (!aggregatable? || aggregate_options.exclude?(aggregate.to_s))
        return "`#{aggregate}` is not a valid aggregate for #{name}." unless aggregatable?

        return "`#{aggregate}` is not a valid aggregate for #{name}. " \
               "Valid values: #{aggregate_options.join(', ')}."
      end

      if sort.present? && entity.sort_options.exclude?(sort.to_s)
        return "`#{sort}` is not a sortable field on #{name}. " \
               "Valid sort values: #{entity.sort_options.join(', ')}."
      end

      return "`#{scope}` is not a valid scope for #{name}. Valid scopes: #{entity.scope_names.join(', ')}." if scope.present? && !entity.compound_scopes? && entity.scope_names.exclude?(scope.to_s)

      if aggregate_field.present? && aggregate_fields.exclude?(aggregate_field.to_s)
        return "`#{aggregate_field}` cannot be aggregated on #{name}. " \
               "Valid aggregate_field values: #{aggregate_fields.join(', ')}."
      end

      if group_by_field.present? && entity.groupable_fields.exclude?(group_by_field.to_s)
        return "`#{group_by_field}` cannot be grouped on #{name}. " \
               "Valid group_by_field values: #{entity.groupable_fields.join(', ')}."
      end

      if aggregate.to_s == "sum" && aggregate_field.to_s == COUNT_FIELD
        return "aggregate_field: '#{COUNT_FIELD}' counts rows and is only honoured by " \
               "aggregate: 'group_by'. To count rows, use aggregate: 'count'."
      end

      return unless aggregate.to_s == "group_by" && group_by_field.blank?

      "aggregate: 'group_by' also needs `group_by_field` and `aggregate_field` " \
        "(pass aggregate_field: '#{COUNT_FIELD}' to count rows per group)."
    end

    def aggregate_fields = entity.aggregatable_fields + [COUNT_FIELD]

    # `sum` is only offered when the entity has something summable: otherwise
    # aggregate_fields holds nothing but the row-count sentinel and every sum is a
    # guaranteed error. The schema and the validator both read this, so the prose, the
    # enum and the rejection cannot disagree.
    def aggregate_options
      entity.aggregatable_fields.any? ? %w[count sum group_by] : %w[count group_by]
    end

    private

    def headline
      verb = list? ? "List" : "Get"
      plural = list? ? "s" : ""
      "#{verb} #{entity.label.downcase}#{plural} the current user is authorised to see. " \
      "#{entity.summary.squish} #{summary.squish}".squish
    end

    def notes_section
      return if notes.empty?

      notes.map(&:squish).join("\n")
    end

    def returns_section
      return if returns.empty?

      lines = returns.map { |field, text| "- #{field} — #{text.squish}" }
      "Returns:\n#{lines.join("\n")}"
    end

    def scopes_section
      return if param_names.exclude?("scope") || entity.scope_names.empty?

      lines = entity.scope_names.map do |scope|
        described = entity.scope_descriptions[scope]
        described ? "- #{scope} — #{described.squish}" : "- #{scope}"
      end
      header = if entity.compound_scopes?
                 "Predefined `scope` filters. Combine several with commas (e.g. 'actuals,quarterly'):"
               else
                 "Predefined `scope` filters (pass at most one):"
               end
      "#{header}\n#{lines.join("\n")}"
    end

    def usage_section
      parts = []
      parts << if aggregate_required?
                 "`aggregate` is REQUIRED — this tool never returns individual rows."
               elsif aggregatable? && entity.aggregatable_fields.any?
                 "For counts and totals use `aggregate` (count/sum/group_by) rather than " \
                   "fetching rows and counting them; `group_by` needs `group_by_field` and " \
                   "`aggregate_field` (pass aggregate_field: \"#{COUNT_FIELD}\" to count rows per group)."
               elsif aggregatable?
                 "For counts use `aggregate` (count/group_by) rather than fetching rows and " \
                   "counting them. Nothing on this entity is summable, so there is no `sum`; " \
                   "`group_by` needs `group_by_field` plus aggregate_field: \"#{COUNT_FIELD}\"."
               end
      parts << "Always pass `sort` and `limit`; without a limit a ROW result is capped at " \
               "#{MAX_ROWS}. The cap does not apply to aggregates — a group_by returns every " \
               "group, so group on a low-cardinality field and filter first."
      parts << "At least one of #{require_one_of.join(', ')} is REQUIRED — unfiltered calls are rejected." if require_one_of.any?
      parts.compact.join(" ")
    end

    # Params the YAML names, with any per-tool override merged over the shared definition.
    def declared_params
      params_spec.to_h do |param, override|
        base = SHARED_PARAMS[param] || {}
        merged = base.merge(override || {}).except("required")
        merged = scope_param if param == "scope" && merged.empty?
        [param.to_sym, merged.symbolize_keys]
      end
    end

    def scope_param
      if entity.compound_scopes?
        { "type" => "string",
          "description" => "Comma-separated scope filters from: #{entity.scope_names.join(', ')}." }
      else
        { "type" => "string", "enum" => entity.scope_names,
          "description" => "Predefined filter; see the tool description for what each one means." }
      end
    end

    def list_params
      params = {}
      if queryable?
        params[:query] = {
          type: "object",
          description: "Ransack conditions as attribute_predicate keys, e.g. " \
                       "{ \"#{entity.fields.keys.first}_eq\": … }. Unknown attributes are rejected " \
                       "with an explanatory error rather than silently ignored."
        }
      end
      params[:sort] = {
        type: "string", enum: entity.sort_options,
        description: "Sort order. Always provide one for 'top'/'latest'/'largest' questions."
      }
      params[:limit] = {
        type: "integer", minimum: 1, maximum: MAX_ROWS,
        description: "Max rows to return. Always provide one; defaults to #{MAX_ROWS}."
      }
      params.merge!(aggregate_params) if aggregatable?
      params
    end

    def aggregate_params
      {
        aggregate: {
          # `sum` is omitted when the entity has nothing summable: aggregate_fields would
          # then offer only the row-count sentinel, so every `sum` call is guaranteed to
          # fail and a model that picks it can only retry.
          type: "string", enum: aggregate_options,
          description: aggregate_required? ? "REQUIRED. Individual rows are never returned." : "Aggregate instead of returning rows."
        },
        aggregate_field: {
          type: "string", enum: aggregate_fields,
          description: if entity.aggregatable_fields.any?
                         "Field to sum. Required for aggregate: 'sum' and aggregate: 'group_by'. " \
                           "With group_by only, pass \"#{COUNT_FIELD}\" to count rows per group " \
                           "instead of summing; for a plain row count use aggregate: 'count'."
                       else
                         "Nothing on this entity is summable, so \"#{COUNT_FIELD}\" is the only " \
                           "value: pass it with aggregate: 'group_by' to count rows per group."
                       end
        },
        group_by_field: {
          type: "string", enum: entity.groupable_fields,
          description: "Dimension to group by. Required when aggregate is 'group_by'."
        }
      }
    end
  end
end
