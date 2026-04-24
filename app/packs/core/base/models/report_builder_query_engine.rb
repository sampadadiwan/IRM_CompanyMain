# Orchestrates the two-pass query strategy:
#   Pass 1 – root model query (Ransack filters + sort + entity scoping)
#   Pass 2 – one aggregator per join (pivot or regular)
# Then merges results into an array of hashes keyed by column key.
class ReportBuilderQueryEngine
  def initialize(report:, entity:, external_filters: {})
    @report           = report
    @entity           = entity
    @config           = ReportBuilderConfig.new(report.template)
    @external_filters = (external_filters || {}).with_indifferent_access
    @dynamic_columns  = []
  end

  # Returns Array<Hash> where each hash is one output row.
  def run(limit: nil)
    return [] unless config.valid?

    @dynamic_columns = []
    root_records, root_ids = pass1(limit: limit)
    child_data             = pass2(root_ids)
    rows                   = merge(root_records, child_data)
    
    apply_formulas(rows)
  end

  # Row count without loading all data (for preview badge).
  def count
    return 0 unless config.valid?

    scope = config.root_class.where(entity_id: entity.id)
    merged_filters = config.root_filters.merge(@external_filters)
    scope = scope.ransack(merged_filters).result
    scope.count
  end

  # GVP columns + any dynamic pivot columns + formula columns.
  def columns
    @gvp_columns ||= report.grid_view_preferences.reorder(:sequence, :id).to_a
    formula_cols = (config.formulas || []).map do |f|
      ReportBuilderDynamicColumn.new(key: f["key"], label: f["label"])
    end
    @gvp_columns + @dynamic_columns + formula_cols
  end

  private

  attr_reader :report, :entity, :config

  def apply_formulas(rows)
    formulas = config.formulas
    return rows if formulas.blank?

    service = ReportBuilderFormulaService.new(formulas)
    rows.map { |row| service.evaluate(row) }
  end

  # ── Pass 1 ──────────────────────────────────────────────────────────────

  def pass1(limit: nil)
    scope = config.root_class.where(entity_id: entity.id)
    
    merged_filters = config.root_filters.merge(@external_filters)
    scope = scope.ransack(merged_filters).result
    
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
    col_names = config.root_class.column_names
    (@gvp_columns ||= report.grid_view_preferences.reorder(:sequence, :id).to_a)
      .map(&:key)
      .reject { |k| k.include?(".") }
      .map    { |k| k.split(";").first.strip }
      .flat_map { |k|
        if col_names.include?(k)
          [k]
        elsif col_names.include?("#{k}_cents")
          ["#{k}_cents"]
        else
          []
        end
      }
      .uniq
  end

  # ── Pass 2 ──────────────────────────────────────────────────────────────

  def pass2(root_ids)
    return {} if root_ids.empty?

    config.joins.each_with_object({}) do |join_cfg, acc|
      relation_path = join_cfg[:relation].to_s
      parts         = relation_path.split(".")
      first_rel     = parts.first
      
      reflection = config.root_class.reflect_on_association(first_rel.to_sym)
      next unless reflection
      
      base_class = reflection.klass
      fk         = reflection.macro == :belongs_to ? "id" : reflection.foreign_key.to_s
      
      # The rest of the path are the joins
      # e.g. "fund.fund_manager"
      remaining_path = parts.size > 1 ? parts[1..-1].join(".") : nil

      pivot_cfg = join_cfg[:pivot]
      pivot_ready = pivot_cfg.present? &&
                    Array(pivot_cfg[:group_bys] || pivot_cfg[:group_by]).any?(&:present?) &&
                    pivot_cfg[:value_col].to_s.present?

      if pivot_ready
        dyn_cols, pivot_data = ReportBuilderPivotAggregator.new(
          join_config: join_cfg.merge(base_class: base_class, joins: remaining_path, fk: fk),
          root_ids: root_ids
        ).call
        @dynamic_columns.concat(dyn_cols)
        acc[relation_path] = pivot_data
      else
        gvp_keys = (@gvp_columns ||= report.grid_view_preferences.order(:sequence).to_a)
                   .map(&:key)
                   .select { |k| k.split(";").first.strip.start_with?("#{relation_path}.") }

        next if gvp_keys.empty?

        acc[relation_path] = ReportBuilderChildAggregator.new(
          join_config: join_cfg.merge(base_class: base_class, joins: remaining_path, fk: fk),
          root_ids: root_ids,
          aggregates: build_rel_aggregates(relation_path, gvp_keys),
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
