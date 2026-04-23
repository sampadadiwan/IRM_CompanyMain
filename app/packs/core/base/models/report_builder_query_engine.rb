# Orchestrates the two-pass query strategy:
#   Pass 1 – root model query (Ransack filters + sort + entity scoping)
#   Pass 2 – one aggregator per join (pivot or regular)
# Then merges results into an array of hashes keyed by column key.
class ReportBuilderQueryEngine
  def initialize(report:, entity:)
    @report          = report
    @entity          = entity
    @config          = ReportBuilderConfig.new(report.template)
    @dynamic_columns = []
  end

  # Returns Array<Hash> where each hash is one output row.
  def run(limit: nil)
    return [] unless config.valid?

    @dynamic_columns = []
    root_records, root_ids = pass1(limit: limit)
    child_data             = pass2(root_ids)
    merge(root_records, child_data)
  end

  # Row count without loading all data (for preview badge).
  def count
    return 0 unless config.valid?

    scope = config.root_class.where(entity_id: entity.id)
    scope = scope.ransack(config.root_filters.presence || {}).result
    scope.count
  end

  # GVP columns + any dynamic pivot columns (populated after run).
  def columns
    @gvp_columns ||= report.grid_view_preferences.reorder(:sequence, :id).to_a
    @gvp_columns + @dynamic_columns
  end

  private

  attr_reader :report, :entity, :config

  # ── Pass 1 ──────────────────────────────────────────────────────────────

  def pass1(limit: nil)
    scope = config.root_class.where(entity_id: entity.id)
    scope = scope.ransack(config.root_filters.presence || {}).result
    scope = apply_sort(scope)
    scope = scope.limit(limit) if limit

    needed_cols = root_db_columns
    scope = scope.select(:id, *needed_cols) if needed_cols.any?

    records = scope.to_a
    [records, records.map(&:id)]
  end

  def apply_sort(scope)
    key = config.sort[:key].to_s.split(";").first&.strip.to_s
    dir = config.sort[:dir] == "desc" ? "DESC" : "ASC"
    key.present? && config.root_class.column_names.include?(key) ? scope.order("#{key} #{dir}") : scope
  end

  def root_db_columns
    (@gvp_columns ||= report.grid_view_preferences.reorder(:sequence, :id).to_a)
      .map(&:key)
      .reject { |k| k.include?(".") }
      .map    { |k| k.split(";").first.strip }
      .select { |k| config.root_class.column_names.include?(k) }
      .uniq
  end

  # ── Pass 2 ──────────────────────────────────────────────────────────────

  def pass2(root_ids)
    return {} if root_ids.empty?

    config.joins.each_with_object({}) do |join_cfg, acc|
      relation = join_cfg[:relation].to_s
      fk       = resolve_fk(config.root_class, relation, join_cfg)

      pivot_cfg = join_cfg[:pivot]
      pivot_ready = pivot_cfg.present? &&
                    pivot_cfg[:group_by].to_s.present? &&
                    pivot_cfg[:value_col].to_s.present?

      if pivot_ready
        dyn_cols, pivot_data = ReportBuilderPivotAggregator.new(
          join_config: join_cfg.merge(fk: fk),
          root_ids: root_ids
        ).call
        @dynamic_columns.concat(dyn_cols)
        acc[relation] = pivot_data
      else
        gvp_keys = (@gvp_columns ||= report.grid_view_preferences.order(:sequence).to_a)
                   .map(&:key)
                   .select { |k| k.split(";").first.strip.start_with?("#{relation}.") }

        next if gvp_keys.empty?

        acc[relation] = ReportBuilderChildAggregator.new(
          join_config: join_cfg.merge(fk: fk),
          root_ids: root_ids,
          aggregates: build_rel_aggregates(relation, gvp_keys),
          gvp_keys: gvp_keys
        ).call
      end
    end
  end

  def build_rel_aggregates(_relation, gvp_keys)
    gvp_keys.each_with_object({}) do |key, h|
      clean = key.split(";").first.strip
      agg   = config.aggregate_for(clean) || config.aggregate_for(key)
      h[clean] = agg if agg
    end
  end

  def resolve_fk(root_class, relation_name, join_cfg)
    return join_cfg[:fk] if join_cfg[:fk].present?

    reflection = root_class.reflect_on_association(relation_name.to_sym)
    return "#{root_class.name.underscore}_id" unless reflection

    case reflection.macro
    when :has_many, :has_one then reflection.foreign_key.to_s
    when :belongs_to         then "id"
    else "#{root_class.name.underscore}_id"
    end
  end

  # ── Merge ───────────────────────────────────────────────────────────────

  def merge(root_records, child_data)
    all_cols = columns # GVPs + dynamic pivot columns

    root_records.map do |root|
      all_cols.each_with_object({}) do |col, row|
        clean = col.key.split(";").first.strip

        if clean.include?(".")
          relation   = clean.split(".", 2).first
          rel_result = child_data[relation] || {}
          row_data   = rel_result[root.id]

          if col.is_a?(ReportBuilderDynamicColumn)
            # Pivot key is the full col.key (includes __pivot__ value)
            row[col.key] = row_data ? (row_data[col.key] || 0) : 0
          else
            agg_type     = config.aggregate_for(clean) || config.aggregate_for(col.key)
            row[col.key] = row_data ? row_data[clean] : zero_value(agg_type)
          end
        else
          row[col.key] = begin
            root.respond_to?(clean) ? root.send(clean) : nil
          rescue StandardError
            nil
          end
        end
      end
    end
  end

  def zero_value(agg_type)
    %w[sum count].include?(agg_type) ? 0 : nil
  end
end
