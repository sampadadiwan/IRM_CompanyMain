class ApprovalsController < ApplicationController
  before_action :set_approval, only: %i[show edit update destroy approve send_reminder]
  after_action :verify_policy_scoped, only: %i[]

  # GET /approvals or /approvals.json
  def index
    authorize Approval
    @approvals = if %w[employee].index(current_user.curr_role)
                   policy_scope(Approval)
                 else
                   Approval.for_investor(current_user)
                 end

    @approvals = @approvals.where(entity_id: params[:entity_id]) if params[:entity_id].present?
    @approvals = @approvals.includes(:entity)
  end

  # GET /approvals/1 or /approvals/1.json
  def show; end

  # GET /approvals/new
  def new
    @approval = Approval.new
    @approval.entity_id = current_user.entity_id
    @approval.due_date = Time.zone.today + 7.days
    @approval.default_response_status
    authorize @approval
    setup_custom_fields(@approval)
  end

  # GET /approvals/1/edit
  def edit
    setup_custom_fields(@approval)
  end

  # POST /approvals or /approvals.json
  def create
    @approval = Approval.new(approval_params)
    authorize @approval
    respond_to do |format|
      if @approval.save
        format.html { redirect_to approval_url(@approval), notice: "Approval was successfully created." }
        format.json { render :show, status: :created, location: @approval }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @approval.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /approvals/1 or /approvals/1.json
  def update
    respond_to do |format|
      if @approval.update(approval_params)
        format.html { redirect_to approval_url(@approval), notice: "Approval was successfully updated." }
        format.json { render :show, status: :ok, location: @approval }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @approval.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /approvals/1 or /approvals/1.json
  def destroy
    @approval.destroy

    respond_to do |format|
      format.html { redirect_to approvals_url, notice: "Approval was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def approve
    @approval.approved = true
    @approval.save
    respond_to do |format|
      format.html { redirect_to approval_url(@approval), notice: "Successfully approved." }
      format.json { head :no_content }
    end
  end

  def send_reminder
    # Mark all pending responses as not notified
    @approval.approval_responses.pending.update_all(notification_sent: false)
    # Send notification out
    @approval.reload.send_notification
    respond_to do |format|
      format.html { redirect_to approval_url(@approval), notice: "Successfully sent reminder." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_approval
    @approval = Approval.find(params[:id])
    authorize @approval
  end

  # Only allow a list of trusted parameters through.
  def approval_params
    params.require(:approval).permit(:title, :agreements_reference, :entity_id, :approved_count, :response_status,
                                     :approved, :due_date, :rejected_count, :form_type_id, properties: {})
  end
end
