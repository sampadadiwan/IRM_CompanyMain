module InvestorKpiMappingsHelper
  # The Delete popup for a mapping KPIs use: at most three action-summary cards — what is deleted, which
  # formulas break, and that it can't be undone (custom/action_summary_modal.scss, built escaped).
  # impact is InvestorKpiMappingDelete.impact(mapping).
  # Worked examples H12 — openspec/changes/kpi-report-journey/design.md#worked-examples
  def investor_kpi_mapping_delete_action_summary(mapping, impact)
    name = mapping.reported_kpi_name
    cards = [["red", "ti-trash", "Deletes KPIs",
              "#{pluralize(impact[:kpis], 'KPI')} across #{pluralize(impact[:periods], 'period')} (#{impact[:approved]} approved)"]]
    if impact[:formulas].any?
      cards << ["amber", "ti-alert-triangle", "Formulas break", "#{impact[:formulas].to_sentence} #{impact[:formulas].one? ? 'uses' : 'use'} #{name}"]
    end
    cards << ["amber", "ti-alert-triangle", "Cannot be undone", "Rename the mapping instead to keep the history"]
    kpi_report_action_summary(cards, intro_action: "Delete")
  end
end
