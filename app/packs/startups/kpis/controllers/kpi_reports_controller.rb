class KpiReportsController < ApplicationController
  before_action :set_kpi_report, only: %i[show edit update destroy recompute_percentage_change analyze]

  # GET /kpi_reports or /kpi_reports.json
  def index
    @q = KpiReport.ransack(params[:q])
    @kpi_reports = policy_scope(@q.result)
    authorize(KpiReport)

    @kpi_reports = if params[:grid_view].present?
                     @kpi_reports.includes(:kpis, :documents, :entity, :portfolio_company, :owner)
                   else
                     @kpi_reports.includes(:kpis, :documents, :entity, :user, :portfolio_company)
                   end

    if params[:months].present?
      date = Time.zone.today - params[:months].to_i.months
      @kpi_reports = @kpi_reports.where(as_of: date..)
    end

    if params[:entity_id].present?
      @kpi_reports = @kpi_reports.where(entity_id: params[:entity_id])
      @portfolio_company = current_user.entity.investors.where(investor_entity_id: params[:entity_id]).last if current_user.curr_role == "investor"
    end
    @kpi_reports = @kpi_reports.where(period: params[:period]) if params[:period].present?
    @kpi_reports = @kpi_reports.where(tag_list: params[:tag_list]) if params[:tag_list].present?
    @kpi_reports = @kpi_reports.where(owner_type: params[:owner_type]) if params[:owner_type].present?

    if params[:portfolio_company_id].present?
      @portfolio_company = Investor.find(params[:portfolio_company_id])
      # Now either the portfolio_company has uploaded and given access to the kpi_reports
      # Or the fund company has uploaded the kpi_reports for the portfolio_company
      @kpi_reports = @kpi_reports.where("portfolio_company_id=? or entity_id=?", @portfolio_company.id, @portfolio_company.investor_entity_id)
    end

    respond_to do |format|
      format.html { render :index }
      format.xlsx { render :index }
      format.json { render json: KpiReportDatatable.new(params, kpi_reports: @kpi_reports) }
    end
  end

  # GET /kpi_reports/1 or /kpi_reports/1.json
  def show; end

  def analyze
    @prev_kpi_report = KpiReport.where(entity_id: @kpi_report.entity_id, as_of: ..@kpi_report.as_of - 1.day).order(as_of: :asc).last
    KpiAnalystJob.perform_later(@kpi_report.id, @prev_kpi_report&.id, current_user.id)
    redirect_to kpi_report_url(@kpi_report), notice: "Analysis started."
  end

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
    setup_doc_user(@kpi_report)

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
    setup_doc_user(@kpi_report)
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

  def recompute_percentage_change
    KpiPercentageChangeJob.perform_later(@kpi_report.entity_id, current_user.id)
    redirect_to request.referer || kpi_report_url(@kpi_report), notice: "Computation started."
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
    params.require(:kpi_report).permit(:portfolio_company_id, :entity_id, :as_of, :tag_list, :notes, :user_id, :form_type_id, :period, properties: {}, kpis_attributes: %i[id entity_id name period value display_value notes _destroy], documents_attributes: Document::NESTED_ATTRIBUTES)
  end
end
