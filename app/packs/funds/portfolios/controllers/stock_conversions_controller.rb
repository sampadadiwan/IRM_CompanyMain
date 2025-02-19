class StockConversionsController < ApplicationController
  before_action :set_stock_conversion, only: %i[show edit update destroy reverse]
  has_scope :fund_id
  has_scope :entity_id
  has_scope :from_instrument_id
  has_scope :to_instrument_id
  has_scope :from_portfolio_investment_id
  has_scope :to_portfolio_investment_id

  # GET /stock_conversions or /stock_conversions.json
  def index
    @stock_conversions = apply_scopes(policy_scope(StockConversion)).includes(:fund, :from_instrument, :to_instrument, to_portfolio_investment: :investment_instrument, from_portfolio_investment: :investment_instrument)
    @stock_conversions = @stock_conversions.page(params[:page])
  end

  # GET /stock_conversions/1 or /stock_conversions/1.json
  def show; end

  # GET /stock_conversions/new
  def new
    @stock_conversion = StockConversion.new(stock_conversion_params)
    @stock_conversion.conversion_date ||= Time.zone.today
    @stock_conversion.entity_id = @stock_conversion.from_portfolio_investment.entity_id
    @stock_conversion.fund_id = @stock_conversion.from_portfolio_investment.fund_id
    @stock_conversion.from_instrument_id = @stock_conversion.from_portfolio_investment.investment_instrument_id
    @stock_conversion.from_quantity = @stock_conversion.from_portfolio_investment.net_quantity
    authorize @stock_conversion
  end

  # GET /stock_conversions/1/edit
  def edit; end

  # POST /stock_conversions or /stock_conversions.json
  def create
    @stock_conversion = StockConversion.new(stock_conversion_params)
    authorize @stock_conversion
    result = StockConverter.call(stock_conversion: @stock_conversion)
    respond_to do |format|
      if result.success?
        format.html { redirect_to stock_conversion_url(@stock_conversion), notice: "Stock conversion was successfully created." }
        format.json { render :show, status: :created, location: @stock_conversion }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @stock_conversion.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /stock_conversions/1 or /stock_conversions/1.json
  def update
    respond_to do |format|
      if @stock_conversion.update(stock_conversion_params)
        format.html { redirect_to stock_conversion_url(@stock_conversion), notice: "Stock conversion was successfully updated." }
        format.json { render :show, status: :ok, location: @stock_conversion }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @stock_conversion.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /stock_conversions/1 or /stock_conversions/1.json
  def destroy
    @stock_conversion.destroy!

    respond_to do |format|
      format.html { redirect_to stock_conversions_url, notice: "Stock conversion was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def reverse
    if StockConverterReverse.call(stock_conversion: @stock_conversion).success?
      redirect_to stock_conversions_url, notice: "Stock conversion was successfully reversed."
    else
      redirect_to stock_conversions_url, alert: "Stock conversion could not be reversed."
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_stock_conversion
    @stock_conversion = StockConversion.find(params[:id])
    authorize @stock_conversion
  end

  # Only allow a list of trusted parameters through.
  def stock_conversion_params
    params.require(:stock_conversion).permit(:entity_id, :from_portfolio_investment_id, :fund_id, :from_instrument_id, :from_quantity, :to_instrument_id, :to_quantity, :notes, :conversion_date)
  end
end
