class FundRatiosController < ApplicationController
  before_action :set_fund_ratio, only: %i[show edit update destroy]

  # GET /fund_ratios or /fund_ratios.json
  def index
    # Step 1: Perform Ransack search
    @q = FundRatio.ransack(params[:q])
    @fund_ratios = policy_scope(@q.result).includes(:fund, :capital_commitment, :portfolio_scenario)

    @fund_ratios = FundRatioSearch.perform(@fund_ratios, current_user, params)

    @fund = Fund.find(params[:fund_id]) if params[:fund_id].present?

    # Step 3: Apply additional filters using custom helper
    @fund_ratios = filter_params(
      @fund_ratios,
      :import_upload_id,
      :capital_commitment_id,
      :portfolio_scenario_id,
      :owner_type,
      :owner_id,
      :scenario,
      :valuation_id,
      :fund_id
    )

    # Step 4: Special filters with more specific logic
    @fund_ratios = @fund_ratios.where(capital_commitment_id: nil) if params[:fund_ratios_only].present?
    @fund_ratios = @fund_ratios.where(latest: true) if params[:latest] == "true"

    # Step 5: Pivot grouping (if requested)
    if params[:pivot].present?
      group_by_period = params[:group_by_period] || :quarter
      @pivot = FundRatioPivot.new(@fund_ratios.includes(:fund), group_by_period:).call
    elsif params[:all].blank? && params[:condensed].blank?
      @pagy, @fund_ratios = pagy(@fund_ratios, limit: params[:per_page])
    end

    # Step 6: Render appropriate format
    respond_to do |format|
      format.html
      format.turbo_stream
      format.xlsx
      format.json
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
    params.require(:fund_ratio).permit(:entity_id, :fund_id, :capital_commitment_id, :valuation_id, :name, :value, :display_value, :label, :notes)
  end
end
