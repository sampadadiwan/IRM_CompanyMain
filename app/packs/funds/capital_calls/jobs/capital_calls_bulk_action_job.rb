# Bulk actions on capital calls (POST /capital_calls/bulk_actions) — approve and allocate units for many
# calls in one request, each exactly as its single-call button does, with the same per-call permission.
# Failures are collected and reported by BulkActionJob's completion notification and email.
# openspec/changes/funds-json-api-hardening — phase 10, P12.
class CapitalCallsBulkActionJob < BulkActionJob
  # bulk_action → the policy query the single-call action authorises with
  ACTIONS = { "approve" => :approve?, "allocate units" => :allocate_units? }.freeze

  def get_class
    CapitalCall
  end

  def record_includes
    # M13 — the firm's maker–checker switch is read per call by approve?; loaded with the calls
    [:fund, { entity: :entity_setting }]
  end

  def perform_action(capital_call, user_id, bulk_action, params: {})
    action = bulk_action.to_s.downcase.tr("_", " ")
    query = ACTIONS[action]
    return send_notification("Invalid bulk action", user_id, :error) unless query

    # X7 (M13) — the batch's preparers in three queries, once per job, before the per-call checks
    preload_approval_makers(capital_call) if action == "approve"
    # The same permission the single-call action checks (e.g. approvers only for approve)
    policy = Pundit.policy!(@user, capital_call)
    unless policy.public_send(query)
      # X7 (M13) — maker–checker on and this approver prepared the call: say so, instead of a bare refusal
      return record_failure(capital_call, "You prepared #{capital_call.name} — another approver must approve it") if action == "approve" && policy.awaiting_second_approver?

      return record_failure(capital_call, "Not authorized to #{action}")
    end

    case action
    when "approve"
      # Already approved: nothing to do (the single action refuses it the same way via approve?)
      result = CapitalCallApproval.call(capital_call:, user: @user)
      record_failure(capital_call, result.errors.presence || capital_call.errors.full_messages.join(", ")) unless result.success?
    when "allocate units"
      # The same job the Allocate Units button queues; units_job_finished_at says when it is done (G18)
      FundUnitsJob.perform_later(capital_call.id, "CapitalCall", capital_call.name, user_id)
    end
  end

  # The batch's record ids, for the one-off preparer preload below
  def perform(record_ids, user_id, bulk_action, params: {})
    @batch_ids = record_ids
    super
  end

  private

  def preload_approval_makers(capital_call)
    @approval_makers ||= CapitalCall.approval_maker_entries_for(@batch_ids || [capital_call.id])
    capital_call.preload_preparer_entries(*@approval_makers.fetch(capital_call.id, [nil, [], false]))
  end

  def record_failure(capital_call, message)
    @error_msg << { msg: message, capital_call: capital_call.name, capital_call_id: capital_call.id }
  end
end
