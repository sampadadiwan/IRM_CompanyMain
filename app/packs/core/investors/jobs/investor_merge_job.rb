class InvestorMergeJob < ApplicationJob
  queue_as :low

  def perform(old_investor_id, new_investor_id, user_id)
    Chewy.strategy(:sidekiq) do
      old_investor = Investor.find(old_investor_id)
      new_investor = Investor.find(new_investor_id)
      Investor.merge(old_investor, new_investor)

      message = "Merged #{old_investor.investor_name} into #{new_investor.investor_name}"
      level = :success
      UserAlert.new(user_id:, message:, level:).broadcast if user_id.present?
    end
  end
end
