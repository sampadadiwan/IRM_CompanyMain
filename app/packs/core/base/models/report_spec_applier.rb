# Writes a new Report Builder report from a report spec — the short form that
# templates (config/report_builder_templates.yml), Duplicate and, later, the
# assistant all use:
#
#   root_model: Investor
#   columns:  [{ key:, label:?, total:? } | { formula: key } | { pivot: relation }]   (column order)
#   joins:    [{ relation:, child_filters:?, only_with_rows:?, pivot:? }]
#   root_filters: { "<field>_<op>" => value }
#   formulas: [{ key:, label:, expression: }]
#   sort: { key:, dir: }   group_rows_by:   currency:
#
# In one transaction it checks the spec (ReportSpecValidator), places the fund
# (ReportBuilderFundTarget — the guided setup's rule), fills what the builder
# derives (related data's model / foreign key, default totals, formula keys)
# and creates the column rows — formula and pivot positions included — so the
# report is exactly what the builder would have saved. spec_from reads a
# report back into a spec (Duplicate, and the assistant's refinements).
# replace: true rewrites an existing report — the assistant's draft — keeping
# only its own keys (draft, ai, chart).
# Worked examples H4–H9, X5 — openspec/changes/report-builder-starting-points/business-rules.md;
# assistant H2–H4 — openspec/changes/report-builder-assistant/business-rules.md
class ReportSpecApplier
  class Invalid < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super(errors.join("; "))
    end
  end

  FORMULA_PREFIX = "formula_".freeze
  # Template keys that belong to the report, not its spec, and survive a replace
  KEPT_ON_REPLACE = %w[draft ai chart].freeze
  SPEC_JOIN_KEYS = %w[relation child_filters only_with_rows pivot].freeze

  class << self
    # Saves `report` (new, with name / entity / user set) with the spec's set-up.
    # validate: false copies a report as it is (Duplicate keeps an imperfect
    # report imperfect; the report check then shows what's wrong).
    def apply!(report:, spec:, fund: nil, validate: true, replace: false)
      spec = spec.deep_stringify_keys
      Report.transaction do
        # X5 — a spec that isn't allowed creates nothing
        if validate
          errors = ReportSpecValidator.errors_for(spec, entity: report.entity, name: report.name)
          raise Invalid, errors if errors.any?
        end

        template = template_for(spec)
        place_fund(template, fund) if fund
        if replace
          # The assistant's draft: its old columns go, its own state stays
          kept = (report.template || {}).deep_stringify_keys.slice(*KEPT_ON_REPLACE)
          template = template.merge(kept)
          report.grid_view_preferences.delete_all
        end
        report.template = template
        report.save!
        create_columns(report, spec, template)
      end
      report
    end

    # The spec of an existing report (Duplicate): its columns in order with
    # their labels and totals, related data, filters, formulas, sort, grouping
    # and currency. Never its pending Undo or schedule.
    def spec_from(report)
      template = (report.template || {}).deep_stringify_keys
      aggregates = template["aggregates"] || {}
      columns = report.grid_view_preferences.reorder(:sequence, :id).map do |gvp|
        if gvp.key.start_with?("formula:") then { "formula" => gvp.key.delete_prefix("formula:") }
        elsif gvp.key.start_with?("pivot:") then { "pivot" => gvp.key.delete_prefix("pivot:") }
        else
          clean = gvp.key.split(";").first.strip
          { "key" => gvp.key, "label" => gvp.label.presence || gvp.name, "total" => aggregates[clean] || aggregates[gvp.key] }.compact
        end
      end

      {
        "root_model" => template["root_model"], "columns" => columns,
        "joins" => (template["joins"] || []).map { |j| j.slice(*SPEC_JOIN_KEYS) },
        "root_filters" => template["root_filters"] || {}, "formulas" => template["formulas"] || [],
        "sort" => template["sort"] || {}, "group_rows_by" => template["group_rows_by"], "currency" => template["currency"]
      }.compact
    end

    private

    # Spec → the report's template JSON, as the builder stores it
    def template_for(spec)
      root = spec["root_model"].to_s.constantize
      joins = Array(spec["joins"]).map { |join| join_for(root, join) }
      config = ReportBuilderConfig.new("root_model" => root.name, "joins" => joins)

      {
        "version" => 1, "root_model" => root.name, "joins" => joins,
        "aggregates" => aggregates_for(spec, config),
        "root_filters" => spec["root_filters"] || {},
        "formulas" => Array(spec["formulas"]).map { |f| f.slice("label", "expression").merge("key" => formula_key(f["key"])) },
        "sort" => sort_for(spec),
        "group_rows_by" => spec["group_rows_by"].presence, "currency" => spec["currency"].presence
      }.compact
    end

    # Related data as the builder saves it: model and foreign key from the association
    def join_for(root, join)
      relation = join["relation"].to_s
      klass = ReportBuilderColumnCatalog.related_class(root, relation)
      reflection = relation.include?(".") ? nil : root.reflect_on_association(relation.to_sym)
      fk = reflection&.foreign_key&.to_s
      join.slice(*SPEC_JOIN_KEYS).merge("model" => klass&.name, "fk" => fk).compact
    end

    # The spec's total, or the default for the column's type (as adding it in the builder would)
    def aggregates_for(spec, config)
      Array(spec["columns"]).each_with_object({}) do |col, aggregates|
        key = col["key"].to_s.split(";").first.to_s.strip
        next unless key.include?(".")

        total = col["total"].presence || config.column_type.default_aggregate(key)
        aggregates[key] = total if total
      end
    end

    # A sort on a formula names the stored formula key
    def sort_for(spec)
      sort = (spec["sort"] || {}).slice("key", "dir")
      return {} if sort["key"].blank?

      formula = Array(spec["formulas"]).find { |f| f["key"].to_s == sort["key"].to_s }
      formula ? sort.merge("key" => formula_key(formula["key"])) : sort
    end

    # "called_pct" → "formula_called_pct"; keys already stored keep theirs (Duplicate)
    def formula_key(key)
      key.to_s.start_with?(FORMULA_PREFIX) ? key.to_s : "#{FORMULA_PREFIX}#{key}"
    end

    # The fund on the rows when they have one, else on each related data with a fund
    def place_fund(template, fund)
      target = ReportBuilderFundTarget.for(ReportBuilderConfig.new(template))
      if target[:root]
        template["root_filters"] = template["root_filters"].merge("fund_id_eq" => fund.id.to_s)
      else
        template["joins"].each do |join|
          next unless target[:relations].include?(join["relation"].to_s)

          join["child_filters"] = (join["child_filters"] || {}).merge("fund_id_eq" => fund.id.to_s)
        end
      end
    end

    # One row per column in spec order; formulas and pivots as position rows (Phase 1)
    def create_columns(report, spec, template)
      config = ReportBuilderConfig.new(template)
      formulas = Array(spec["formulas"]).index_by { |f| f["key"].to_s }
      Array(spec["columns"]).each_with_index do |col, i|
        key, label = column_row(col, formulas, config)
        report.grid_view_preferences.create!(key: key, name: label, label: label,
                                             entity_id: report.entity_id, sequence: i + 1)
      end
    end

    def column_row(col, formulas, config)
      if col["formula"]
        formula = formulas[col["formula"].to_s]
        ["formula:#{formula_key(col['formula'])}", formula&.dig("label") || col["formula"].to_s]
      elsif col["pivot"]
        ["pivot:#{col['pivot']}", "#{col['pivot'].to_s.humanize} (pivot)"]
      else
        [col["key"], col["label"].presence || ReportBuilderColumnCatalog.label_for(config, col["key"])]
      end
    end
  end
end
