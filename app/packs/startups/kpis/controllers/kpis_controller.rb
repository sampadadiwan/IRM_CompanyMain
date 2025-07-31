class KpisController < ApplicationController
  before_action :set_kpi, only: %i[show edit update destroy]

  # GET /kpis or /kpis.json
  def index
    @q = Kpi.ransack(params[:q])
    @kpis = policy_scope(@q.result).includes(kpi_report: :portfolio_company)
    @kpis = @kpis.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
    authorize(Kpi)
  end

  # GET /kpis/1 or /kpis/1.json
  def show; end

  # GET /kpis/new
  def new
    @kpi = Kpi.new(kpi_params)
    @kpi.entity_id = current_user.entity_id
    authorize @kpi
    setup_custom_fields(@kpi)
  end

  # GET /kpis/1/edit
  def edit
    setup_custom_fields(@kpi)
  end

  # POST /kpis or /kpis.json
  def create
    @kpi = Kpi.new(kpi_params)
    authorize @kpi
    respond_to do |format|
      if @kpi.save
        format.html { redirect_to kpi_url(@kpi), notice: "Kpi was successfully created." }
        format.json { render :show, status: :created, location: @kpi }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @kpi.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /kpis/1 or /kpis/1.json
  def update
    respond_to do |format|
      if @kpi.update(kpi_params)
        format.html { redirect_to kpi_url(@kpi), notice: "Kpi was successfully updated." }
        format.json { render :show, status: :ok, location: @kpi }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @kpi.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /kpis/1 or /kpis/1.json
  def destroy
    @kpi.destroy

    respond_to do |format|
      format.html { redirect_to kpis_url, notice: "Kpi was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_kpi
    @kpi = Kpi.find(params[:id])
    authorize @kpi
  end

  # Only allow a list of trusted parameters through.
  def kpi_params
    params.require(:kpi).permit(:entity_id, :name, :value, :display_value, :notes, :kpi_report_id, :form_type_id, properties: {})
  end
end
