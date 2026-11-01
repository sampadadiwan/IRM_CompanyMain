# Keeps the parts of an AI-written report spec that the Report Builder allows,
# and says why each other part was left out ("Couldn't do"). Every part is
# checked with ReportSpecValidator — the same rules as the starter templates —
# one part at a time, so one bad column doesn't throw the whole draft away:
#
#   table      a report table whose feature the company has
#   related    each related data that resolves (and whose feature is on)
#   columns    each column, with its total
#   filters    each filter — never on the company itself, and for a field with
#              a list of values (yes/no, a fund, few text values) only values
#              that exist: "No capital remittances have Status Overdu — values: …"
#   pivots, formulas, sort, Excel grouping, currency — each on what was kept
#
#   ReportSpecPruner.prune(spec, entity:) → [clean_spec, ["<problem>", …]]
#
# Worked examples E2, E4, X3, X5 — openspec/changes/report-builder-assistant/business-rules.md
class ReportSpecPruner
  VALUE_OPS = %w[eq not_eq in].freeze
  LISTED_KINDS = %i[boolean fund choice].freeze

  def self.prune(spec, entity:)
    new(spec, entity).prune
  end

  def initialize(spec, entity)
    @spec     = spec.is_a?(Hash) ? spec.deep_stringify_keys : {}
    @entity   = entity
    @problems = []
  end

  def prune
    # The table first: nothing else can be checked without it (E4)
    root = ReportBuilderModelDiscovery.roots.find { |klass| klass.name == @spec["root_model"].to_s }
    return [{}, ["#{table_words(@spec['root_model'])} aren't available in reports for your account"]] unless root && ReportBuilderModelDiscovery.pack_enabled_for?(root, @entity)

    @root = root
    @kept = { "root_model" => root.name, "columns" => [], "joins" => [], "root_filters" => {}, "formulas" => [], "sort" => {} }

    keep_joins
    keep_columns
    keep_filters
    keep_pivots
    keep_formulas
    keep_order
    order_columns_as_given

    [@kept, @problems.uniq]
  end

  private

  def list(key)
    Array(@spec[key]).grep(Hash)
  end

  # The validator's first complaint about the kept spec with one more part, or nil
  def problem_with(candidate)
    ReportSpecValidator.new(candidate).errors.first
  end

  def try(candidate)
    problem = problem_with(candidate)
    @problems << problem if problem
    problem.nil?
  end

  # Related data that resolves, without its filters / pivot yet
  def keep_joins
    list("joins").each do |join|
      relation = join["relation"].to_s
      klass = ReportBuilderColumnCatalog.related_class(@root, relation)
      if klass && !ReportBuilderModelDiscovery.pack_enabled_for?(klass, @entity)
        @problems << "#{table_words(klass.name)} aren't available in reports for your account"
        next
      end

      bare = join.slice("relation", "only_with_rows")
      @kept["joins"] << bare if try(@kept.merge("joins" => @kept["joins"] + [bare]))
    end
  end

  def kept_relations
    @kept["joins"].pluck("relation")
  end

  # Each catalog column, alone with the kept related data
  def keep_columns
    list("columns").each do |col|
      next if col["formula"] || col["pivot"]

      @kept["columns"] << col.slice("key", "label", "total") if try(@kept.merge("columns" => [col.slice("key", "label", "total")]))
    end
  end

  def keep_filters
    @kept["root_filters"] = kept_filters(nil, @spec["root_filters"])
    @kept["joins"].each do |join|
      given = list("joins").find { |j| j["relation"].to_s == join["relation"] }
      filters = kept_filters(join["relation"], given&.dig("child_filters"))
      join["child_filters"] = filters if filters.any?
    end
  end

  def kept_filters(relation, filters)
    return {} unless filters.is_a?(Hash)

    filters.each_with_object({}) do |(pred_key, value), kept|
      field, op = ReportBuilderFilterField.split_predicate(pred_key)
      # X5 — the engine scopes to the company; a filter on it is never needed
      if field.to_s.end_with?("entity_id")
        @problems << "Filters on the company itself can't be used"
        next
      end

      candidate = relation ? with_join_filter(relation, pred_key, value) : @kept.merge("root_filters" => { pred_key => value })
      next unless try(candidate)
      next unless value_exists?(relation, field, op, value)

      kept[pred_key] = value
    end
  end

  def with_join_filter(relation, pred_key, value)
    joins = @kept["joins"].map { |j| j["relation"] == relation ? j.merge("child_filters" => { pred_key => value }) : j }
    @kept.merge("joins" => joins)
  end

  # E2 — a value of a listed field must be one of its values
  def value_exists?(relation, field, op, value)
    return true unless VALUE_OPS.include?(op)

    info  = ReportBuilderFilterField.new(config: kept_config, key: field, entity: @entity, relation: relation)
    label = ReportBuilderColumnCatalog.label_for(kept_config, [relation, field].compact.join("."))
    table = table_words(relation || @root.name)

    # Yes/no, funds and few-valued text: every value must be one of the list
    if LISTED_KINDS.include?(info.kind)
      missing = Array(value).map(&:to_s) - info.options.map { |_, v| v.to_s }
      return true if missing.empty?

      @problems << "No #{table} have #{label} #{missing.to_sentence} — values: #{info.options.map(&:first).join(', ')}"
      return false
    end

    # Other text (many values, or one of the largest tables): one indexed EXISTS, no list
    return true unless text_value_missing?(relation, field, op, value)

    @problems << "No #{table} have #{label} #{Array(value).to_sentence}"
    false
  end

  def text_value_missing?(relation, field, op, value)
    klass = relation ? ReportBuilderColumnCatalog.related_class(@root, relation) : @root
    return false unless op == "eq" && klass&.column_names&.include?("entity_id") && klass.columns_hash[field]&.type == :string

    !klass.exists?(entity_id: @entity.id, field => value.to_s)
  end

  def kept_config
    ReportBuilderConfig.new("root_model" => @root.name, "joins" => @kept["joins"])
  end

  def keep_pivots
    @kept["joins"].each do |join|
      pivot = list("joins").find { |j| j["relation"].to_s == join["relation"] }&.dig("pivot")
      next unless pivot.is_a?(Hash)

      joins = @kept["joins"].map { |j| j.equal?(join) ? j.merge("pivot" => pivot) : j }
      join["pivot"] = pivot if try(@kept.merge("joins" => joins))
    end
  end

  # Formulas over the kept columns only
  def keep_formulas
    list("formulas").each do |formula|
      @kept["formulas"] << formula.slice("key", "label", "expression") if try(@kept.merge("formulas" => @kept["formulas"] + [formula]))
    end
  end

  def keep_order
    sort = @spec["sort"].is_a?(Hash) ? @spec["sort"].slice("key", "dir") : {}
    @kept["sort"] = sort if sort["key"].present? && try(@kept.merge("sort" => sort))
    { "group_rows_by" => @spec["group_rows_by"], "currency" => @spec["currency"] }.compact_blank.each do |key, value|
      @kept[key] = value if try(@kept.merge(key => value))
    end
  end

  # Columns back in the order given, with the formula and pivot positions that survived
  def order_columns_as_given
    formula_keys = @kept["formulas"].map { |f| f["key"].to_s }
    pivots = @kept["joins"].select { |j| j["pivot"] }.pluck("relation")
    kept_keys = @kept["columns"].pluck("key")
    @kept["columns"] = list("columns").filter_map do |col|
      if col["formula"]
        { "formula" => col["formula"].to_s } if formula_keys.include?(col["formula"].to_s)
      elsif col["pivot"]
        { "pivot" => col["pivot"].to_s } if pivots.include?(col["pivot"].to_s)
      elsif kept_keys.include?(col["key"])
        @kept["columns"].find { |c| c["key"] == col["key"] }
      end
    end
  end

  # "SecondarySale" / "capital_remittances" → "secondary sales" / "capital remittances"
  def table_words(name)
    name.to_s.underscore.humanize.downcase.pluralize
  end
end
