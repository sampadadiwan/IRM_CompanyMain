class GenerateDealActivitiesJob < ApplicationJob
  queue_as :default

  def perform(id, class_name)
    Chewy.strategy(:atomic) do
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
