class ExpressionOfInterestsController < ApplicationController
  before_action :set_expression_of_interest, only: %i[show edit update destroy approve allocation_form allocate generate_documentation]

  # GET /expression_of_interests or /expression_of_interests.json
  def index
    @expression_of_interests = policy_scope(ExpressionOfInterest).includes(:investor, user: [:roles])
    @expression_of_interests = @expression_of_interests.where(investment_opportunity_id: params[:investment_opportunity_id]) if params[:investment_opportunity_id].present?
  end

  # GET /expression_of_interests/1 or /expression_of_interests/1.json
  def show; end

  # GET /expression_of_interests/new
  def new
    @expression_of_interest = ExpressionOfInterest.new(expression_of_interest_params)
    @expression_of_interest.entity_id = @expression_of_interest.investment_opportunity.entity_id
    if current_user.entity_id != @expression_of_interest.entity_id
      @expression_of_interest.eoi_entity_id = @expression_of_interest.investment_opportunity.entity_id
      @expression_of_interest.investor = @expression_of_interest.entity.investors.where(investor_entity_id: current_user.entity_id).first
    end
    @expression_of_interest.amount = @expression_of_interest.investment_opportunity.min_ticket_size
    authorize @expression_of_interest
  end

  # GET /expression_of_interests/1/edit
  def edit; end

  # POST /expression_of_interests or /expression_of_interests.json
  def create
    @expression_of_interest = ExpressionOfInterest.new(expression_of_interest_params)
    @expression_of_interest.eoi_entity_id = @expression_of_interest.investor&.investor_entity_id
    @expression_of_interest.entity_id = @expression_of_interest.investment_opportunity.entity_id
    @expression_of_interest.user_id = current_user.id

    authorize @expression_of_interest

    result = EoiCreate.wtf?(expression_of_interest: @expression_of_interest)
    respond_to do |format|
      if result.success?
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

  def generate_documentation
    EoiDocJob.perform_later(@expression_of_interest.id, current_user.id)
    redirect_to expression_of_interest_url(@expression_of_interest), notice: "Documentation generation started, please check back in a few mins."
  end

  def approve
    if !@expression_of_interest.approved
      result = EoiApprove.wtf?(expression_of_interest: @expression_of_interest)
    else
      result = EoiUnapprove.wtf?(expression_of_interest: @expression_of_interest)
    end

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

  def allocation_form; end

  def allocate
    @expression_of_interest.allocation_amount = expression_of_interest_params[:allocation_amount]
    @expression_of_interest.comment = expression_of_interest_params[:comment]
    @expression_of_interest.verified = expression_of_interest_params[:verified]
    @expression_of_interest.approved = expression_of_interest_params[:approved]

    respond_to do |format|
      if @expression_of_interest.save
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("tf_expression_of_interest_#{@expression_of_interest.id}", partial: "expression_of_interests/final_expression_of_interest", locals: { expression_of_interest: @expression_of_interest })
          ]
        end
        format.html { redirect_to expression_of_interest_url(@expression_of_interest), notice: "EOI was successfully updated." }
        format.json { render :show, status: :ok, location: @expression_of_interest }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @expression_of_interest.errors, status: :unprocessable_entity }
      end
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
    params.require(:expression_of_interest).permit(:entity_id, :user_id, :eoi_entity_id, :investor_name, :investor_id, :investor_kyc_id, :investment_opportunity_id, :amount, :approved, :verified, :investor_email, :allocation_percentage, :comment, :investor_signatory_id, :allocation_amount, :details, documents_attributes: Document::NESTED_ATTRIBUTES)
  end
end
