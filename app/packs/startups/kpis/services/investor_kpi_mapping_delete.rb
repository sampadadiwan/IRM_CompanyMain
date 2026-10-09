# Deleting a KPI mapping (InvestorKpiMappingsController#destroy).
#
#   - A parent mapping (one with child mappings, via ancestry) is never deleted: the children must be
#     moved or deleted first (user decision; design card ⑧, X5).
#   - A mapping no KPI uses is deleted as before (H11).
#   - A mapping KPIs use is deleted together with its KPIs, after the page's warning popup (H12, H13):
#     the KPIs go in batches and then the mapping, in one transaction, so a failure deletes nothing (X2).
#     The database foreign key (kpis.investor_kpi_mapping_id) is why the KPIs must go first.
#     Afterwards the portfolio company's auto-filled values and percentage changes are recomputed in the
#     background, and its KPI report journeys are re-evaluated as an undo (E16: the last mapping gone
#     sends them back to "Set up KPI mappings").
#
# .impact(mapping) gives the popup its counts without loading any KPI rows.
# Worked examples H11, H12, H13, E15, E16, X2, X5 — openspec/changes/kpi-report-journey/design.md#worked-examples
class InvestorKpiMappingDelete < Trailblazer::Operation
  BATCH_SIZE = 1000

  step :refuse_parent
  step :delete_with_kpis
  step :after_delete

  # What deleting this mapping would remove, for the confirm popup — counts only, plus the names of the
  # computed mappings whose formula mentions it and of its child mappings.
  def self.impact(mapping)
    kpis = Kpi.where(investor_kpi_mapping_id: mapping.id)
    name = mapping.reported_kpi_name.to_s
    # Formulas reference other mappings by name; the portco has only a handful of computed mappings
    formulas = InvestorKpiMapping.compute.where(investor_id: mapping.investor_id).where.not(id: mapping.id)
                                 .select { |m| name.present? && m.compute_formula.to_s.include?(name) }.map(&:reported_kpi_name)
    {
      kpis: kpis.count,
      periods: kpis.distinct.count(:kpi_report_id),
      approved: kpis.approved.count,
      formulas:,
      children: mapping.children.pluck(:reported_kpi_name)
    }
  end

  # X5: refused before anything is written
  def refuse_parent(ctx, mapping:, **)
    children = mapping.children.pluck(:reported_kpi_name)
    return true if children.empty?

    ctx[:error] = "Move or delete #{children.to_sentence} first"
    false
  end

  def delete_with_kpis(ctx, mapping:, **)
    ctx[:started_at] = Time.current # before any change, for the journey undo
    ActiveRecord::Base.transaction do
      # Batched, skipping per-KPI callbacks (one recompute job afterwards does their work)
      ctx[:kpis_deleted] = 0
      Kpi.where(investor_kpi_mapping_id: mapping.id).in_batches(of: BATCH_SIZE) do |batch|
        ctx[:kpis_deleted] += batch.delete_all
      end
      mapping.destroy!
    end
    true
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("[InvestorKpiMappingDelete] mapping #{mapping.id} (investor #{mapping.investor_id}, entity #{mapping.entity_id}): #{e.class}: #{e.message}")
    ctx[:error] = "Could not delete #{mapping.reported_kpi_name} — nothing was changed"
    false
  end

  # After commit: recompute what the deleted KPIs fed, and move the portco's journeys back as needed
  def after_delete(ctx, mapping:, user:, **)
    KpiCumulateJob.perform_later([mapping.investor_id], user_id: user.id, compute_percentage_change: true) if ctx[:kpis_deleted].positive?
    # An undo only when data really went: KPIs were deleted, or the portco has no importable mapping left.
    # Deleting an unused mapping must not reopen a finished journey (or clear its completion email).
    last_mapping = InvestorKpiMapping.not_compute.where(investor_id: mapping.investor_id).none?
    if ctx[:kpis_deleted].positive? || last_mapping
      KpiReport.journey_undo_for_portco(mapping.entity_id, mapping.investor_id,
                                        note: "KPI mapping #{mapping.reported_kpi_name} deleted",
                                        started_at: ctx[:started_at], actor: user)
    else
      KpiReport.journey_progress_for_portco(mapping.entity_id, mapping.investor_id, actor: user)
    end
    true
  end
end
