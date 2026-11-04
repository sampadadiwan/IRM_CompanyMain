# Handles pivot aggregation for a single child relation.
# Produces one dynamic column per distinct value of the group_by column,
# using CASE WHEN SQL so the entire pivot runs in a single query.
#
# Example: pivot { group_by: "name", value_col: "amount", aggregate: "sum" }
# produces columns "Management Fees (sum)", "Setup Fees (sum)", etc.
class ReportBuilderPivotAggregator
  # user – whose Pundit scope of the child model limits the rows pivoted (M16-2)
  def initialize(join_config:, root_ids:, user:)
    @join_config = join_config.with_indifferent_access
    @root_ids    = root_ids
    @user        = user
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

  # How many columns the pivot would create and the first headers, without
  # running it — shown in the pivot form before Apply. Worked examples H16, X2.
  def preview_columns(limit: 5)
    return { error: "Choose categories and a value" } if group_bys.blank? || value_col.blank?

    unknown = (group_bys + [value_col]).find { |col| !column_exists?(col) }
    return { error: "#{unknown} isn't a field of #{relation.humanize.downcase}" } if unknown

    combinations = discover_values
    { count: combinations.size, headers: combinations.first(limit).map { |combo| Array(combo).join(" · ") } }
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.warn "[ReportBuilderPivotAggregator] preview failed: #{e.message}"
    { error: "The pivot couldn't be previewed" }
  end

  private

  def column_exists?(col)
    bare = col.to_s.split(".").last
    child_class.column_names.include?(bare) || child_class.column_names.include?("#{bare}_cents")
  end

  attr_reader :join_config, :root_ids, :pivot, :user

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

  # M16 — the user's visible ids of the child model (a subquery), built once per aggregator
  def visible_child_ids
    return @visible_child_ids if defined?(@visible_child_ids)

    @visible_child_ids = ReportBuilderQueryEngine.visible_ids(user, child_class)
  end

  def base_scope
    scope = child_class.where(fk => root_ids)
    # M16 — only the children the user may see, so an out-of-scope row adds no pivot column or value
    # (M16-2). The value discovery and the latest-value subquery both start here.
    scope = scope.where(id: visible_child_ids) if visible_child_ids
    # Polymorphic has_many: only the root's own owner type (H5)
    scope = scope.where(join_config[:poly_type] => join_config[:poly_name]) if join_config[:poly_type].present?
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
      # Headers name their related data, so two pivots with the same values
      # stay distinguishable: "Capital commitments · A (sum)" (H12)
      ReportBuilderDynamicColumn.new(
        key: pivot_key(combo),
        label: "#{relation.humanize} · #{label} (#{aggregate})"
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
    relation = base_scope
               .group(fk_sql)
               .select(Arel.sql("#{fk_sql} AS rb_group_id"), *case_exprs.map { |e| Arel.sql(e[:sql]) })

    # Plain rows, not model instances: a partial SELECT trips models whose
    # after_initialize reads a column that isn't selected (e.g. Document)
    select_rows(relation).each do |row|
      id = row["rb_group_id"]
      case_exprs.each do |e|
        raw = row[e[:alias]]
        # A count is a number of rows, never money (H2)
        result[id][pivot_key(e[:combo])] = monetized?(value_col) && aggregate != "count" ? cents_to_amount(raw) : raw
      end
    end

    result
  end

  def select_rows(relation)
    child_class.connection.select_all(relation.to_sql).to_a
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
    relation = child_class
               .joins(joins.present? ? joins.to_sym : [])
               .where("`#{child_class.table_name}`.id IN (#{latest_ids_query.to_sql})")
               .select("`#{child_class.table_name}`.`#{fk}` AS rb_group_id",
                       *db_grp_cols.each_with_index.map { |c, i| "#{c} AS rb_group_#{i}" },
                       "#{db_val_col_name} AS rb_value")

    select_rows(relation).each do |row|
      root_id = row["rb_group_id"]

      # Extract combination from row
      combo = group_bys.each_index.map { |i| row["rb_group_#{i}"] }
      next unless combinations.include?(combo) || combinations.include?(combo.first) # handle single vs multi

      raw = row["rb_value"]
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
