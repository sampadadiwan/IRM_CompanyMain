class CapitalRemittanceVerify < CapitalRemittanceAction
  # Note: fees are NOT recomputed on verify/unverify. They are set on create/update
  # (CapitalRemittanceCreate/CapitalRemittanceUpdate), and verifying must not
  # overwrite them if account entries or fee formulas changed since then.
  step :reload_current
  step :start_journey_undo
  step :set_call_amount
  step :toggle_verify
  step :set_status
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :payment_received_notification
  step :touch_investor
  step :evaluate_journey_on_unverify

  # P6 (funds-json-api-hardening H26 E31): a bulk verify job loads every remittance when it starts;
  # by the time it gets to one, a payment import or another job may have changed its verified flag or
  # collected amount. Toggling the stale copy applied the wrong amount to the call / fund / commitment
  # rollups (or applied it twice). Start from the row's current verified flag and collected amount; the
  # toggle itself is unchanged. Only those two columns are re-read, so the bulk job's preloaded
  # associations are kept (no extra queries per remittance).
  def reload_current(_ctx, capital_remittance:, **)
    return true unless capital_remittance.persisted?

    verified, collected = CapitalRemittance.where(id: capital_remittance.id).pick(:verified, :collected_amount_cents)
    capital_remittance.verified = verified
    capital_remittance.collected_amount_cents = collected
    # Fresh values, not edits: the rollups must see only the toggle as a change
    capital_remittance.clear_attribute_changes(%i[verified collected_amount_cents])
    true
  end

  def toggle_verify(_ctx, capital_remittance:, **)
    capital_remittance.verified = !capital_remittance.verified
    true
  end

  def start_journey_undo(ctx, **)
    ctx[:journey_undo_started_at] = Time.current
    true
  end

  # Un-verifying is an undoing action (capital-call-journey); the bulk toggle job passes
  # skip_journey and evaluates each call once at the end instead.
  # Worked examples E18 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  def evaluate_journey_on_unverify(ctx, capital_remittance:, skip_journey: false, current_user: nil, **)
    return true if skip_journey

    # Verifying moves the journey forward: re-check as progress for real-time updates
    if capital_remittance.verified
      capital_remittance.capital_call.journey_progress!(actor: current_user)
      return true
    end

    capital_remittance.capital_call.journey_undo_evaluate(note: "Remittance #{capital_remittance} unverified",
                                                          actor: current_user, started_at: ctx[:journey_undo_started_at])
    true
  end

  def payment_received_notification(_ctx, capital_remittance:, **)
    # removed checks from here as they are already present in the model
    # Here we will have to send out the notifications for the remittance_payments and not remittance
    capital_remittance.capital_remittance_payments.each(&:notify_capital_remittance_payment)
    true
  end
end
