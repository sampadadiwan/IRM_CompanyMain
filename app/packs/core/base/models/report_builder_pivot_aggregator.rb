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
    return [[], {}] if group_bys.blank? || value_col.blank?

    # Validate all user-supplied column names against the table schema before
    # interpolating them into SQL. This prevents column-name injection.
    return [[], {}] unless valid_columns?

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
  def child_class = join_config[:base_class].to_s.constantize
  def fk          = join_config[:fk].to_s
  def joins       = join_config[:joins]
  def group_bys   = Array(pivot[:group_bys] || pivot[:group_by]).map(&:to_s).compact_blank
  def value_col   = pivot[:value_col].to_s
  def aggregate   = pivot[:aggregate].to_s.presence || "sum"

  def child_filters
    (join_config[:child_filters] || {}).with_indifferent_access
  end

  def base_scope
    scope = child_class.where(fk => root_ids)
    scope = scope.joins(joins.to_sym) if joins.present?
    child_filters.present? ? scope.ransack(child_filters).result : scope
  end

  def discover_values
    return [] if group_bys.empty?

    # If multiple group_bys, we want distinct combinations
    cols = group_bys.map { |gb| db_col(gb) }
    base_scope.distinct.order(cols.map { |c| Arel.sql(c) }).pluck(*cols.map { |c| Arel.sql(c) })
  end

  def pivot_key(val_combination)
    val_str = Array(val_combination).join(" | ")
    "#{relation}.#{value_col}__pivot__#{val_str}"
  end

  def build_dynamic_columns(combinations)
    combinations.map do |combo|
      label = Array(combo).join(" | ")
      ReportBuilderDynamicColumn.new(
        key: pivot_key(combo),
        label: "#{label} (#{aggregate})"
      )
    end
  end

  def run_pivot_query(combinations)
    return run_latest_pivot_query(combinations) if aggregate == "latest"

    result = Hash.new { |h, k| h[k] = {} }
    db_val_col = db_col(value_col)
    db_grp_cols = group_bys.map { |gb| db_col(gb) }
    conn = child_class.connection

    case_exprs = combinations.map do |combo|
      combo_vals = Array(combo)
      safe = "pv_#{combo_vals.join('_').gsub(/[^a-z0-9]/i, '_')[0, 40]}_#{combinations.index(combo)}"

      # Build multi-column WHEN clause
      when_parts = db_grp_cols.each_with_index.map do |col, i|
        "#{col} = #{conn.quote(combo_vals[i])}"
      end
      when_clause = "CASE WHEN #{when_parts.join(' AND ')} THEN #{db_val_col} END"

      sql = agg_for_sql(aggregate, when_clause)
      { combo: combo, alias: safe, sql: "#{sql} AS `#{safe}`" }
    end

    fk_sql = Arel.sql("`#{child_class.table_name}`.`#{fk}`")
    base_scope
      .group(fk_sql)
      .select(fk_sql, *case_exprs.map { |e| Arel.sql(e[:sql]) })
      .each do |row|
        id = row.send(fk)
        case_exprs.each do |e|
          raw = row.send(e[:alias])
          result[id][pivot_key(e[:combo])] = monetized?(value_col) ? cents_to_amount(raw) : raw
        end
      end

    result
  end

  def run_latest_pivot_query(combinations)
    result = Hash.new { |h, k| h[k] = {} }

    db_grp_cols = group_bys.map { |gb| db_col(gb) }

    # Find latest ID per (root, categories)
    latest_ids_scope = base_scope.group("`#{child_class.table_name}`.`#{fk}`", *db_grp_cols)
    latest_ids_scope = latest_ids_scope.latest if child_class.respond_to?(:latest)
    latest_ids_query = latest_ids_scope.select("MAX(`#{child_class.table_name}`.id)")

    # Fetch values for those IDs
    db_val_col_name = db_col(value_col)
    child_class
      .joins(joins&.to_sym)
      .where("`#{child_class.table_name}`.id IN (#{latest_ids_query.to_sql})")
      .select("`#{child_class.table_name}`.`#{fk}`", *db_grp_cols, db_val_col_name)
      .each do |row|
        root_id = row.send(fk)

        # Extract combination from row
        combo = group_bys.map { |gb| row.send(gb.split(".").last) }
        next unless combinations.include?(combo) || combinations.include?(combo.first) # handle single vs multi

        raw = row.send(value_col.split(".").last)
        result[root_id][pivot_key(combo)] = monetized?(value_col) ? cents_to_amount(raw) : raw
      end

    result
  end

  def valid_columns?
    allowed = child_class.column_names.to_set

    # Validate each group_by column (simple columns only; dot-notation resolved via db_col)
    group_bys.each do |gb|
      col = gb.include?(".") ? gb.split(".").last : gb
      cents = "#{col}_cents"
      unless allowed.include?(col) || allowed.include?(cents)
        Rails.logger.warn "[ReportBuilderPivotAggregator] Rejected unknown group_by column: #{gb}"
        return false
      end
    end

    # Validate value_col
    vcol = value_col.include?(".") ? value_col.split(".").last : value_col
    vcents = "#{vcol}_cents"
    unless allowed.include?(vcol) || allowed.include?(vcents)
      Rails.logger.warn "[ReportBuilderPivotAggregator] Rejected unknown value_col: #{value_col}"
      return false
    end

    true
  end

  def agg_for_sql(agg, when_clause)
    case agg
    when "count" then "COUNT(#{when_clause})"
    when "avg"   then "AVG(#{when_clause})"
    when "min"   then "MIN(#{when_clause})"
    when "max"   then "MAX(#{when_clause})"
    when "list"  then "GROUP_CONCAT(DISTINCT #{when_clause} SEPARATOR ', ')"
    else              "SUM(#{when_clause})"
    end
  end

  def db_col(col)
    if col.include?(".")
      parts = col.split(".")
      target_col = parts.last
      target_klass = child_class
      parts[0..-2].each do |part|
        reflection = target_klass.reflect_on_association(part.to_sym)
        target_klass = reflection.klass if reflection
      end

      cents = "#{target_col}_cents"
      final_col = target_klass.column_names.include?(cents) ? cents : target_col
      "`#{target_klass.table_name}`.`#{final_col}`"
    else
      return "`#{child_class.table_name}`.`#{col}`" if child_class.column_names.include?(col)

      cents = "#{col}_cents"
      final_col = child_class.column_names.include?(cents) ? cents : col
      "`#{child_class.table_name}`.`#{final_col}`"
    end
  end

  def monetized?(col)
    target_klass = child_class
    target_col   = col

    if col.include?(".")
      parts = col.split(".")
      target_col = parts.last
      parts[0..-2].each do |part|
        reflection = target_klass.reflect_on_association(part.to_sym)
        target_klass = reflection.klass if reflection
      end
    end

    target_klass.column_names.exclude?(target_col) &&
      target_klass.column_names.include?("#{target_col}_cents")
  end

  def cents_to_amount(val)
    return nil if val.nil?

    BigDecimal(val.to_s) / 100
  end
end
