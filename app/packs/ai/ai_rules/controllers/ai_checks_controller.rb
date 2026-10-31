class AiChecksController < ApplicationController
  # L14 — the classes AI checks run on: AiRule::FOR_CLASSES, plus InvestorKyc, the base class the KYC
  # checks are stored under (production parents: Fund, InvestorKyc; owners: InvestorKyc, PortfolioInvestment)
  CHECKABLE_TYPES = (AiRule::FOR_CLASSES + %w[InvestorKyc]).uniq.freeze

  before_action :set_ai_check, only: %i[show edit update destroy]

  # GET /ai_checks
  def index
    @q = AiCheck.ransack(params[:q])

    @ai_checks = policy_scope(@q.result)
    @ai_checks = @ai_checks.where(parent_id: params[:parent_id]) if params[:parent_id].present?
    @ai_checks = @ai_checks.where(parent_type: params[:parent_type]) if params[:parent_type].present?
    @ai_checks = @ai_checks.where(owner_id: params[:owner_id]) if params[:owner_id].present?
    @ai_checks = @ai_checks.where(owner_type: params[:owner_type]) if params[:owner_type].present?
    @ai_checks = @ai_checks.where(status: params[:status]) if params[:status].present?
    @ai_checks = @ai_checks.where(rule_type: params[:rule_type]) if params[:rule_type].present?

    @ai_checks = if params[:checklist].present?
                   @ai_checks.includes(:ai_rule)
                 else
                   @ai_checks.includes(:ai_rule, :parent, :owner)
                 end

    @pagy, @ai_checks = pagy(@ai_checks) unless params[:format] == "xlsx"
  end

  def run_checks
    # Get the model to run the checks on

    if params[:parent_id].present?
      # L14 — only a class AI rules run on (CHECKABLE_TYPES); an unknown name is a 404 (L14-12)
      parent_class = ApplicationRecord.model_class_from_param(params[:parent_type], allowed: CHECKABLE_TYPES)
      raise ActiveRecord::RecordNotFound, "Unknown parent type" unless parent_class

      @parent = parent_class.find(params[:parent_id])
      authorize(@parent, :run_checks?)
      params[:for_classes]&.split(",") || AiRule::FOR_CLASSES
    end

    if params[:owner_id].present?
      # L14 — same list for the owner (L14-12)
      owner_class = ApplicationRecord.model_class_from_param(params[:owner_type], allowed: CHECKABLE_TYPES)
      raise ActiveRecord::RecordNotFound, "Unknown owner type" unless owner_class

      @owner = owner_class.find(params[:owner_id])
      authorize(@owner, :run_checks?)
    end

    schedule = params[:schedule]
    rule_type = params[:rule_type]
    for_classes = params[:for_classes].presence || AiRule::FOR_CLASSES

    if request.post?
      # Run the compliance checks
      if params[:parent_id].present?
        AiFundChecksJob.perform_later(params[:parent_type], params[:parent_id], current_user.id, for_classes, rule_type, schedule)
        redirect_to @parent, notice: "Compliance checks are being run in the background. Please check in a few mins"
      elsif params[:owner_id].present?
        AiChecksJob.perform_later(params[:owner_type], params[:owner_id], current_user.id, rule_type, schedule)
        redirect_to @owner, notice: "Compliance checks are being run in the background. Please check in a few mins"
      end
    else
      render :run_checks
    end
  end

  # GET /ai_checks/1
  def show; end

  # GET /ai_checks/new
  def new
    @ai_check = AiCheck.new
    authorize @ai_check
  end

  # GET /ai_checks/1/edit
  def edit; end

  # POST /ai_checks
  def create
    @ai_check = AiCheck.new(ai_check_params)
    authorize @ai_check
    if @ai_check.save
      redirect_to @ai_check, notice: "Compliance check was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /ai_checks/1
  def update
    if @ai_check.update(ai_check_params)
      redirect_to @ai_check, notice: "Compliance check was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /ai_checks/1
  def destroy
    @ai_check.destroy!
    redirect_to ai_checks_url, notice: "Compliance check was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_ai_check
    @ai_check = AiCheck.find(params[:id])
    authorize @ai_check
  end

  # Only allow a list of trusted parameters through.
  def ai_check_params
    params.require(:ai_check).permit(:entity_id, :parent_id, :parent_type, :owner_id, :owner_type, :status, :explanation)
  end
end
