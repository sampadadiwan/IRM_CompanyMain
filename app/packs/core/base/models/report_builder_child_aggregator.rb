# Handles all aggregation for a single child relation.
# Issues at most two queries: one GROUP BY for sum/count/avg/min/max/list,
# and one MAX(id)-subquery for "latest" columns.
class ReportBuilderChildAggregator
  GROUP_SQL = {
    "sum" => ->(col) { "SUM(#{col})" },
    "count" => ->(_)   { "COUNT(*)" },
    "avg" => ->(col) { "AVG(#{col})" },
    "min" => ->(col) { "MIN(#{col})" },
    "max" => ->(col) { "MAX(#{col})" },
    "list" => lambda { |col|
      if /mysql/i.match?(ActiveRecord::Base.connection.adapter_name)
        "GROUP_CONCAT(DISTINCT #{col} SEPARATOR ', ')"
      else
        "GROUP_CONCAT(DISTINCT #{col})"
      end
    }
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
    return {} if root_ids.empty? || valid_gvp_keys.empty?

    # Plain Hash, not Hash.new { |h, k| h[k] = {} } — that auto-vivifying default
    # makes `result[missing_root_id]` return a truthy `{}` instead of `nil` on
    # read, which defeats QueryEngine#merge's `row_data ? ... : zero_value(...)`
    # zero-fill check for root rows with no matching children (they'd render
    # blank instead of the documented 0 for sum/count). Use `||= {}` at each
    # write site below instead, so a genuinely-unpopulated id stays absent.
    result = {}
    run_group_aggregates(result)
    run_latest_aggregates(result)
    result
  end

  private

  attr_reader :join_config, :root_ids, :aggregates, :gvp_keys

  # Drops any key whose column doesn't resolve to a real DB column (walking
  # association reflections for dotted paths). This is the boundary that
  # keeps column names safe to interpolate as raw SQL identifiers below —
  # mirrors ReportBuilderPivotAggregator#valid_columns?.
  def valid_gvp_keys
    @valid_gvp_keys ||= gvp_keys.select { |k| column_path_valid?(bare_col(k)) }
  end

  def column_path_valid?(col)
    parts = col.to_s.split(".")
    target_col = parts.pop
    target_klass = child_class

    parts.each do |part|
      reflection = target_klass.reflect_on_association(part.to_sym)
      return false unless reflection

      target_klass = reflection.klass
    end

    allowed = target_klass.column_names.to_set
    allowed.include?(target_col) || allowed.include?("#{target_col}_cents")
  rescue StandardError
    false
  end

  def relation    = join_config[:relation].to_s
  def child_class = join_config[:base_class].to_s.constantize
  def fk          = join_config[:fk].to_s
  def joins       = join_config[:joins]

  def child_filters
    (join_config[:child_filters] || {}).with_indifferent_access
  end

  def base_scope
    scope = child_class.where(fk => root_ids)
    scope = scope.joins(joins.to_sym) if joins.present?
    child_filters.present? ? scope.ransack(child_filters).result : scope
  end

  # Strip "relation.path." prefix and "; col-type" suffix to get bare column name.
  def bare_col(gvp_key)
    without_type = gvp_key.split(";").first.strip
    # If key is "capital_commitments.fund.name", and relation is "capital_commitments.fund"
    # we want "name".
    # But wait, QueryEngine passes relation_path as "capital_commitments.fund"
    # So we can just remove the relation_path prefix.
    rel_prefix = "#{relation}."
    if without_type.start_with?(rel_prefix)
      without_type.sub(rel_prefix, "")
    else
      without_type.split(".", 2).last
    end
  end

  def agg_alias(gvp_key)
    "rb_#{bare_col(gvp_key).gsub(/[^a-z0-9_]/i, '_')}_#{aggregates[clean_key(gvp_key)]}"
  end

  def clean_key(gvp_key)
    gvp_key.split(";").first.strip
  end

  def group_keys
    valid_gvp_keys.reject { |k| aggregates[clean_key(k)] == "latest" }
                  .select { |k| GROUP_SQL.key?(aggregates[clean_key(k)]) }
  end

  def latest_keys
    valid_gvp_keys.select { |k| aggregates[clean_key(k)] == "latest" }
  end

  def run_group_aggregates(result)
    return if group_keys.empty?

    exprs = group_keys.filter_map do |k|
      col = db_col(bare_col(k))
      sql = GROUP_SQL[aggregates[clean_key(k)]]&.call(col)
      "#{sql} AS #{agg_alias(k)}" if sql
    end

    base_scope
      .group("`#{child_class.table_name}`.`#{fk}`")
      .select("`#{child_class.table_name}`.`#{fk}`", *exprs)
      .each do |row|
        id = row.send(fk)
        group_keys.each do |k|
          raw = row.send(agg_alias(k))
          (result[id] ||= {})[clean_key(k)] = monetized?(bare_col(k)) ? cents_to_amount(raw) : raw
        end
      end
  end

  def run_latest_aggregates(result)
    return if latest_keys.empty?

    # Use model's latest scope if available, otherwise fallback to MAX(id)
    latest_id_scope = base_scope.group("`#{child_class.table_name}`.`#{fk}`")
    latest_id_scope = latest_id_scope.latest if child_class.respond_to?(:latest)
    latest_id_sql   = latest_id_scope.select("MAX(`#{child_class.table_name}`.id) AS max_id").to_sql

    db_cols = latest_keys.map { |k| db_col(bare_col(k)) }.uniq

    child_class
      .joins(joins&.to_sym)
      .where("`#{child_class.table_name}`.id IN (#{latest_id_sql})")
      .select("`#{child_class.table_name}`.`#{fk}`", *db_cols.map { |c| c.include?(".") ? c : "`#{child_class.table_name}`.`#{c}`" })
      .each do |row|
        id = row.send(fk)
        latest_keys.each do |k|
          col = bare_col(k)
          raw = row.send(db_col(col).split(".").last.delete("`"))
          (result[id] ||= {})[clean_key(k)] = monetized?(col) ? cents_to_amount(raw) : raw
        end
      end
  end

  # Returns the actual DB column, falling back to _cents for monetized attributes.
  # Handles joined columns by prefixing with table name if needed.
  def db_col(col)
    if col.include?(".")
      # e.g. "fund.name"
      parts = col.split(".")
      target_col = parts.last

      # We need the table name for the joined model
      # This is tricky because ActiveRecord might alias tables.
      # For now, let's assume standard table names.

      # We can try to resolve the table name from the association
      current_klass = child_class
      parts[0..-2].each do |part|
        reflection = current_klass.reflect_on_association(part.to_sym)
        current_klass = reflection.klass if reflection
      end

      table_name = current_klass.table_name

      # Check for monetization on the target class
      cents = "#{target_col}_cents"
      final_col = current_klass.column_names.include?(cents) ? cents : target_col

      "`#{table_name}`.`#{final_col}`"
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

  def cents_to_amount(cents_val)
    return nil if cents_val.nil?

    BigDecimal(cents_val.to_s) / 100
  end
end
