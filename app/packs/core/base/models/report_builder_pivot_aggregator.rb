# Handles pivot aggregation for a single child relation.
# Produces one dynamic column per distinct value of the group_by column,
# using CASE WHEN SQL so the entire pivot runs in a single query.
#
# Example: pivot { group_by: "name", value_col: "amount", aggregate: "sum" }
# produces columns "Management Fees (sum)", "Setup Fees (sum)", etc.
class ReportBuilderPivotAggregator
  def initialize(join_config:, root_ids:)
    @join_config = join_config.with_indifferent_access
    @root_ids    = root_ids
    @pivot       = @join_config[:pivot].with_indifferent_access
  end

  # Returns [Array<ReportBuilderDynamicColumn>, Hash{ root_id => { col_key => value } }]
  def call
    return [[], {}] if root_ids.empty?
    return [[], {}] if group_by.blank? || value_col.blank?

    distinct_values = discover_values
    return [[], {}] if distinct_values.empty?

    dyn_cols = build_dynamic_columns(distinct_values)
    data     = run_pivot_query(distinct_values)
    [dyn_cols, data]
  rescue ActiveRecord::StatementInvalid, ActiveRecord::UnknownAttributeReference,
         ArgumentError, NameError => e
    Rails.logger.warn "[ReportBuilderPivotAggregator] #{e.message}"
    [[], {}]
  end

  private

  attr_reader :join_config, :root_ids, :pivot

  def relation    = join_config[:relation].to_s
  def child_class = join_config[:model].constantize
  def fk          = join_config[:fk].to_s
  def group_by    = pivot[:group_by].to_s
  def value_col   = pivot[:value_col].to_s
  def aggregate   = pivot[:aggregate].to_s.presence || "sum"

  def child_filters
    (join_config[:child_filters] || {}).with_indifferent_access
  end

  def base_scope
    scope = child_class.where(fk => root_ids)
    child_filters.present? ? scope.ransack(child_filters).result : scope
  end

  def discover_values
    base_scope.distinct.order(group_by.to_sym).pluck(group_by).compact
  end

  def pivot_key(val)
    "#{relation}.#{value_col}__pivot__#{val}"
  end

  def build_dynamic_columns(values)
    values.map do |val|
      ReportBuilderDynamicColumn.new(
        key: pivot_key(val),
        label: "#{val} (#{aggregate})"
      )
    end
  end

  def run_pivot_query(values)
    return run_latest_pivot_query(values) if aggregate == "latest"

    result  = Hash.new { |h, k| h[k] = {} }
    db_col  = resolve_db_col(value_col)
    conn    = child_class.connection

    case_exprs = values.map do |val|
      safe = "pv_#{val.to_s.gsub(/[^a-z0-9]/i, '_')[0, 40]}_#{values.index(val)}"
      sql  = case_when_sql(db_col, aggregate, group_by, val, conn)
      { val: val, alias: safe, sql: "#{sql} AS `#{safe}`" }
    end

    fk_sql = Arel.sql("`#{child_class.table_name}`.`#{fk}`")
    base_scope
      .group(fk_sql)
      .select(fk_sql, *case_exprs.map { |e| Arel.sql(e[:sql]) })
      .each do |row|
        id = row.send(fk)
        case_exprs.each do |e|
          raw = row.send(e[:alias])
          result[id][pivot_key(e[:val])] = monetized?(value_col) ? cents_to_amount(raw) : raw
        end
      end

    result
  end

  def run_latest_pivot_query(values)
    result = Hash.new { |h, k| h[k] = {} }
    
    # Find latest ID per (root, category)
    latest_ids_scope = base_scope.group(fk, group_by)
    latest_ids_scope = child_class.respond_to?(:latest) ? latest_ids_scope.latest : latest_ids_scope
    latest_ids_query = latest_ids_scope.select("MAX(id)")

    # Fetch values for those IDs
    db_col_name = resolve_db_col(value_col)
    child_class
      .where(id: latest_ids_query)
      .select(fk, group_by, db_col_name)
      .each do |row|
        root_id = row.send(fk)
        cat_val = row.send(group_by)
        next unless values.include?(cat_val)

        raw = row.send(db_col_name)
        result[root_id][pivot_key(cat_val)] = monetized?(value_col) ? cents_to_amount(raw) : raw
      end

    result
  end

  def case_when_sql(db_col, agg, group_col, val, conn)
    when_clause = "CASE WHEN `#{group_col}` = #{conn.quote(val)} THEN `#{db_col}` END"
    case agg
    when "count" then "COUNT(#{when_clause})"
    when "avg"   then "AVG(#{when_clause})"
    when "min"   then "MIN(#{when_clause})"
    when "max"   then "MAX(#{when_clause})"
    when "list"  then "GROUP_CONCAT(DISTINCT #{when_clause} SEPARATOR ', ')"
    else              "SUM(#{when_clause})"
    end
  end

  def resolve_db_col(col)
    return col if child_class.column_names.include?(col)

    cents = "#{col}_cents"
    child_class.column_names.include?(cents) ? cents : col
  end

  def monetized?(col)
    child_class.column_names.exclude?(col) &&
      child_class.column_names.include?("#{col}_cents")
  end

  def cents_to_amount(val)
    return nil if val.nil?

    BigDecimal(val.to_s) / 100
  end
end
