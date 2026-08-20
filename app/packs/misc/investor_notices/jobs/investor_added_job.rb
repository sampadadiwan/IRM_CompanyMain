class InvestorAddedJob < ApplicationJob
  queue_as :low

  def perform(id)
    Chewy.strategy(:sidekiq) do
      investor = Investor.find(id)
      # Entity-wide notices (owner nil) always regenerate for a newly added
      # investor. Owner-scoped notices (Fund/SecondarySale/Deal) only
      # regenerate when this investor is actually part of that owner's
      # granted-access audience — otherwise every investor added anywhere in
      # the GP would pick up entries for notices scoped to funds/deals they
      # have no access to.
      investor.entity.investor_notices.where(generate: true, active: true).find_each do |notice|
        next if notice.owner.present? && !notice.investors.exists?(id: investor.id)

        InvestorNoticeJob.perform_now(notice.id)
      end
    end
  end
end
