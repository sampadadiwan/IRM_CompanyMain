class InvestorAddedJob < ApplicationJob
  queue_as :default

  def perform(id)
    Chewy.strategy(:atomic) do
      investor = Investor.find(id)
      investor.entity.investor_notices.where(generate: true).each do |notice|
        InvestorNoticeJob.perform_now(notice.id)
      end
    end
  end
end
