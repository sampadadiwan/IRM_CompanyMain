class GenerateDealActivitiesJob < ApplicationJob
  queue_as :serial

  def perform(id, class_name)
    Chewy.strategy(:sidekiq) do
      case class_name
      when "Deal"
        @deal = Deal.find(id)
        @deal.create_activities
        @deal.broadcast_message("Deal steps were created, please refresh your page.")
      when "DealInvestor"
        Rails.logger.info "Generating deal activities for DealInvestor with id: #{id}"
        @deal_investor = DealInvestor.find(id)
        @deal_investor.create_activities
        @deal_investor.deal.broadcast_message("Deal steps were created, please refresh your page.")
        @deal_investor.deal.kanban_board.broadcast_board_event if @deal_investor.deal.kanban_board.present?
      end
    end
  end
end
