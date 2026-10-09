class CapitalRemittancesRecomputeFeesJob < BulkActionJob
  def perform(capital_call_id, user_id = nil)
    send_notification("Recomputing fees for all capital remittances for capital call #{@capital_call}", user_id, :info)

    @error_msg = []
    @capital_call = CapitalCall.find(capital_call_id)
    journey_undo_started_at = Time.current
    processed_count = 0
    Chewy.strategy(:sidekiq) do
      @capital_call.capital_remittances.includes(:fund, :entity, { investor: :investor_entity }, { capital_commitment: :investor_kyc }, :form_type, :documents).find_each do |capital_remittance|
        CapitalRemittanceUpdate.call(capital_remittance:, recompute_call_amount: true)
        processed_count += 1
      rescue StandardError => e
        msg = "Error recomputing fees for capital remittance #{capital_remittance.id}: #{e.message}"
        send_notification(msg, user_id, :danger)
        @error_msg << { msg:, folio_id: capital_remittance.folio_id, capital_remittance_id: capital_remittance.id, for: capital_remittance.capital_call }
      end
    end

    if @error_msg.present?
      msg = "Recompute completed for #{processed_count} records, with #{@error_msg.length} errors. Errors will be sent via email"
      send_notification(msg, user_id, :danger)
      EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg: @error_msg).doc_gen_errors.deliver_now
    else
      send_notification("Recomputed fees for all capital remittances successfully for capital call #{@capital_call}", user_id, :info)
      record_recompute_in_journey(user_id, journey_undo_started_at)
    end
  end

  private

  # Recompute is an undoing action (capital-call-journey): only a run with no row errors counts as
  # "remittances recalculated" (the marker Create remittances needs after a figures change), and the
  # amounts just changed, so the notices are stale until regenerated.
  # Worked examples E13 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  def record_recompute_in_journey(user_id, started_at)
    actor = User.find_by(id: user_id)
    WorkflowStepInvalidate.record_refresh(record: @capital_call, check_key: "capital_call.create_remittances",
                                          actor:, note: "Remittances recomputed")
    WorkflowStepInvalidate.call(record: @capital_call, actor:, check_keys: %w[capital_call.generate_notices],
                                reason: "Notices were generated before the remittances changed — unapprove them on the Documents screen, then click Generate Documents")
    @capital_call.journey_undo_evaluate(note: "Remittances recomputed", actor:, started_at:)
  end
end
