# Single source of truth for turning an InvestorKpiMapping's RAG configuration
# (rag_direction / rag_comparator_tag / rag_red_threshold / rag_green_threshold) plus a value
# (and, when there's a comparator, the comparator's value) into 'red' / 'amber' / 'green' / nil.
# Called from both Kpi#recompute_rag_status! (the live, persisted path) and
# KpiWorkbookReader#plausibility_checks (the upload-time warning). See
# docs/modules/portfolio/kpis/kpi_rag_rules_redesign.md.
#
# This operation doesn't know or care *how* comparator_value was resolved — the caller may have
# matched it by tag (Budget/PriorYear, same as_of) or, when mapping.rag_comparator_prior_period?
# is true, by walking to the KPI's own most recent prior report (see the "Addendum: prior-period
# comparator" section of the doc above). Either way rag_comparator_tag.present? is true (the
# reserved sentinel string is non-blank), so both paths take the same ratio-based branch below.
class RagStatusEvaluator < Trailblazer::Operation
  step :evaluate

  private

  def evaluate(ctx, value:, comparator_value:, mapping:, **)
    ctx[:status] = nil
    return true unless mapping&.rag_configured?

    if mapping.rag_comparator_tag.present?
      return true if comparator_value.blank?

      if comparator_value.to_f.zero?
        ctx[:status] = 'red'
        return true
      end

      judged_value = value.to_f / comparator_value.to_f
    else
      judged_value = value.to_f
    end

    ctx[:status] = classify(judged_value, mapping)
    true
  end

  def classify(judged_value, mapping)
    red = mapping.rag_red_threshold.to_f
    green = mapping.rag_green_threshold.to_f

    if mapping.higher_is_better?
      return 'red' if judged_value < red
      return 'green' if judged_value >= green

      'amber'
    else
      return 'red' if judged_value > red
      return 'green' if judged_value <= green

      'amber'
    end
  end
end
