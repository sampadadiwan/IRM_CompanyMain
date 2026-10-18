# Approving a capital call, as the Approve button does: approve-time validation rules first (a blocker
# stops it, warnings are passed back), then CapitalCallApprove. Shared by CapitalCallsController#approve and
# the bulk approve (CapitalCallsBulkActionJob) so one call and forty calls are approved the same way.
# openspec/changes/funds-json-api-hardening — phase 10, P12.
class CapitalCallApproval
  Result = Struct.new(:success, :blocked, :warnings, :errors, keyword_init: true) do
    def success? = success
    def blocked? = blocked
  end

  def self.call(capital_call:, user:)
    # Evaluate rules against the current (pre-approval) record state
    rule_results = ValidationRuleEvaluator.call(record: capital_call, entity: user.entity)
    blockers = rule_results.select(&:blocker?)
    return Result.new(success: false, blocked: true, warnings: [], errors: blockers.map(&:message).join(" ")) if blockers.any?

    capital_call.approved = true
    capital_call.approved_by_user = user
    # Skip model-level re-evaluation — already evaluated above
    result = WithValidationRules.skip { CapitalCallApprove.call(capital_call:) }
    Result.new(success: result.success?, blocked: false, warnings: rule_results.select(&:warning?), errors: result[:errors])
  end
end
