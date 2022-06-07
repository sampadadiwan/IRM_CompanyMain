class AggregateInvestmentsController < ApplicationController
  before_action :set_aggregate_investment, only: %i[show edit update destroy]
  after_action :verify_authorized, except: %i[index search investor_investments]

  # GET /aggregate_investments or /aggregate_investments.json
  def index
    @aggregate_investments = policy_scope(AggregateInvestment)

    @entity = current_user.entity

    @aggregate_investments = @aggregate_investments.includes(:investor, :entity)

    respond_to do |format|
      format.xlsx do
        response.headers[
          'Content-Disposition'
        ] = "attachment; filename=aggregate_investments.xlsx"
      end
      format.html { render :index }
      format.json { render :index }
      format.pdf do
        render template: "aggregate_investments/index", formats: [:html], pdf: "#{@entity.name} Aggregate Investments"
      end
    end
  end

  def investor_investments
    if params[:entity_id].present?
      @entity = Entity.find(params[:entity_id])
      @aggregate_investments = AggregateInvestment.for_investor(current_user, @entity)
    end

    @aggregate_investments = @aggregate_investments.order(id: :desc)
                                                   .includes(:investor, :entity).distinct

    render "index"
  end

  # GET /aggregate_investments/1 or /aggregate_investments/1.json
  def show; end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_aggregate_investment
    @aggregate_investment = AggregateInvestment.find(params[:id])
    authorize @aggregate_investment
  end

  # Only allow a list of trusted parameters through.
  def aggregate_investment_params
    params.require(:aggregate_investment).permit(:entity_id, :shareholder, :investor_id, :equity, :preferred,
                                                 :options, :percentage, :full_diluted_percentage)
  end
end
