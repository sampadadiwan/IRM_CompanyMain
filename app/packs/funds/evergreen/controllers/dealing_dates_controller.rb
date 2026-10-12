# GET /dealing_dates/:id/journey — just the dealing date's journey panel, for live refreshes.
class DealingDatesController < ApplicationController
  include WithJourneyPanel

  def journey
    @dealing_date = DealingDate.find(params[:id])
    authorize @dealing_date, :show?
    render_journey_panel(@dealing_date)
  end
end
