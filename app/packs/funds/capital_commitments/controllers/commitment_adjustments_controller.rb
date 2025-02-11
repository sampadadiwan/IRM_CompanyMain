class CommitmentAdjustmentsController < ApplicationController
  before_action :set_commitment_adjustment, only: %i[show edit update destroy]

  # GET /commitment_adjustments or /commitment_adjustments.json
  def index
    @commitment_adjustments = policy_scope(CommitmentAdjustment).includes(:fund)
    @commitment_adjustments = @commitment_adjustments.where(capital_commitment_id: params[:capital_commitment_id]) if params[:capital_commitment_id].present?
    @commitment_adjustments = @commitment_adjustments.where(fund_id: params[:fund_id]) if params[:fund_id].present?
  end

  # GET /commitment_adjustments/1 or /commitment_adjustments/1.json
  def show; end

  # GET /commitment_adjustments/new
  def new
    @commitment_adjustment = CommitmentAdjustment.new(commitment_adjustment_params)
    @commitment_adjustment.entity_id = @commitment_adjustment.capital_commitment.entity_id
    @commitment_adjustment.fund_id = @commitment_adjustment.capital_commitment.fund_id
    @commitment_adjustment.as_of = @commitment_adjustment.owner_type == "CapitalRemittance" ? @commitment_adjustment.owner.payment_date : Time.zone.today
    authorize @commitment_adjustment
  end

  # GET /commitment_adjustments/1/edit
  def edit; end

  # POST /commitment_adjustments or /commitment_adjustments.json
  def create
    @commitment_adjustment = CommitmentAdjustment.new(commitment_adjustment_params)
    authorize @commitment_adjustment
    result = AdjustmentCreate.call(commitment_adjustment: @commitment_adjustment)
    respond_to do |format|
      if result.success?
        format.html { redirect_to commitment_adjustment_url(@commitment_adjustment), notice: "Commitment adjustment was successfully created." }
        format.json { render :show, status: :created, location: @commitment_adjustment }
      else
        logger.error "Error creating commitment adjustment: #{result[:errors]}"
        format.html { render :new, status: :unprocessable_entity, notice: result[:errors] }
        format.json { render json: @commitment_adjustment.errors, status: :unprocessable_entity }
      end
    end
  end

  # # PATCH/PUT /commitment_adjustments/1 or /commitment_adjustments/1.json
  # def update
  #   respond_to do |format|
  #     if @commitment_adjustment.update(commitment_adjustment_params)
  #       format.html { redirect_to commitment_adjustment_url(@commitment_adjustment), notice: "Commitment adjustment was successfully updated." }
  #       format.json { render :show, status: :ok, location: @commitment_adjustment }
  #     else
  #       format.html { render :edit, status: :unprocessable_entity }
  #       format.json { render json: @commitment_adjustment.errors, status: :unprocessable_entity }
  #     end
  #   end
  # end

  # DELETE /commitment_adjustments/1 or /commitment_adjustments/1.json
  def destroy
    @commitment_adjustment.destroy

    respond_to do |format|
      format.html { redirect_to capital_commitment_url(@commitment_adjustment.capital_commitment), notice: "Commitment adjustment was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_commitment_adjustment
    @commitment_adjustment = CommitmentAdjustment.find(params[:id])
    authorize @commitment_adjustment
    @bread_crumbs = { Funds: funds_path,
                      "#{@commitment_adjustment.fund.name}": fund_path(@commitment_adjustment.fund),
                      "#{@commitment_adjustment.capital_commitment}": capital_commitment_path(@commitment_adjustment.capital_commitment), "#{@commitment_adjustment.adjustment_type}": nil }
  end

  # Only allow a list of trusted parameters through.
  def commitment_adjustment_params
    params.require(:commitment_adjustment).permit(:entity_id, :fund_id, :capital_commitment_id, :adjustment_type, :pre_adjustment, :folio_amount, :post_adjustment, :reason, :as_of, :folio_amount, :owner_id, :owner_type)
  end
end
