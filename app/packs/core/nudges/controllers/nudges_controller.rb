class NudgesController < ApplicationController
  before_action :set_nudge, only: %i[show edit update destroy]

  # GET /nudges or /nudges.json
  def index
    @nudges = policy_scope(Nudge).order("id desc").limit(50)
  end

  # GET /nudges/1 or /nudges/1.json
  def show; end

  # GET /nudges/new
  def new
    @nudge = Nudge.new(nudge_params)
    @nudge.user_id = current_user.id
    @nudge.entity_id = current_user.entity_id
    @nudge.pre_populate
    authorize @nudge
  end

  # GET /nudges/1/edit
  def edit; end

  # POST /nudges or /nudges.json
  def create
    @nudge = Nudge.new(nudge_params)
    @nudge.user_id = current_user.id
    @nudge.entity_id = current_user.entity_id

    authorize @nudge

    respond_to do |format|
      if @nudge.save
        redirect_url = params[:back_to].presence || nudge_url(@nudge)

        format.html { redirect_to redirect_url, notice: "Nudge was successfully created." }
        format.json { render :show, status: :created, location: @nudge }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @nudge.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /nudges/1 or /nudges/1.json
  def update
    respond_to do |format|
      if @nudge.update(nudge_params)
        redirect_url = params[:back_to].presence || nudge_url(@nudge)
        format.html { redirect_to redirect_url, notice: "Nudge was successfully updated." }
        format.json { render :show, status: :ok, location: @nudge }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @nudge.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /nudges/1 or /nudges/1.json
  def destroy
    @nudge.destroy

    respond_to do |format|
      format.html { redirect_to nudges_url, notice: "Nudge was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_nudge
    @nudge = Nudge.find(params[:id])
    authorize @nudge
  end

  # Only allow a list of trusted parameters through.
  def nudge_params
    params.require(:nudge).permit(:to, :cc, :bcc, :subject, :msg_body,
                                  :user_id, :entity_id, :item_id, :item_type)
  end
end
