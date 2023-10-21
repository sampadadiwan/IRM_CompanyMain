class KpiReportsController < ApplicationController
  before_action :set_kpi_report, only: %i[show edit update destroy]

  # GET /kpi_reports or /kpi_reports.json
  def index
    @kpi_reports = policy_scope(KpiReport).includes(:kpis, :documents)
    authorize(KpiReport)

    if params[:period].present?
      date = Time.zone.today - params[:period].to_i.months
      @kpi_reports = @kpi_reports.where(as_of: date..)
    end

    @kpi_reports = @kpi_reports.where(entity_id: params[:entity_id]) if params[:entity_id].present?

    respond_to do |format|
      format.html { render :index }
      format.json { render json: KpiReportDatatable.new(params, kpi_reports: @kpi_reports) }
    end
  end

  # GET /kpi_reports/1 or /kpi_reports/1.json
  def show; end

  # GET /kpi_reports/new
  def new
    @kpi_report = KpiReport.new(kpi_report_params)
    @kpi_report.entity_id = current_user.entity_id
    @kpi_report.user_id = current_user.id
    @kpi_report.as_of = Time.zone.today
    authorize @kpi_report
    setup_custom_fields(@kpi_report)
    @kpi_report.custom_kpis
  end

  # GET /kpi_reports/1/edit
  def edit
    setup_custom_fields(@kpi_report)
    @kpi_report.custom_kpis
  end

  # POST /kpi_reports or /kpi_reports.json
  def create
    @kpi_report = KpiReport.new(kpi_report_params)
    authorize @kpi_report

    respond_to do |format|
      if @kpi_report.save
        format.html { redirect_to kpi_report_url(@kpi_report), notice: "Kpi report was successfully created." }
        format.json { render :show, status: :created, location: @kpi_report }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @kpi_report.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /kpi_reports/1 or /kpi_reports/1.json
  def update
    respond_to do |format|
      if @kpi_report.update(kpi_report_params)
        format.html { redirect_to kpi_report_url(@kpi_report), notice: "Kpi report was successfully updated." }
        format.json { render :show, status: :ok, location: @kpi_report }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @kpi_report.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /kpi_reports/1 or /kpi_reports/1.json
  def destroy
    @kpi_report.destroy

    respond_to do |format|
      format.html { redirect_to kpi_reports_url, notice: "Kpi report was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_kpi_report
    @kpi_report = KpiReport.find(params[:id])
    authorize @kpi_report
    @bread_crumbs = { Kpis: kpi_reports_path, "#{@kpi_report.as_of}": kpi_report_path(@kpi_report) }
  end

  # Only allow a list of trusted parameters through.
  def kpi_report_params
    params.require(:kpi_report).permit(:entity_id, :as_of, :notes, :user_id, :form_type_id, properties: {}, kpis_attributes: %i[id entity_id name value display_value notes _destroy])
  end
end
