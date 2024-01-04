class QuickLinkStepsController < ApplicationController
  before_action :set_quick_link_step, only: %i[show edit update destroy]

  # GET /quick_link_steps or /quick_link_steps.json
  def index
    @quick_link_steps = policy_scope(QuickLinkStep)
  end

  # GET /quick_link_steps/1 or /quick_link_steps/1.json
  def show; end

  # GET /quick_link_steps/new
  def new
    @quick_link_step = QuickLinkStep.new
    authorize @quick_link_step
  end

  # GET /quick_link_steps/1/edit
  def edit; end

  # POST /quick_link_steps or /quick_link_steps.json
  def create
    @quick_link_step = QuickLinkStep.new(quick_link_step_params)
    authorize @quick_link_step
    respond_to do |format|
      if @quick_link_step.save
        format.html { redirect_to quick_link_step_url(@quick_link_step), notice: "Quick link step was successfully created." }
        format.json { render :show, status: :created, location: @quick_link_step }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @quick_link_step.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /quick_link_steps/1 or /quick_link_steps/1.json
  def update
    respond_to do |format|
      if @quick_link_step.update(quick_link_step_params)
        format.html { redirect_to quick_link_step_url(@quick_link_step), notice: "Quick link step was successfully updated." }
        format.json { render :show, status: :ok, location: @quick_link_step }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @quick_link_step.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /quick_link_steps/1 or /quick_link_steps/1.json
  def destroy
    @quick_link_step.destroy!

    respond_to do |format|
      format.html { redirect_to quick_link_steps_url, notice: "Quick link step was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_quick_link_step
    @quick_link_step = QuickLinkStep.find(params[:id])
    authorize @quick_link_step
  end

  # Only allow a list of trusted parameters through.
  def quick_link_step_params
    params.require(:quick_link_step).permit(:name, :link, :description, :entity_id, :quick_link_id)
  end
end
