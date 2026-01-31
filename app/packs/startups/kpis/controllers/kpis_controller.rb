class KpisController < ApplicationController
  before_action :set_kpi, only: %i[show edit update destroy approve]

  # GET /kpis or /kpis.json
  def index
    authorize(Kpi)
    service = KpiList.call(current_user, params) { |relation| policy_scope(relation) }
    @q = service.q
    @kpis = service.kpis
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

  def approve
    @kpi = KpiApproveService.call(@kpi.id, current_user.id)
    respond_to do |format|
      format.html { redirect_back_or_to(kpi_reports_path, notice: "KPI was successfully approved.") }
      format.json { render :show, status: :ok, location: @kpi }
    end
  end

  def approve_all
    portfolio_company_id = params[:portfolio_company_id]
    entity_id = params[:entity_id] || current_user.entity_id

    unapproved_kpis = Kpi.unapproved.where(portfolio_company_id: portfolio_company_id, entity_id: entity_id)

    unapproved_kpis.find_each do |kpi|
      authorize kpi, :approve?
      KpiApproveService.call(kpi.id, current_user.id)
    end

    respond_to do |format|
      format.html { redirect_back_or_to(kpi_reports_path, notice: "All pending KPIs were successfully approved.") }
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
