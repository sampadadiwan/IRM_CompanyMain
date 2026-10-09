class FundUnitsController < ApplicationController
  include FundsHelper

  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 500

  before_action :set_fund_unit, only: %i[show edit update destroy]

  # GET /fund_units or /fund_units.json
  def index
    fetch_rows

    # Step 3: Set breadcrumbs for navigation
    fund_bread_crumbs("Fund Units")
  end

  def fetch_rows
    authorize(FundUnit)
    service = FundUnitList.call(current_user, params) { |relation| policy_scope(relation) }
    @q = service.q
    @fund_units = service.fund_units
    paginate_fund_units if paginate?

    @fund_units
  end

  # GET /fund_units/1 or /fund_units/1.json
  def show; end

  # GET /fund_units/new
  def new
    @fund_unit = FundUnit.new(fund_unit_params)
    authorize @fund_unit
  end

  # GET /fund_units/1/edit
  def edit; end

  # POST /fund_units or /fund_units.json
  def create
    @fund_unit = FundUnit.new(fund_unit_params)
    authorize @fund_unit

    respond_to do |format|
      if @fund_unit.save
        format.html { redirect_to fund_unit_url(@fund_unit), notice: "Fund unit was successfully created." }
        format.json { render :show, status: :created, location: @fund_unit }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @fund_unit.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /fund_units/1 or /fund_units/1.json
  def update
    respond_to do |format|
      if @fund_unit.update(fund_unit_params)
        format.html { redirect_to fund_unit_url(@fund_unit), notice: "Fund unit was successfully updated." }
        format.json { render :show, status: :ok, location: @fund_unit }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @fund_unit.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /fund_units/1 or /fund_units/1.json
  def destroy
    @fund_unit.destroy

    respond_to do |format|
      format.html { redirect_to @fund_unit.owner, notice: "Fund unit was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # The xlsx download and json keep returning every matching unit
  def paginate?
    params[:all].blank? && request.format.html?
  end

  # Pagy raises for a page outside 1..total_pages, so clamp it ourselves: a stale
  # bookmark or a filter change that shrinks the list shows the nearest valid page.
  def paginate_fund_units
    per_page = params[:per_page].to_i
    per_page = DEFAULT_PER_PAGE unless per_page.positive?
    per_page = [per_page, MAX_PER_PAGE].min

    count = @fund_units.count
    total_pages = [(count.to_f / per_page).ceil, 1].max
    page = params[:page].to_i.clamp(1, total_pages)

    @pagy, @fund_units = pagy(@fund_units, limit: per_page, page:, count:)
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_fund_unit
    @fund_unit = FundUnit.find(params[:id])
    authorize @fund_unit
    @bread_crumbs = { Funds: funds_path, "#{@fund_unit.fund.name}": fund_path(@fund_unit.fund),
                      # "Fund Units": fund_units_path(fund_id: @fund_unit.fund_id),
                      "#{@fund_unit.capital_commitment}": capital_commitment_path(@fund_unit.capital_commitment),
                      "#{@fund_unit}": nil }
  end

  # Only allow a list of trusted parameters through.
  def fund_unit_params
    params.require(:fund_unit).permit(:fund_id, :capital_commitment_id, :investor_id, :unit_type, :quantity, :reason)
  end
end
