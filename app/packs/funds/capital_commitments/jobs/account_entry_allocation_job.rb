class AccountEntryAllocationJob < ApplicationJob
  queue_as :high
  # Ensure this job does not run multiple times if it fails
  sidekiq_options retry: 0

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(fund_id, start_date, end_date, user_id: nil, run_allocations: true, explain: false,
              generate_soa: nil, template_id: nil, fund_ratios: nil, sample: nil, rule_for: nil, tag_list: nil, allocation_run_id: nil, timing: false)
    Rails.logger.info "Running AccountEntryAllocationJob for Fund ID: #{fund_id}, Start Date: #{start_date}, End Date: #{end_date}, User ID: #{user_id}"
    Chewy.strategy(:sidekiq) do
      fund = Fund.find(fund_id)
      user = User.find(user_id)
      Audited.audit_class.as_user(user) do
        AccountEntryAllocation::Engine.new(fund, start_date, end_date, run_allocations:, explain:, user_id:, generate_soa:, rule_for:, tag_list:, template_id:, fund_ratios:, sample:, allocation_run_id:, timing:).call
      end
    end
  end

  def notify(message, level, user_id)
    UserAlert.new(user_id:, message:, level:).broadcast
  end
end
