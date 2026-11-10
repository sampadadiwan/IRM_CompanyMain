# Bulk actions on capital distributions (POST /capital_distributions/bulk_actions) — approve and redeem
# units for many distributions in one request, each exactly as its single button does, with the same
# per-distribution permission. Failures are reported by BulkActionJob's completion notification and email.
# openspec/changes/funds-json-api-hardening — phase 10, P12.
class CapitalDistributionsBulkActionJob < BulkActionJob
  # bulk_action → the policy query the single action authorises with
  ACTIONS = { "approve" => :approve?, "redeem units" => :redeem_units? }.freeze

  def get_class
    CapitalDistribution
  end

  def record_includes
    # M13 — the firm's maker–checker switch is read per distribution by approve?; loaded with the distributions
    [:fund, { entity: :entity_setting }]
  end

  # The batch's record ids, for the one-off preparer preload below
  def perform(record_ids, user_id, bulk_action, params: {})
    @batch_ids = record_ids
    super
  end

  def perform_action(capital_distribution, user_id, bulk_action, params: {})
    action = bulk_action.to_s.downcase.tr("_", " ")
    query = ACTIONS[action]
    return send_notification("Invalid bulk action", user_id, :error) unless query

    # X8 (M13) — the batch's preparers in three queries, once per job, before the per-distribution checks
    preload_approval_makers(capital_distribution) if action == "approve"
    policy = Pundit.policy!(@user, capital_distribution)
    unless policy.public_send(query)
      # X8 (M13) — maker–checker on and this approver prepared it: say so, instead of a bare refusal
      return record_failure(capital_distribution, "You prepared #{capital_distribution.title} — another approver must approve it") if action == "approve" && policy.awaiting_second_approver?

      return record_failure(capital_distribution, "Not authorized to #{action}")
    end

    case action
    when "approve"
      # As CapitalDistributionsController#approve: approve, save, then journey progress
      capital_distribution.approved = true
      capital_distribution.approved_by_user = @user
      if capital_distribution.save
        capital_distribution.journey_progress!(actor: @user)
      else
        record_failure(capital_distribution, capital_distribution.errors.full_messages.join(", "))
      end
    when "redeem units"
      # The same job the Redeem Units button queues; units_job_finished_at says when it is done (G18)
      FundUnitsJob.perform_later(capital_distribution.id, "CapitalDistribution", capital_distribution.title, user_id)
    end
  end

  private

  def preload_approval_makers(capital_distribution)
    @approval_makers ||= CapitalDistribution.approval_maker_entries_for(@batch_ids || [capital_distribution.id])
    capital_distribution.preload_preparer_entries(*@approval_makers.fetch(capital_distribution.id, [nil, [], false]))
  end

  def record_failure(capital_distribution, message)
    @error_msg << { msg: message, capital_distribution: capital_distribution.title, capital_distribution_id: capital_distribution.id }
  end
end
