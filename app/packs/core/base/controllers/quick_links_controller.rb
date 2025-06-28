class QuickLinksController < ApplicationController
  before_action :set_quick_link, only: %i[show edit update destroy]

  # GET /quick_links or /quick_links.json
  def index
    @quick_links = policy_scope(QuickLink)
    @quick_links = @quick_links.where(tags: params[:tags]) if params[:tags].present?
    @quick_links = @quick_links.where(entity_id: params[:entity_id]) if params[:entity_id].present?
    @quick_links = @quick_links.where("name ILIKE ?", "%#{params[:search]}%") if params[:search].present?
    @pagy, @quick_links = pagy(@quick_links.order(entity_id: :desc))
  end

  # GET /quick_links/1 or /quick_links/1.json
  def show; end

  # GET /quick_links/new
  def new
    @quick_link = QuickLink.new
    @quick_link.entity_id ||= current_user.entity_id unless current_user.has_cached_role?(:super)
    authorize @quick_link
  end

  # GET /quick_links/1/edit
  def edit; end

  # POST /quick_links or /quick_links.json
  def create
    @quick_link = QuickLink.new(quick_link_params)
    @quick_link.entity_id ||= current_user.entity_id unless current_user.has_cached_role?(:super)
    authorize @quick_link
    respond_to do |format|
      if @quick_link.save
        format.html { redirect_to quick_link_url(@quick_link), notice: "Quick link was successfully created." }
        format.json { render :show, status: :created, location: @quick_link }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @quick_link.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /quick_links/1 or /quick_links/1.json
  def update
    respond_to do |format|
      if @quick_link.update(quick_link_params)
        format.html { redirect_to quick_link_url(@quick_link), notice: "Quick link was successfully updated." }
        format.json { render :show, status: :ok, location: @quick_link }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @quick_link.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /quick_links/1 or /quick_links/1.json
  def destroy
    @quick_link.destroy!

    respond_to do |format|
      format.html { redirect_to quick_links_url, notice: "Quick link was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_quick_link
    @quick_link = QuickLink.find(params[:id])
    authorize @quick_link
  end

  # Only allow a list of trusted parameters through.
  def quick_link_params
    params.require(:quick_link).permit(:name, :description, :tags, :entity_id, quick_link_steps_attributes: %i[id name description link position _destroy])
  end
end
