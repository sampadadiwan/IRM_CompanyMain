class StockAdjustmentsController < ApplicationController
  before_action :set_stock_adjustment, only: %i[show edit update destroy]

  # GET /stock_adjustments or /stock_adjustments.json
  def index
    @stock_adjustments = policy_scope(StockAdjustment)
  end

  # GET /stock_adjustments/1 or /stock_adjustments/1.json
  def show; end

  # GET /stock_adjustments/new
  def new
    @stock_adjustment = StockAdjustment.new
    @stock_adjustment.entity_id = current_user.entity_id
    @stock_adjustment.user_id = current_user.id
    @stock_adjustment.portfolio_company_id = params[:portfolio_company_id]
    authorize @stock_adjustment
  end

  # GET /stock_adjustments/1/edit
  def edit; end

  # POST /stock_adjustments or /stock_adjustments.json
  def create
    @stock_adjustment = StockAdjustment.new(stock_adjustment_params)
    @stock_adjustment.entity_id = current_user.entity_id
    @stock_adjustment.user_id = current_user.id
    authorize @stock_adjustment

    respond_to do |format|
      if @stock_adjustment.save
        format.html { redirect_to stock_adjustment_url(@stock_adjustment), notice: "Stock adjustment was successfully created." }
        format.json { render :show, status: :created, location: @stock_adjustment }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @stock_adjustment.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /stock_adjustments/1 or /stock_adjustments/1.json
  def update
    respond_to do |format|
      if @stock_adjustment.update(stock_adjustment_params)
        format.html { redirect_to stock_adjustment_url(@stock_adjustment), notice: "Stock adjustment was successfully updated." }
        format.json { render :show, status: :ok, location: @stock_adjustment }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @stock_adjustment.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /stock_adjustments/1 or /stock_adjustments/1.json
  def destroy
    @stock_adjustment.destroy

    respond_to do |format|
      format.html { redirect_to stock_adjustments_url, notice: "Stock adjustment was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_stock_adjustment
    @stock_adjustment = StockAdjustment.find(params[:id])
    authorize @stock_adjustment
  end

  # Only allow a list of trusted parameters through.
  def stock_adjustment_params
    params.require(:stock_adjustment).permit(:entity_id, :portfolio_company_id, :investment_instrument_id, :user_id, :adjustment, :notes)
  end
end
