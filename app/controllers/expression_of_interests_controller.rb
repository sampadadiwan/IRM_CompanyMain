class ExpressionOfInterestsController < ApplicationController
  before_action :set_expression_of_interest, only: %i[show edit update destroy approve]

  # GET /expression_of_interests or /expression_of_interests.json
  def index
    @expression_of_interests = policy_scope(ExpressionOfInterest)
    @expression_of_interests = @expression_of_interests.where(investment_opportunity_id: params[:investment_opportunity_id]) if params[:investment_opportunity_id].present?
  end

  # GET /expression_of_interests/1 or /expression_of_interests/1.json
  def show; end

  # GET /expression_of_interests/new
  def new
    @expression_of_interest = ExpressionOfInterest.new(expression_of_interest_params)
    @expression_of_interest.eoi_entity_id = current_user.entity_id
    authorize @expression_of_interest
  end

  # GET /expression_of_interests/1/edit
  def edit; end

  # POST /expression_of_interests or /expression_of_interests.json
  def create
    @expression_of_interest = ExpressionOfInterest.new(expression_of_interest_params)
    @expression_of_interest.eoi_entity_id = current_user.entity_id
    @expression_of_interest.entity_id = @expression_of_interest.investment_opportunity.entity_id
    @expression_of_interest.user_id = current_user.id

    authorize @expression_of_interest

    respond_to do |format|
      if @expression_of_interest.save
        format.html { redirect_to expression_of_interest_url(@expression_of_interest), notice: "Expression of interest was successfully created." }
        format.json { render :show, status: :created, location: @expression_of_interest }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @expression_of_interest.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /expression_of_interests/1 or /expression_of_interests/1.json
  def update
    respond_to do |format|
      if @expression_of_interest.update(expression_of_interest_params)
        format.html { redirect_to expression_of_interest_url(@expression_of_interest), notice: "Expression of interest was successfully updated." }
        format.json { render :show, status: :ok, location: @expression_of_interest }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @expression_of_interest.errors, status: :unprocessable_entity }
      end
    end
  end

  def approve
    @expression_of_interest.approved = !@expression_of_interest.approved
    @expression_of_interest.save
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(@expression_of_interest)
        ]
      end
      format.html { redirect_to expression_of_interest_url(@expression_of_interest), notice: "EOI was successfully approved." }
      format.json { @expression_of_interest.to_json }
    end
  end

  # DELETE /expression_of_interests/1 or /expression_of_interests/1.json
  def destroy
    @expression_of_interest.destroy

    respond_to do |format|
      format.html { redirect_to expression_of_interests_url, notice: "Expression of interest was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_expression_of_interest
    @expression_of_interest = ExpressionOfInterest.find(params[:id])
    authorize @expression_of_interest
  end

  # Only allow a list of trusted parameters through.
  def expression_of_interest_params
    params.require(:expression_of_interest).permit(:entity_id, :user_id, :eoi_entity_id, :investment_opportunity_id, :amount, :approved, :verified, :allocation_percentage, :allocation_amount)
  end
end
