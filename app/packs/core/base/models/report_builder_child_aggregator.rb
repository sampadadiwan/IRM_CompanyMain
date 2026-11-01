# Handles all aggregation for a single child relation.
# Issues at most two queries: one GROUP BY for sum/count/avg/min/max/list,
# and one MAX(id)-subquery for "latest" columns.
#
# Two modes (chosen by ReportBuilderColumnType#strategy_for, passed as join_config[:mode]):
#   :grouped  — a first-level has_many: query the child table, grouped by its
#               foreign key to the root (the original path; related filters apply)
#   :anchored — parents, has_one, through and multi-step paths: query the ROOT
#               table joined along the path, grouped by the root id
# Worked examples H1, H2, H3, H4, H5, E1, X1 — openspec/changes/report-builder-trust/design.md#worked-examples
class ReportBuilderChildAggregator
  GROUP_SQL = {
    "sum" => ->(col) { "SUM(#{col})" },
    "count" => ->(_)   { "COUNT(*)" },
    "avg" => ->(col) { "AVG(#{col})" },
    "min" => ->(col) { "MIN(#{col})" },
    "max" => ->(col) { "MAX(#{col})" },
    # Internal: the single related value of one-per-row related data (H1, H2)
    "value" => ->(col) { "MAX(#{col})" },
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
  # user         – whose Pundit scope of the child model limits the rows aggregated (M16-2)
  def initialize(join_config:, root_ids:, aggregates:, gvp_keys:, user:)
    @join_config = join_config.with_indifferent_access
    @root_ids    = root_ids
    @aggregates  = aggregates
    @gvp_keys    = gvp_keys
    @user        = user
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
  rescue ActiveRecord::StatementInvalid, ActiveRecord::ConfigurationError, NameError => e
    # A path or column that no longer resolves leaves its columns blank rather
    # than breaking the whole report (X1)
    Rails.logger.warn "[ReportBuilder] related data #{relation} could not be read: #{e.message}"
    {}
  end

  private

  # The total used in SQL for a key. "Latest" picks the newest child row by id,
  # which only makes sense when grouping the child table itself — anchored
  # joins use the largest value instead.
  def agg_for(gvp_key)
    agg = aggregates[clean_key(gvp_key)]
    anchored? && agg == "latest" ? "max" : agg
  end

  attr_reader :join_config, :root_ids, :aggregates, :gvp_keys, :user

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
  def anchored?   = join_config[:mode].to_s == "anchored"

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
    # M16 — only the children the user may see, so an out-of-scope row is not counted or summed
    # either (M16-2). The latest-value query reuses this scope as its MAX(id) subquery.
    scope = scope.where(id: visible_child_ids) if visible_child_ids
    # Polymorphic has_many (e.g. documents `as: :owner`): only the root's own
    # type, never another model's rows that share the id (H5)
    scope = scope.where(join_config[:poly_type] => join_config[:poly_name]) if join_config[:poly_type].present?
    scope = scope.joins(joins_arg) if joins.present?
    # Related filters are Ransack conditions on the child table — they don't
    # apply to anchored joins, whose base table is the root itself
    return scope if anchored?

    child_filters.present? ? scope.ransack(child_filters).result : scope
  end

  # A dotted relation path as the nested form `joins` expects:
  # "fund" → :fund, "capital_commitments.fund" → { capital_commitments: :fund }
  def joins_arg
    return joins unless joins.is_a?(String)

    joins.split(".").map(&:to_sym).reverse.reduce { |inner, outer| { outer => inner } }
  end

  # The column path relative to the base table, without the "; col-type" suffix.
  # Grouped: strip the relation ("capital_commitments.committed_amount" → "committed_amount").
  # Anchored: the whole key, since the base table is the root
  # ("capital_commitments.fund.name" is walked root → capital_commitments → fund → name).
  def bare_col(gvp_key)
    without_type = gvp_key.split(";").first.strip
    return without_type if anchored?

    rel_prefix = "#{relation}."
    if without_type.start_with?(rel_prefix)
      without_type.sub(rel_prefix, "")
    else
      without_type.split(".", 2).last
    end
  end

  def agg_alias(gvp_key)
    "rb_#{bare_col(gvp_key).gsub(/[^a-z0-9_]/i, '_')}_#{agg_for(gvp_key)}"
  end

  def clean_key(gvp_key)
    gvp_key.split(";").first.strip
  end

  def group_keys
    valid_gvp_keys.reject { |k| agg_for(k) == "latest" }
                  .select { |k| GROUP_SQL.key?(agg_for(k)) }
  end

  def latest_keys
    valid_gvp_keys.select { |k| agg_for(k) == "latest" }
  end

  def run_group_aggregates(result)
    return if group_keys.empty?

    exprs = group_keys.filter_map do |k|
      col = db_col(bare_col(k))
      sql = GROUP_SQL[agg_for(k)]&.call(col)
      "#{sql} AS #{agg_alias(k)}" if sql
    end

    relation = base_scope
               .group("`#{child_class.table_name}`.`#{fk}`")
               .select("`#{child_class.table_name}`.`#{fk}` AS rb_group_id", *exprs)

    # Plain rows, not model instances: a partial SELECT trips models whose
    # after_initialize reads a column that isn't selected (Document#send_email — H5, E1)
    select_rows(relation).each do |row|
      id = row["rb_group_id"]
      group_keys.each do |k|
        raw = row[agg_alias(k)]
        (result[id] ||= {})[clean_key(k)] = read_value(bare_col(k), raw, agg_for(k))
      end
    end
  end

  def select_rows(relation)
    child_class.connection.select_all(relation.to_sql).to_a
  end

  def run_latest_aggregates(result)
    return if latest_keys.empty?

    # Use model's latest scope if available, otherwise fallback to MAX(id)
    latest_id_scope = base_scope.group("`#{child_class.table_name}`.`#{fk}`")
    latest_id_scope = latest_id_scope.latest if child_class.respond_to?(:latest)
    latest_id_sql   = latest_id_scope.select("MAX(`#{child_class.table_name}`.id) AS max_id").to_sql

    db_cols = latest_keys.map { |k| db_col(bare_col(k)) }.uniq

    # Each selected column gets its own alias, so the same column name from two
    # tables can't collide
    col_aliases = db_cols.each_with_index.to_h { |c, i| [c, "rb_latest_#{i}"] }
    relation = child_class
               .joins(joins.present? ? joins_arg : [])
               .where("`#{child_class.table_name}`.id IN (#{latest_id_sql})")
               .select("`#{child_class.table_name}`.`#{fk}` AS rb_group_id",
                       *col_aliases.map { |c, a| "#{c.include?('.') ? c : "`#{child_class.table_name}`.`#{c}`"} AS #{a}" })

    select_rows(relation).each do |row|
      id = row["rb_group_id"]
      latest_keys.each do |k|
        col = bare_col(k)
        raw = row[col_aliases[db_col(col)]]
        (result[id] ||= {})[clean_key(k)] = read_value(col, raw, "latest")
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

  # Turns a raw database value into what the column holds: money from cents;
  # for totals that keep the column's type (min / max / latest / value) the
  # column's own cast, so a date stays a Date and a yes/no stays true/false
  # (raw rows give "2026-01-15" or 0/1 depending on the database). E4, E5.
  def read_value(col, raw, agg)
    # A count is a number of rows, never money — even of an amount column (H2)
    return raw if agg.to_s == "count"
    return cents_to_amount(raw) if monetized?(col)
    return raw unless %w[min max latest value].include?(agg.to_s)

    target_klass, target_col = target_for(col)
    target_klass.type_for_attribute(target_col).cast(raw)
  rescue StandardError
    raw
  end

  # [model class, bare column] at the end of a column path from the base table
  def target_for(col)
    parts = col.to_s.split(".")
    target_col = parts.pop
    klass = parts.reduce(child_class) { |k, part| k.reflect_on_association(part.to_sym)&.klass || k }
    [klass, target_col]
  end
end
