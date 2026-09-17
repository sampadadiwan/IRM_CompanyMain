class GenerateDealActivitiesJob < ApplicationJob
  queue_as :serial

  def perform(id, class_name, user_id = nil)
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
        # Inline: this is already a background job, and the broadcast below tells open screens to
        # refresh — the first step's tasks have to exist by then, not one queue hop later.
        @deal_investor.set_deal_investor_activity(user_id, synchronous: true)
        @deal_investor.deal.broadcast_message("Deal steps were created, please refresh your page.")
        @deal_investor.deal.kanban_board.presence&.broadcast_board_event
      end
    end
  end
end
