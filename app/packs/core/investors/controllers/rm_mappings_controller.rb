class RmMappingsController < ApplicationController
  before_action :set_rm_mapping, only: %i[show edit update destroy]

  # GET /rm_mappings
  def index
    @q = RmMapping.ransack(params[:q])
    @rm_mappings = policy_scope(@q.result)
  end

  # GET /rm_mappings/1
  def show; end

  # GET /rm_mappings/new
  def new
    @rm_mapping = RmMapping.new
    @rm_mapping.entity_id = current_user.entity_id
    authorize @rm_mapping
  end

  # GET /rm_mappings/1/edit
  def edit; end

  # POST /rm_mappings
  def create
    @rm_mapping = RmMapping.new(rm_mapping_params)
    @rm_mapping.entity_id = current_user.entity_id
    authorize @rm_mapping
    if @rm_mapping.save
      redirect_to @rm_mapping, notice: "Rm mapping was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /rm_mappings/1
  def update
    if @rm_mapping.update(rm_mapping_params)
      redirect_to @rm_mapping, notice: "Rm mapping was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /rm_mappings/1
  def destroy
    @rm_mapping.destroy!
    redirect_to rm_mappings_url, notice: "Rm mapping was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_rm_mapping
    @rm_mapping = RmMapping.find(params[:id])
    authorize @rm_mapping
  end

  # Only allow a list of trusted parameters through.
  def rm_mapping_params
    params.require(:rm_mapping).permit(:rm_id, :investor_id, :entity_id, :approved, permissions: [])
  end
end
