# Handles all aggregation for a single child relation.
# Issues at most two queries: one GROUP BY for sum/count/avg/min/max/list,
# and one MAX(id)-subquery for "latest" columns.
class ReportBuilderChildAggregator
  GROUP_SQL = {
    "sum" => ->(col) { "SUM(`#{col}`)" },
    "count" => ->(_)   { "COUNT(*)" },
    "avg" => ->(col) { "AVG(`#{col}`)" },
    "min" => ->(col) { "MIN(`#{col}`)" },
    "max" => ->(col) { "MAX(`#{col}`)" },
    "list" => ->(col) { "GROUP_CONCAT(DISTINCT `#{col}` SEPARATOR ', ')" }
  }.freeze

  # join_config  – one element from Config#joins (with :fk added by QueryEngine)
  # root_ids     – array of root record IDs
  # aggregates   – Hash { "relation.col" => "sum"|"count"|... } (clean keys, no col-type suffix)
  # gvp_keys     – GridViewPreference#key values belonging to this relation (raw, may have "; col-type")
  def initialize(join_config:, root_ids:, aggregates:, gvp_keys:)
    @join_config = join_config.with_indifferent_access
    @root_ids    = root_ids
    @aggregates  = aggregates
    @gvp_keys    = gvp_keys
  end

  # Returns Hash { root_id => { gvp_key => value } }
  def call
    return {} if root_ids.empty? || gvp_keys.empty?

    result = Hash.new { |h, k| h[k] = {} }
    run_group_aggregates(result)
    run_latest_aggregates(result)
    result
  end

  private

  attr_reader :join_config, :root_ids, :aggregates, :gvp_keys

  def relation    = join_config[:relation].to_s
  def child_class = join_config[:model].constantize
  def fk          = join_config[:fk].to_s

  def child_filters
    (join_config[:child_filters] || {}).with_indifferent_access
  end

  def base_scope
    scope = child_class.where(fk => root_ids)
    child_filters.present? ? scope.ransack(child_filters).result : scope
  end

  # Strip "relation." prefix and "; col-type" suffix to get bare column name.
  def bare_col(gvp_key)
    without_type = gvp_key.split(";").first.strip
    without_type.split(".", 2).last
  end

  def agg_alias(gvp_key)
    "rb_#{bare_col(gvp_key).gsub(/[^a-z0-9_]/i, '_')}_#{aggregates[clean_key(gvp_key)]}"
  end

  def clean_key(gvp_key)
    gvp_key.split(";").first.strip
  end

  def group_keys
    gvp_keys.reject { |k| aggregates[clean_key(k)] == "latest" }
            .select { |k| GROUP_SQL.key?(aggregates[clean_key(k)]) }
  end

  def latest_keys
    gvp_keys.select { |k| aggregates[clean_key(k)] == "latest" }
  end

  def run_group_aggregates(result)
    return if group_keys.empty?

    exprs = group_keys.filter_map do |k|
      col = db_col(bare_col(k))
      sql = GROUP_SQL[aggregates[clean_key(k)]]&.call(col)
      "#{sql} AS #{agg_alias(k)}" if sql
    end

    base_scope
      .group(fk)
      .select("`#{child_class.table_name}`.`#{fk}`", *exprs)
      .each do |row|
        id = row.send(fk)
        group_keys.each do |k|
          raw = row.send(agg_alias(k))
          result[id][clean_key(k)] = monetized?(bare_col(k)) ? cents_to_amount(raw) : raw
        end
      end
  end

  def run_latest_aggregates(result)
    return if latest_keys.empty?

    # Use model's latest scope if available, otherwise fallback to MAX(id)
    latest_id_scope = base_scope.group(fk)
    latest_id_scope = child_class.respond_to?(:latest) ? latest_id_scope.latest : latest_id_scope
    latest_id_sql   = latest_id_scope.select("MAX(id) AS max_id").to_sql

    db_cols = latest_keys.map { |k| db_col(bare_col(k)) }.uniq

    child_class
      .where("id IN (#{latest_id_sql})")
      .select("`#{fk}`", *db_cols.map { |c| "`#{c}`" })
      .each do |row|
        id = row.send(fk)
        latest_keys.each do |k|
          col = bare_col(k)
          raw = row.send(db_col(col))
          result[id][clean_key(k)] = monetized?(col) ? cents_to_amount(raw) : raw
        end
      end
  end

  # Returns the actual DB column, falling back to _cents for monetized attributes.
  def db_col(col)
    return col if child_class.column_names.include?(col)

    cents = "#{col}_cents"
    child_class.column_names.include?(cents) ? cents : col
  end

  def monetized?(col)
    child_class.column_names.exclude?(col) &&
      child_class.column_names.include?("#{col}_cents")
  end

  def cents_to_amount(cents_val)
    return nil if cents_val.nil?

    BigDecimal(cents_val.to_s) / 100
  end
end
