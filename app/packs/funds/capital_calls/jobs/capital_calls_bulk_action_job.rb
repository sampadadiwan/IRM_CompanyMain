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
    [:fund]
  end

  def perform_action(capital_call, user_id, bulk_action, params: {})
    action = bulk_action.to_s.downcase.tr("_", " ")
    query = ACTIONS[action]
    return send_notification("Invalid bulk action", user_id, :error) unless query
    # The same permission the single-call action checks (e.g. approvers only for approve)
    return record_failure(capital_call, "Not authorized to #{action}") unless Pundit.policy!(@user, capital_call).public_send(query)

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

  private

  def record_failure(capital_call, message)
    @error_msg << { msg: message, capital_call: capital_call.name, capital_call_id: capital_call.id }
  end
end
