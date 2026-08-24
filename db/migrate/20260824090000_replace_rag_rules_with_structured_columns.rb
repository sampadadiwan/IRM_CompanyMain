class ReplaceRagRulesWithStructuredColumns < ActiveRecord::Migration[8.1]
  def up
    add_column :investor_kpi_mappings, :rag_comparator_tag, :string, limit: 50, default: "Budget"
    add_column :investor_kpi_mappings, :rag_direction, :string, limit: 20
    add_column :investor_kpi_mappings, :rag_red_threshold, :decimal, precision: 20, scale: 4
    add_column :investor_kpi_mappings, :rag_green_threshold, :decimal, precision: 20, scale: 4

    # Best-effort backfill from the old free-form JSON (see docs/technical/kpi_rag_rules_redesign.md).
    # The old format never recorded which tag a mapping was meant to compare against — it was either
    # hardcoded to 'Budget' (KpiWorkbookReader) or passed as a runtime argument that wasn't persisted
    # anywhere (Kpi#set_rag_status_from_ratio) — so 'Budget' is the only sensible default, and
    # direction defaults to higher_is_better. The feature was never wired into a live write path
    # (see design doc), so real rows are expected to be rare; anything that doesn't cleanly parse
    # is left unconfigured rather than guessed at.
    InvestorKpiMapping.where.not(rag_rules: [nil, {}]).find_each do |mapping|
      rules = mapping.rag_rules.is_a?(Hash) ? mapping.rag_rules["ratio_rules"] : nil
      next unless rules.is_a?(Hash)

      red_max = rules.dig("red", "max")
      green_min = rules.dig("green", "min")
      next if red_max.blank? || green_min.blank?

      begin
        mapping.update_columns(
          rag_comparator_tag: "Budget",
          rag_direction: "higher_is_better",
          rag_red_threshold: Float(red_max),
          rag_green_threshold: Float(green_min)
        )
      rescue ArgumentError, TypeError
        next
      end
    end

    remove_column :investor_kpi_mappings, :rag_rules
  end

  def down
    add_column :investor_kpi_mappings, :rag_rules, :json
    remove_column :investor_kpi_mappings, :rag_comparator_tag
    remove_column :investor_kpi_mappings, :rag_direction
    remove_column :investor_kpi_mappings, :rag_red_threshold
    remove_column :investor_kpi_mappings, :rag_green_threshold
  end
end
