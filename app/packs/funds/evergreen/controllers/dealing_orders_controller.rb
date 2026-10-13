# GET /dealing_orders/:id/journey — just the order's journey panel, for the frame a real-time update
# reloads (Workflowable#broadcast_journey_change requests /<plural>/:id/journey).
class DealingOrdersController < ApplicationController
  include WithJourneyPanel

  def journey
    @dealing_order = DealingOrder.find(params[:id])
    authorize @dealing_order, :show?
    render_journey_panel(@dealing_order)
  end
end
