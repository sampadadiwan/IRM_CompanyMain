class FundRatiosController < ApplicationController
  before_action :set_fund_ratio, only: %i[show edit update destroy]

  # GET /fund_ratios or /fund_ratios.json
  def index
    @q = FundRatio.ransack(params[:q])

    @fund_ratios = policy_scope(@q.result).includes(:fund, :capital_commitment)

    if params[:fund_id].present?
      @fund_ratios = @fund_ratios.where(fund_id: params[:fund_id])
      @fund ||= Fund.find(params[:fund_id])
    end
    @fund_ratios = @fund_ratios.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
    @fund_ratios = @fund_ratios.where(capital_commitment_id: params[:capital_commitment_id]) if params[:capital_commitment_id].present?
    @fund_ratios = @fund_ratios.where(capital_commitment_id: nil) if params[:fund_ratios_only].present?

    @fund_ratios = @fund_ratios.where(owner_type: params[:owner_type]) if params[:owner_type].present?
    @fund_ratios = @fund_ratios.where(owner_id: params[:owner_id]) if params[:owner_id].present?
    @fund_ratios = @fund_ratios.where(scenario: params[:scenario]) if params[:scenario].present?
    @fund_ratios = @fund_ratios.where(latest: true) if params[:latest] == "true"
    @fund_ratios = @fund_ratios.where(valuation_id: params[:valuation_id]) if params[:valuation_id].present?
    respond_to do |format|
      format.html
      format.turbo_stream
      format.xlsx
      format.json { render json: FundRatioDatatable.new(params, fund_ratios: @fund_ratios) }
    end
  end

  # GET /fund_ratios/1 or /fund_ratios/1.json
  def show; end

  # GET /fund_ratios/new
  def new
    @fund_ratio = FundRatio.new(fund_ratio_params)
    authorize(@fund_ratio)
  end

  # GET /fund_ratios/1/edit
  def edit; end

  # POST /fund_ratios or /fund_ratios.json
  def create
    @fund_ratio = FundRatio.new(fund_ratio_params)
    authorize(@fund_ratio)
    respond_to do |format|
      if @fund_ratio.save
        format.html { redirect_to fund_ratio_url(@fund_ratio), notice: "Fund ratio was successfully created." }
        format.json { render :show, status: :created, location: @fund_ratio }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @fund_ratio.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /fund_ratios/1 or /fund_ratios/1.json
  def update
    respond_to do |format|
      if @fund_ratio.update(fund_ratio_params)
        format.html { redirect_to fund_ratio_url(@fund_ratio), notice: "Fund ratio was successfully updated." }
        format.json { render :show, status: :ok, location: @fund_ratio }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @fund_ratio.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /fund_ratios/1 or /fund_ratios/1.json
  def destroy
    @fund_ratio.destroy

    respond_to do |format|
      format.html { redirect_to fund_ratios_url, notice: "Fund ratio was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_fund_ratio
    @fund_ratio = FundRatio.find(params[:id])
    authorize(@fund_ratio)
    @bread_crumbs = { Funds: funds_path,
                      "#{@fund_ratio.fund.name}": fund_path(@fund_ratio.fund),
                      'Fund Ratios': fund_ratios_path(fund_id: @fund_ratio.fund_id, filter: true),
                      "#{@fund_ratio}": nil }
  end

  # Only allow a list of trusted parameters through.
  def fund_ratio_params
    params.require(:fund_ratio).permit(:entity_id, :fund_id, :capital_commitment_id, :valuation_id, :name, :value, :display_value, :notes)
  end
end
