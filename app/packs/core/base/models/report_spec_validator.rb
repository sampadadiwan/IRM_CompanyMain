# Says whether a report spec (the short description templates, Duplicate and,
# later, the assistant use — see ReportSpecApplier) only uses what the Report
# Builder itself allows: a report table, related data that resolves, columns
# from the column catalog, totals only where a column has many rows per row,
# filter fields that can be searched, formulas over the spec's own columns,
# pivot fields that are stored, and a sort / Excel grouping it can use.
#
# No second allow-list: every answer comes from ReportBuilderColumnCatalog,
# ReportBuilderColumnType and ReportBuilderModelDiscovery.
# Worked examples H12, X1, X5 —
# openspec/changes/report-builder-starting-points/business-rules.md
class ReportSpecValidator
  # ["<name>: <problem>", …] — empty when the spec is valid
  def self.errors_for(spec, entity:, name:)
    new(spec).errors.map { |problem| "#{name}: #{problem}" }
  end

  def initialize(spec)
    @spec = spec.deep_stringify_keys
  end

  def errors
    @root = ReportBuilderModelDiscovery.roots.find { |klass| klass.name == @spec["root_model"].to_s }
    return ["#{@spec['root_model']} isn't a report table"] unless @root

    # Related data must resolve before its columns can be checked
    join_problems = joins.filter_map { |join| join_problem(join["relation"].to_s) }
    return join_problems if join_problems.any?

    column_problems + filter_problems + formula_problems + pivot_problems + order_problems
  end

  private

  def joins
    Array(@spec["joins"])
  end

  def columns
    Array(@spec["columns"])
  end

  def formulas
    Array(@spec["formulas"])
  end

  # Just enough of a template for the column-type rules (root + related data)
  def config
    @config ||= ReportBuilderConfig.new("root_model" => @root.name, "joins" => joins.map { |j| { "relation" => j["relation"] } })
  end

  def column_type
    config.column_type
  end

  def table_label(relation)
    relation ? relation.to_s.humanize.downcase : ReportBuilder::Wizard.model_label(@root.name).pluralize.downcase
  end

  def column_keys
    @column_keys ||= columns.filter_map { |c| c["key"]&.split(";")&.first&.strip }
  end

  def formula_keys
    formulas.map { |f| f["key"].to_s }
  end

  def join_problem(relation)
    return if column_type.strategy_for(relation)

    "#{relation} isn't related data of #{table_label(nil)}"
  end

  # Each column: a catalog column (with an allowed total), a formula position or a pivot position
  def column_problems
    columns.flat_map do |col|
      if col["formula"]
        formula_keys.include?(col["formula"].to_s) ? [] : ["column formula #{col['formula']} has no formula"]
      elsif col["pivot"]
        joins.any? { |j| j["relation"].to_s == col["pivot"].to_s && j["pivot"] } ? [] : ["column pivot #{col['pivot']} has no pivot"]
      else
        catalog_column_problems(col)
      end
    end
  end

  def catalog_column_problems(col)
    key = col["key"].to_s.split(";").first.to_s.strip
    relation = key.include?(".") ? column_type.relation_for(key) : nil
    field = relation ? key.delete_prefix("#{relation}.") : key
    return ["#{key} isn't a column of #{table_label(relation)}"] unless catalog_column?(relation, field)

    total = col["total"]
    return [] if total.blank?
    return ["#{key} has an unknown total #{total}"] unless ReportBuilderColumnType::AGGREGATES.include?(total.to_s)
    # Totals only where there are several related rows per row
    return ["#{key} is one value per row and can't have a total"] unless column_type.default_aggregate(key)

    []
  end

  # Own columns must be readable on the row; related ones stored (they are totalled in SQL)
  def catalog_column?(relation, field)
    return ReportBuilderColumnCatalog.columns_for(@root).any? { |c| c[:key] == field } unless relation

    klass = ReportBuilderColumnCatalog.related_class(@root, relation)
    klass && ReportBuilderColumnCatalog.related_columns_for(klass).any? { |c| c[:key] == field }
  end

  def filter_problems
    own = filters_on(nil, @spec["root_filters"])
    related = joins.flat_map { |join| filters_on(join["relation"].to_s, join["child_filters"]) }
    own + related
  end

  def filters_on(relation, filters)
    klass = relation ? ReportBuilderColumnCatalog.related_class(@root, relation) : @root
    searchable = ReportBuilderColumnCatalog.filter_columns_for(klass).pluck(:key)
    (filters || {}).keys.filter_map do |pred_key|
      field, op = ReportBuilderFilterField.split_predicate(pred_key)
      next if op && searchable.include?(field)

      "filter #{pred_key} can't be used on #{table_label(relation)}"
    end
  end

  # Formulas use the spec's columns only, and must parse
  def formula_problems
    formulas.flat_map do |formula|
      refs = formula["expression"].to_s.scan(/\[([^\]]+)\]/).flatten.map { |r| r.split(";").first.strip }
      missing = refs.uniq - column_keys
      next missing.map { |ref| "formula #{formula['label']} uses #{ref}, which isn't a column" } if missing.any?

      result = ReportBuilderFormulaService.validate(formula["expression"], refs.index_with(1))
      result == true ? [] : ["formula #{formula['label']}: #{result}"]
    end
  end

  # Pivot categories and value must be stored columns of the related table
  def pivot_problems
    joins.select { |j| j["pivot"] }.flat_map do |join|
      relation = join["relation"].to_s
      klass = ReportBuilderColumnCatalog.related_class(@root, relation)
      pivot = join["pivot"]
      fields = Array(pivot["group_bys"]) + [pivot["value_col"]]
      fields.reject { |f| stored?(klass, f) }.map { |f| "pivot #{f} isn't a column of #{table_label(relation)}" }
    end
  end

  def stored?(klass, field)
    klass && (klass.column_names.include?(field.to_s) || klass.column_names.include?("#{field}_cents"))
  end

  # Sort by a column or formula of the spec; Excel grouping by a stored own column
  def order_problems
    problems = []
    sort_key = @spec.dig("sort", "key").to_s
    problems << "sort #{sort_key} isn't a column or formula" if sort_key.present? && (column_keys + formula_keys).exclude?(sort_key)
    group = @spec["group_rows_by"].to_s
    problems << "Excel grouping #{group} isn't a stored column of #{table_label(nil)}" if group.present? && !stored?(@root, group)
    problems
  end
end
