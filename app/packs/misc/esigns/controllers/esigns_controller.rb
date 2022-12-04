class EsignsController < ApplicationController
  before_action :set_esign, only: %i[show edit update destroy]

  # GET /esigns or /esigns.json
  def index
    @esigns = policy_scope(Esign)
    @esigns = @esigns.where(owner_id: params[:owner_id]) if params[:owner_id].present?
    @esigns = @esigns.where(owner_type: params[:owner_type]) if params[:owner_type].present?
  end

  # GET /esigns/1 or /esigns/1.json
  def show; end

  # GET /esigns/new
  def new
    @esign = Esign.new(esign_params)
    authorize @esign
  end

  # GET /esigns/1/edit
  def edit; end

  # POST /esigns or /esigns.json
  def create
    @esign = Esign.new(esign_params)
    authorize @esign
    respond_to do |format|
      if @esign.save
        format.html { redirect_to esign_url(@esign), notice: "Esign was successfully created." }
        format.json { render :show, status: :created, location: @esign }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @esign.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /esigns/1 or /esigns/1.json
  def update
    respond_to do |format|
      if @esign.update(esign_params)
        format.html { redirect_to esign_url(@esign), notice: "Esign was successfully updated." }
        format.json { render :show, status: :ok, location: @esign }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @esign.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /esigns/1 or /esigns/1.json
  def destroy
    @esign.destroy

    respond_to do |format|
      format.html { redirect_to esigns_url, notice: "Esign was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_esign
    @esign = Esign.find(params[:id])
    authorize @esign
  end

  # Only allow a list of trusted parameters through.
  def esign_params
    params.require(:esign).permit(:entity_id, :user_id, :owner_id, :owner_type, :sequence_no, :link, :reason, :status, :completed)
  end
end
