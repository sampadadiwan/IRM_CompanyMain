class SupportClientMappingsController < ApplicationController
  before_action :set_support_client_mapping, only: %i[show edit update destroy]

  # GET /support_client_mappings or /support_client_mappings.json
  def index
    authorize SupportClientMapping
    @support_client_mappings = policy_scope(SupportClientMapping)
  end

  # GET /support_client_mappings/1 or /support_client_mappings/1.json
  def show; end

  # GET /support_client_mappings/new
  def new
    @support_client_mapping = SupportClientMapping.new
    @support_client_mapping.end_date = Time.zone.today + 1.week
    @support_client_mapping.enabled = true
    @support_client_mapping.entity_id = params[:entity_id]
    authorize @support_client_mapping
  end

  # GET /support_client_mappings/1/edit
  def edit; end

  # POST /support_client_mappings or /support_client_mappings.json
  def create
    @support_client_mapping = SupportClientMapping.new(support_client_mapping_params)
    authorize @support_client_mapping
    respond_to do |format|
      if @support_client_mapping.save
        format.html { redirect_to support_client_mapping_url(@support_client_mapping), notice: "Support client mapping was successfully created." }
        format.json { render :show, status: :created, location: @support_client_mapping }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @support_client_mapping.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /support_client_mappings/1 or /support_client_mappings/1.json
  def update
    respond_to do |format|
      if @support_client_mapping.update(support_client_mapping_params)
        format.html { redirect_to support_client_mapping_url(@support_client_mapping), notice: "Support client mapping was successfully updated." }
        format.json { render :show, status: :ok, location: @support_client_mapping }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @support_client_mapping.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /support_client_mappings/1 or /support_client_mappings/1.json
  def destroy
    @support_client_mapping.destroy!

    respond_to do |format|
      format.html { redirect_to support_client_mappings_url, notice: "Support client mapping was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_support_client_mapping
    @support_client_mapping = SupportClientMapping.find(params[:id])
    authorize @support_client_mapping
  end

  # Only allow a list of trusted parameters through.
  def support_client_mapping_params
    params.require(:support_client_mapping).permit(:user_id, :entity_id, :end_date, :enabled)
  end
end
