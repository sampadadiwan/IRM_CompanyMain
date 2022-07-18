class ApprovalResponsesController < ApplicationController
  before_action :set_approval_response, only: %i[show edit update destroy]

  # GET /approval_responses or /approval_responses.json
  def index
    @approval_responses = policy_scope(ApprovalResponse)
  end

  # GET /approval_responses/1 or /approval_responses/1.json
  def show; end

  # GET /approval_responses/new
  def new
    @approval_response = ApprovalResponse.new(approval_response_params)
    @approval_response.response_entity_id = current_user.entity_id
    @approval_response.response_user_id = current_user.id
    @approval_response.entity_id = @approval_response.approval.entity_id
    authorize @approval_response
  end

  # GET /approval_responses/1/edit
  def edit; end

  # POST /approval_responses or /approval_responses.json
  def create
    @approval_response = ApprovalResponse.new(approval_response_params)
    @approval_response.response_entity_id = current_user.entity_id
    @approval_response.response_user_id = current_user.id
    @approval_response.entity_id = @approval_response.approval.entity_id
    authorize @approval_response

    respond_to do |format|
      if @approval_response.save
        format.html { redirect_to approval_response_url(@approval_response), notice: "Approval response was successfully created." }
        format.json { render :show, status: :created, location: @approval_response }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @approval_response.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /approval_responses/1 or /approval_responses/1.json
  def update
    respond_to do |format|
      if @approval_response.update(approval_response_params)
        format.html { redirect_to approval_response_url(@approval_response), notice: "Approval response was successfully updated." }
        format.json { render :show, status: :ok, location: @approval_response }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @approval_response.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /approval_responses/1 or /approval_responses/1.json
  def destroy
    @approval_response.destroy

    respond_to do |format|
      format.html { redirect_to approval_responses_url, notice: "Approval response was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_approval_response
    @approval_response = ApprovalResponse.find(params[:id])
    authorize @approval_response
  end

  # Only allow a list of trusted parameters through.
  def approval_response_params
    params.require(:approval_response).permit(:entity_id, :approval_id, :status, :details)
  end
end
