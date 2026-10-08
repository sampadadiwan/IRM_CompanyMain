class CapitalCallAction < Trailblazer::Operation
  def save(_ctx, capital_call:, **)
    capital_call.save
  end

  def handle_errors(ctx, capital_call:, **)
    unless capital_call.valid?
      ctx[:errors] = capital_call.errors.full_messages.join(", ")
      Rails.logger.error capital_call.errors.full_messages
    end
    capital_call.valid?
  end

  def generate_capital_remittances(ctx, capital_call:, **)
    # If this is called via import of calls, then we don't want to generate remittances in poerform_later but we want to generate in perform_now. if import_upload is not present, then later is false.
    later = ctx[:import_upload].blank?
    capital_call.generate_capital_remittances(later:) unless capital_call.destroyed?
    true
  end

  # ── Capital call journey: undoing actions (capital-call-journey) ───────────────
  # Worked examples E8, E10b, E13 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples

  # Taken before the action changes anything, so the undo resets every sign-off given before it
  def start_journey_undo(ctx, **)
    ctx[:journey_undo_started_at] = Time.current
    true
  end

  # Unapprove: re-check the journey now, as an undo (moves back to Approve call)
  def evaluate_journey_undo(ctx, capital_call:, current_user: nil, **)
    capital_call.journey_undo_evaluate(note: ctx[:journey_undo_note] || "Call changed", actor: current_user,
                                       started_at: ctx[:journey_undo_started_at] || Time.current)
    true
  end

  # Figures or call date edited once remittances exist: the remittances and notices still carry the
  # old amounts, which no check can see, so mark both tasks stale and re-check as an undo
  def invalidate_if_figures_changed(ctx, capital_call:, current_user: nil, **)
    figures = %i[percentage_called amount_to_be_called_cents fund_closes call_date]
    changed = figures.select { |attr| capital_call.saved_change_to_attribute?(attr) }
    return true if changed.empty? || !capital_call.capital_remittances.exists?

    note = "Call figures changed by #{current_user&.full_name || 'a user'}"
    # Each task gets the message that tells the user what to do; the history note says who and when
    WorkflowStepInvalidate.call(record: capital_call, actor: current_user, check_keys: %w[capital_call.create_remittances],
                                reason: "Remittances were calculated before the call figures changed — recompute")
    WorkflowStepInvalidate.call(record: capital_call, actor: current_user, check_keys: %w[capital_call.generate_notices],
                                reason: "Notices were generated before the call figures changed — unapprove them on the Documents screen, then click Generate Documents")
    capital_call.journey_undo_evaluate(note:, actor: current_user, started_at: ctx[:journey_undo_started_at] || Time.current)
    true
  end

  # Editing call_date after remittances already exist re-dates every capital_remittance to match
  # (see docs/modules/funds/call_and_distribution_date_cascade_plan.md) and triggers a fee recompute,
  # since the new date changes the exchange-rate lookup used for fee/amount conversions.
  def cascade_call_date_change(_ctx, capital_call:, current_user: nil, **)
    CapitalCallDateChangeJob.perform_later(capital_call.id, current_user.id) if capital_call.saved_change_to_call_date? && current_user
    true
  end
end
