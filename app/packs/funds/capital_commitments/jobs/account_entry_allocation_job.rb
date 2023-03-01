class AccountEntryAllocationJob < ApplicationJob
  queue_as :doc_gen
  # Ensure this job does not run multiple times if it fails
  sidekiq_options retry: 0

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(fund_id, start_date, end_date, formula_id: nil, user_id: nil,
              generate_soa: nil, template_name: nil, fund_ratios: nil)
    Chewy.strategy(:sidekiq) do
      fund = Fund.find(fund_id)
      begin
        AccountEntryAllocationEngine.new(fund, start_date, end_date,
                                         formula_id:, user_id:, generate_soa:,
                                         template_name:, fund_ratios:).run_formulas
      rescue Exception => e
        # notify("Please contact support. Error running fund formulas: #{e.message}", :danger, user_id)
        raise e
      end
    end
  end

  def notify(message, level, user_id)
    UserAlert.new(user_id:, message:, level:).broadcast
  end
end
