class InvestorAddedJob < ApplicationJob
  queue_as :low

  def perform(id)
    Chewy.strategy(:sidekiq) do
      investor = Investor.find(id)
      investor.entity.investor_notices.where(owner: nil, generate: true).find_each do |notice|
        InvestorNoticeJob.perform_now(notice.id)
      end
    end
  end
end
