class GenerateDealActivitiesJob < ApplicationJob
  queue_as :serial

  def perform(id, class_name)
    Chewy.strategy(:active_job) do
      case class_name
      when "Deal"
        @deal = Deal.find(id)
        @deal.create_activities
        @deal.broadcast_message("Deal steps were created, please refresh your page.")
      when "DealInvestor"
        @deal_investor = DealInvestor.find(id)
        @deal_investor.create_activities
        @deal_investor.deal.broadcast_message("Deal steps were created, please refresh your page.")
      end
    end
  end
end
