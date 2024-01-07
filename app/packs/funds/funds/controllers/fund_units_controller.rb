class FundUnitsController < ApplicationController
  include FundsHelper
  before_action :set_fund_unit, only: %i[show edit update destroy]

  # GET /fund_units or /fund_units.json
  def index
    @q = FundUnit.ransack(params[:q])
    @fund_units = policy_scope(@q.result).includes(:fund, :capital_commitment)
    @fund_units = @fund_units.where(capital_commitment_id: params[:capital_commitment_id]) if params[:capital_commitment_id]
    @fund_units = @fund_units.where(fund_id: params[:fund_id]) if params[:fund_id]
    @fund_units = @fund_units.where(investor_id: params[:investor_id]) if params[:investor_id]
    @fund_units = @fund_units.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id]

    if params[:owner_id] && params[:owner_type]
      @fund_units = @fund_units.where(owner_id: params[:owner_id])
      @fund_units = @fund_units.where(owner_type: params[:owner_type])
    end

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
      format.html { redirect_to fund_units_url, notice: "Fund unit was successfully destroyed." }
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
