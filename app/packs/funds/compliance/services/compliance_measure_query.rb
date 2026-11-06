# ④ Turns a pack measure into a number (or one number per group) for one fund, as of a date.
# Aggregates run in SQL over catalogue sources only; expressions combine measures with + - * / min max.
# A missing input (unmapped group, blank fund figure) raises MissingInput, which the evaluator turns
# into "Could not check — missing: <input>" — never a pass (X24, X29).
# Worked examples H2, H3, H20, H21, E22, E23, E30, E123, E124, E131, X24, X29 — openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceMeasureQuery
  class MissingInput < StandardError
    attr_reader :input_label

    def initialize(input_label)
      @input_label = input_label
      super("missing: #{input_label}")
    end
  end

  # value: BigDecimal (scalar) or nil; groups: {group_id => BigDecimal} for grouped figures
  Figure = Struct.new(:value, :groups, :labels, :steps, keyword_init: true) do
    def grouped?
      !groups.nil?
    end
  end

  # Everything a measure needs about the run; caches measure values for one fund run
  Context = Struct.new(:fund, :as_of, :setup, :version, :cache, keyword_init: true) do
    def measure(key)
      version.measures.detect { |m| m["key"] == key }
    end

    def input(key)
      version.inputs.detect { |i| i["key"] == key } || {}
    end
  end

  FILTER_NODES = {
    "eq" => Arel::Nodes::Equality, "ne" => Arel::Nodes::NotEqual, "gt" => Arel::Nodes::GreaterThan,
    "gte" => Arel::Nodes::GreaterThanOrEqual, "lt" => Arel::Nodes::LessThan, "lte" => Arel::Nodes::LessThanOrEqual
  }.freeze

  def self.call(measure, context)
    new(context).value_of(measure)
  end

  def self.context(fund:, as_of:, setup:, version:)
    Context.new(fund:, as_of:, setup:, version:, cache: {})
  end

  def initialize(context)
    @ctx = context
  end

  # Value of a measure hash, memoised per run
  def value_of(measure)
    key = measure["key"]
    return @ctx.cache[key] if key && @ctx.cache.key?(key)

    fig = compute_measure(measure)
    @ctx.cache[key] = fig if key
    fig
  end

  # Evaluate an expression: a number, a measure key, or [op, a, b, ...]
  def evaluate(expr)
    case expr
    when Numeric then Figure.new(value: expr.to_d)
    when String
      m = @ctx.measure(expr)
      raise ComplianceDataCatalog::UnknownField, "Unknown measure: #{expr}" unless m

      value_of(m)
    when Array then combine(expr.first.to_s, expr.drop(1).map { |e| evaluate(e) })
    else raise ArgumentError, "Bad expression"
    end
  end

  private

  def compute_measure(measure)
    case measure["op"]
    when "expr" then evaluate(measure["expr"])
    when "input" then input_figure(measure)
    else aggregate(measure)
    end
  end

  # A per-fund figure the entity enters in setup (e.g. estimated expenses); blank → MissingInput (X24)
  def input_figure(measure)
    input = @ctx.input(measure["input"])
    label = input["label"].presence || measure["input"].to_s.humanize.downcase
    value = @ctx.setup&.fund_figure(measure["input"], @ctx.fund)
    raise MissingInput, label if value.nil?

    Figure.new(value:)
  end

  # SQL aggregate over one catalogue source, optionally grouped
  def aggregate(measure)
    source = measure["source"]
    scope = base_scope(source)
    scope = apply_filters(scope, source, measure["filters"])
    op = measure["op"]
    group_sql = measure["group_by"].present? ? ComplianceDataCatalog.source(source).groups.fetch(measure["group_by"]) : nil
    field_sql = measure["field"].present? ? ComplianceDataCatalog.field_sql(source, measure["field"]) : nil

    if group_sql
      grouped = run_grouped(scope, op, group_sql, field_sql)
      Figure.new(groups: grouped.transform_values(&:to_d), labels: group_labels(source, measure["group_by"], grouped.keys))
    else
      Figure.new(value: run_scalar(scope, op, field_sql).to_d)
    end
  end

  def run_scalar(scope, op, field_sql)
    case op
    when "sum" then scope.sum(Arel.sql(field_sql)) || 0
    when "count" then scope.count
    # unscope(:order) before distinct — MySQL refuses ORDER BY columns outside the select list
    when "count_distinct" then scope.unscope(:order).distinct.count(Arel.sql(field_sql))
    when "max" then scope.maximum(Arel.sql(field_sql)) || 0
    when "min" then scope.minimum(Arel.sql(field_sql)) || 0
    end
  end

  def run_grouped(scope, op, group_sql, field_sql)
    grouped = scope.unscope(:order).group(Arel.sql(group_sql))
    result = case op
             when "sum" then grouped.sum(Arel.sql(field_sql))
             when "count" then grouped.count
             when "count_distinct" then grouped.distinct.count(Arel.sql(field_sql))
             when "max" then grouped.maximum(Arel.sql(field_sql))
             when "min" then grouped.minimum(Arel.sql(field_sql))
             end
    result.reject { |k, _| k.nil? }.transform_values { |v| v || 0 }
  end

  # Records of the fund, as of the run date (backdated rows count once their date ≤ as_of — E123).
  # A row with no date at all (e.g. a commitment imported without a commitment date) still belongs to
  # the fund and counts — dropping it would understate corpus and turn a breach into a pass (R107).
  # Soft-deleted rows are excluded by the models' default scopes (E124).
  def base_scope(source)
    src = ComplianceDataCatalog.source(source)
    model = ComplianceDataCatalog.model(source)
    scope = if source == "investor_kycs"
              model.where(entity_id: @ctx.fund.entity_id, investor_id: CapitalCommitment.where(fund_id: @ctx.fund.id).select(:investor_id))
            else
              model.where(entity_id: @ctx.fund.entity_id, fund_id: @ctx.fund.id)
            end
    if src.date && @ctx.as_of
      date = model.arel_table[src.date]
      scope = scope.where(date.lteq(@ctx.as_of).or(date.eq(nil)))
    end
    scope
  end

  def apply_filters(scope, source, filters)
    Array(filters).reduce(scope) { |s, f| apply_filter(s, source, *f) }
  end

  # Filters compile to Arel nodes: the column side is a catalogue SQL fragment (frozen allowlist or a
  # regex-checked custom field), the value side is always quoted — nothing from a definition is interpolated.
  def apply_filter(scope, source, field, op, value)
    case field.to_s
    when "investor_group" then investor_group_filter(scope, op, value)
    when "transaction"
      column = Arel.sql(ComplianceDataCatalog.field_sql(source, "quantity"))
      # buys are positive quantities, sells negative (PortfolioInvestment#buy?) — E127
      scope.where(value.to_s == "sell" ? Arel::Nodes::LessThan.new(column, 0) : Arel::Nodes::GreaterThan.new(column, 0))
    else
      scope.where(filter_node(Arel.sql(ComplianceDataCatalog.field_sql(source, field)), op.to_s, value))
    end
  end

  def filter_node(column, op, value)
    case op
    when "in" then Arel::Nodes::In.new(column, Array(value).map { |v| Arel::Nodes.build_quoted(v) })
    when "not_in" then Arel::Nodes::NotIn.new(column, Array(value).map { |v| Arel::Nodes.build_quoted(v) })
    else FILTER_NODES.fetch(op).new(column, Arel::Nodes.build_quoted(value))
    end
  end

  # Investors in (or not in) a mapped group, e.g. the sponsor/manager categories (X29)
  def investor_group_filter(scope, op, input_key)
    categories = @ctx.setup&.group_categories(input_key)
    input = @ctx.input(input_key)
    label = input["label"].presence || input_key.to_s.humanize
    # An optional group (e.g. employees) left unmapped is simply empty; a required one is missing (X29)
    categories = [] if categories.nil? && input["optional"]
    raise MissingInput, label if categories.nil?

    ids = Investor.where(entity_id: @ctx.fund.entity_id, category: categories).select(:id)
    op.to_s == "not_in" ? scope.where.not(investor_id: ids) : scope.where(investor_id: ids)
  end

  def group_labels(source, group, keys)
    return keys.index_with(&:to_s) unless ComplianceDataCatalog.source(source).label_for[group] == :investor

    Investor.where(id: keys).pluck(:id, :investor_name).to_h
  end

  # Element-wise arithmetic; a grouped operand makes the result grouped
  def combine(op, figures)
    if figures.any?(&:grouped?)
      keys = figures.select(&:grouped?).flat_map { |f| f.groups.keys }.uniq
      labels = figures.select(&:grouped?).filter_map(&:labels).reduce({}, :merge)
      groups = keys.index_with do |k|
        apply_op(op, figures.map { |f| f.grouped? ? f.groups.fetch(k, 0.to_d) : f.value })
      end
      Figure.new(groups:, labels:)
    else
      Figure.new(value: apply_op(op, figures.map(&:value)))
    end
  end

  def apply_op(op, values)
    return nil if values.any?(&:nil?)

    case op
    when "+" then values.sum
    when "-" then values.drop(1).reduce(values.first) { |a, b| a - b }
    when "*" then values.reduce(1.to_d) { |a, b| a * b }
    when "/" then values.drop(1).reduce(values.first) { |a, b| b.zero? ? nil : (a && (a / b)) }
    when "min" then values.min
    when "max" then values.max
    end
  end
end
