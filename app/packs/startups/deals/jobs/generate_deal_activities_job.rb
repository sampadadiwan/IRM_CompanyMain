class GenerateDealActivitiesJob < ApplicationJob
  queue_as :critical

  def perform(id, class_name)
    Chewy.strategy(:sidekiq) do
      case class_name
      when "Deal"
        @deal = Deal.find(id)
        @deal.create_activities
      when "DealInvestor"
        @deal_investor = DealInvestor.find(id)
        @deal_investor.create_activities
      end
    end
  end
end
