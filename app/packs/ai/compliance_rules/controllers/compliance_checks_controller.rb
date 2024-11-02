class ComplianceChecksController < ApplicationController
  before_action :set_compliance_check, only: %i[show edit update destroy]

  # GET /compliance_checks
  def index
    @q = ComplianceCheck.ransack(params[:q])
    @compliance_checks = policy_scope(@q.result).includes(:compliance_rule, :parent, :owner).page(params[:page])
    @compliance_checks = @compliance_checks.where(parent_id: params[:parent_id]) if params[:parent_id].present?
    @compliance_checks = @compliance_checks.where(parent_type: params[:parent_type]) if params[:parent_type].present?
    @compliance_checks = @compliance_checks.where(owner_id: params[:owner_id]) if params[:owner_id].present?
    @compliance_checks = @compliance_checks.where(owner_type: params[:owner_type]) if params[:owner_type].present?
    @compliance_checks = @compliance_checks.where(status: params[:status]) if params[:status].present?

    @compliance_checks = @compliance_checks.page(params[:page]) unless params[:format] == "xlsx"
  end

  def run_checks
    # Get the model to run the checks on
    model = params[:owner_type].constantize.find(params[:owner_id])
    authorize(model, :run_checks?)
    # Run the compliance checks
    RecordComplianceJob.perform_later(params[:owner_type], params[:owner_id], current_user.id)
    redirect_to model, notice: "Compliance checks are being run in the background. Please check in a few mins"
  end

  # GET /compliance_checks/1
  def show; end

  # GET /compliance_checks/new
  def new
    @compliance_check = ComplianceCheck.new
    authorize @compliance_check
  end

  # GET /compliance_checks/1/edit
  def edit; end

  # POST /compliance_checks
  def create
    @compliance_check = ComplianceCheck.new(compliance_check_params)
    authorize @compliance_check
    if @compliance_check.save
      redirect_to @compliance_check, notice: "Compliance check was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /compliance_checks/1
  def update
    if @compliance_check.update(compliance_check_params)
      redirect_to @compliance_check, notice: "Compliance check was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /compliance_checks/1
  def destroy
    @compliance_check.destroy!
    redirect_to compliance_checks_url, notice: "Compliance check was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_compliance_check
    @compliance_check = ComplianceCheck.find(params[:id])
    authorize @compliance_check
  end

  # Only allow a list of trusted parameters through.
  def compliance_check_params
    params.require(:compliance_check).permit(:entity_id, :parent_id, :parent_type, :owner_id, :owner_type, :status, :explanation)
  end
end
