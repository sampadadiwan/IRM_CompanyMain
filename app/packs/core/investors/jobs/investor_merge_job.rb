class InvestorMergeJob < ApplicationJob
  queue_as :low

  def perform(old_investor_id, new_investor_id, user_id)
    Chewy.strategy(:sidekiq) do
      old_investor = Investor.find(old_investor_id)
      new_investor = Investor.find(new_investor_id)
      # merge returns how many of the old linked firm's users it left in place (C5-2 / C5-3)
      users_not_moved = Investor.merge(old_investor, new_investor)

      message = "Merged #{old_investor.investor_name} into #{new_investor.investor_name}"
      level = :success
      if users_not_moved.to_i.positive?
        # C5-2 / C5-3 — a linked firm is shared with another GP: the data merged, the contacts did not
        message += ". #{users_not_moved} contacts not moved — ask CapHive support to merge the entities"
        level = :warning
      end
      UserAlert.new(user_id:, message:, level:).broadcast if user_id.present?
    end
  end
end
