class FundUnitsController < ApplicationController
  include FundsHelper
  before_action :set_fund_unit, only: %i[show edit update destroy]

  # GET /fund_units or /fund_units.json
  def index
    # Step 1: Base query with Ransack and policy scope
    @q = FundUnit.ransack(params[:q])
    @fund_units = policy_scope(@q.result).includes(:fund, :capital_commitment)

    # Step 2: Apply basic filters using helper
    @fund_units = filter_params(
      @fund_units,
      :capital_commitment_id,
      :fund_id,
      :investor_id,
      :import_upload_id,
      :owner_id,
      :owner_type
    )

    # Step 3: Set breadcrumbs for navigation
    fund_bread_crumbs("Fund Units")
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
