class SignatureWorkflowsController < ApplicationController
  before_action :set_signature_workflow, only: %i[show edit update destroy]

  # GET /signature_workflows or /signature_workflows.json
  def index
    @signature_workflows = policy_scope(SignatureWorkflow)
  end

  # GET /signature_workflows/1 or /signature_workflows/1.json
  def show; end

  # GET /signature_workflows/new
  def new
    @signature_workflow = SignatureWorkflow.new(signature_workflow_params)
    authorize(@signature_workflow)
  end

  # GET /signature_workflows/1/edit
  def edit; end

  # POST /signature_workflows or /signature_workflows.json
  def create
    @signature_workflow = SignatureWorkflow.new(signature_workflow_params)
    authorize(@signature_workflow)
    respond_to do |format|
      if @signature_workflow.save
        format.html { redirect_to signature_workflow_url(@signature_workflow), notice: "Signature workflow was successfully created." }
        format.json { render :show, status: :created, location: @signature_workflow }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @signature_workflow.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /signature_workflows/1 or /signature_workflows/1.json
  def update
    respond_to do |format|
      if @signature_workflow.update(signature_workflow_params)
        format.html { redirect_to signature_workflow_url(@signature_workflow), notice: "Signature workflow was successfully updated." }
        format.json { render :show, status: :ok, location: @signature_workflow }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @signature_workflow.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /signature_workflows/1 or /signature_workflows/1.json
  def destroy
    @signature_workflow.destroy

    respond_to do |format|
      format.html { redirect_to signature_workflows_url, notice: "Signature workflow was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_signature_workflow
    @signature_workflow = SignatureWorkflow.find(params[:id])
    authorize(@signature_workflow)
  end

  # Only allow a list of trusted parameters through.
  def signature_workflow_params
    params.require(:signature_workflow).permit(:owner_id, :owner_type, :entity_id, :signatory_ids, :completed_ids, :sequential)
  end
end
