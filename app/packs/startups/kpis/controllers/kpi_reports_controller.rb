class KpiReportsController < ApplicationController
  before_action :set_kpi_report, only: %i[show edit update destroy recompute_percentage_change recompute_cumulative analyze]
  after_action :verify_authorized, except: %i[index search show_performance]

  # GET /kpi_reports or /kpi_reports.json
  def index
    authorize(KpiReport)
    # Extract sort_field and sort_direction
    sort_field, sort_direction, sort_query = extract_sorting_params

    @q = KpiReport.ransack(params[:q])

    @kpi_reports = policy_scope(@q.result).includes(:entity, :portfolio_company)

    @kpi_reports = if params[:grid_view].present?
                     @kpi_reports.includes(:kpis, :documents, :owner)
                   else
                     @kpi_reports.includes(:user)
                   end

    @kpi_reports = if params[:tag_list].blank?
                     @tag_list = ["Actual"]
                     @kpi_reports.where(tag_list: @tag_list)
                   elsif params[:tag_list].is_a?(String)
                     @tag_list = params[:tag_list].split(",").map(&:strip)
                     @kpi_reports.where(tag_list: @tag_list)
                   elsif params[:tag_list].is_a?(Array)
                     @tag_list = params[:tag_list].map(&:strip)
                     @kpi_reports.where(tag_list: @tag_list)
                   end

    @kpi_reports = sort_field == "entity_name" ? @kpi_reports.order("entities.name #{sort_direction}") : @kpi_reports
    @kpi_reports = filter_params(@kpi_reports, :period, :owner_type, :entity_id, :import_upload_id)
    @kpi_reports = KpiReportSearch.perform(@kpi_reports, params)
    @entity = Entity.find(params[:entity_id]) if params[:entity_id].present?

    @pagy, @kpi_reports = pagy(@kpi_reports, limit: params[:per_page]) if params[:all].blank? && !request.format.xlsx?

    # Add back the sort field so UI can reflect the current sort if sorted by entity_name
    @q.sorts = sort_query if sort_query.present?

    respond_to do |format|
      format.html { render :index }
      format.xlsx { render :index }
      format.json { render json: KpiReportDatatable.new(params, kpi_reports: @kpi_reports) }
    end
  end

  # GET /kpi_reports/1 or /kpi_reports/1.json
  def show; end

  def analyze
    @prev_kpi_report = KpiReport.where(entity_id: @kpi_report.entity_id, as_of: ..(@kpi_report.as_of - 1.day)).order(as_of: :asc).last
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

    @kpi_mappings = @kpi_report.portfolio_company.investor_kpi_mappings.order(:reported_kpi_name) if @kpi_report.portfolio_company.present?
    setup_custom_fields(@kpi_report)
    @kpi_report.custom_kpis
  end

  # GET /kpi_reports/1/edit
  def edit
    setup_custom_fields(@kpi_report)
    @kpi_mappings = @kpi_report.portfolio_company.investor_kpi_mappings.order(:reported_kpi_name) if @kpi_report.portfolio_company.present?
    @kpi_report.custom_kpis
  end

  # POST /kpi_reports or /kpi_reports.json
  def create
    @kpi_report = KpiReport.new(kpi_report_params)
    @kpi_report.user_id = current_user.id
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
      if @kpi_report.update(kpi_report_params.merge(user_id: current_user.id))
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
    KpiPercentageChangeJob.perform_later(@kpi_report.portfolio_company_id, current_user.id)
    redirect_to request.referer || kpi_report_url(@kpi_report), notice: "Computation started."
  end

  # rubocop:disable Rails/SkipsModelValidations
  def recompute_cumulative
    # Force recomputation by resetting cumulation_completed if necessary
    # and ensuring the job picks up all reports for this portfolio company
    KpiReport.where(portfolio_company_id: @kpi_report.portfolio_company_id).update_all(cumulation_completed: false)
    KpiCumulateJob.perform_later(@kpi_report.portfolio_company_id, user_id: current_user.id, force: true)
    redirect_to request.referer || kpi_report_url(@kpi_report), notice: "Recompute cumulative and forward fill started."
  end
  # rubocop:enable Rails/SkipsModelValidations

  def send_portco_notification
    portfolio_company = Investor.find(params[:portfolio_company_id])
    kpi_report = find_or_create_kpi_report_shell(portfolio_company)
    authorize kpi_report, :send_portco_notification?

    SendPortcoNotification.call(model: kpi_report, entity_id: current_user.entity_id)
    redirect_to investor_url(id: portfolio_company.id, tab: "kpis-tab"), notice: "Notification sent."
  end

  def trigger_periodic_reports
    authorize KpiReport, :trigger_periodic_reports?
    GeneratePeriodicKpiReportsJob.perform_later(params[:portfolio_company_id], params[:id])
    redirect_to request.referer || kpi_reports_path, notice: "Periodic KPI reports generation triggered."
  end

  def show_performance
    @as_of = params[:as_of].present? ? Date.local_parse(params[:as_of]) : (Time.zone.today.end_of_month - 1.month)
    @kpi_report = KpiReport.find_by(portfolio_company_id: params[:portfolio_company_id], as_of: @as_of)
    @portfolio_company = Investor.find(params[:portfolio_company_id]) if params[:portfolio_company_id].present?

    if @kpi_report.present?
      authorize @kpi_report

      @rows = PerformanceTableService.call(
        kpi_report: @kpi_report,
        portfolio_company_id: params[:portfolio_company_id],
        as_of: @as_of,
        metric_names: params[:metric_names]&.split # or fetch dynamically
      )
    end

    render :performance_table
  end

  private

  def extract_sorting_params
    return [nil, nil, nil] unless params[:q]&.dig(:s)

    sort_field, sort_direction = params[:q][:s].split
    sort_field = nil unless sort_field == "entity_name"
    sort_direction = sort_direction&.downcase == 'desc' ? 'DESC' : 'ASC'
    sort_query = params[:q].delete(:s)

    [sort_field, sort_direction, sort_query]
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_kpi_report
    @kpi_report = KpiReport.find(params[:id])
    authorize @kpi_report
    @bread_crumbs = { Kpis: kpi_reports_path, "#{@kpi_report.as_of}": kpi_report_path(@kpi_report) }
  end

  # Only allow a list of trusted parameters through.
  def kpi_report_params
    params.require(:kpi_report).permit(:portfolio_company_id, :entity_id, :as_of, :tag_list, :notes, :user_id, :form_type_id, :delete_kpis, :update_existing_kpis, :upload_new_kpis, :period, properties: {}, kpis_attributes: %i[id entity_id name period value display_value notes _destroy], documents_attributes: Document::NESTED_ATTRIBUTES)
  end

  def find_or_create_kpi_report_shell(portfolio_company)
    # Requirement: notifications must target an Actual-tag KPI report shell at quarter end.
    # If the request is sent more than 15 days after quarter end and the previous quarter
    # report is still empty (no KPIs), we should reuse that previous quarter shell.
    current_quarter_end = Time.zone.today.end_of_quarter
    as_of = current_quarter_end
    period = "Quarter"

    if Time.zone.today > (current_quarter_end + 15.days)
      # Create (or reuse) the previous quarter shell so we can check if it has KPIs.
      previous_quarter_end = (Time.zone.today - 3.months).end_of_quarter
      previous_report = find_or_create_kpi_report_for(portfolio_company, previous_quarter_end, period)
      as_of = previous_report.kpis.none? ? previous_quarter_end : current_quarter_end

      # If we are reusing the previous quarter, return that shell directly.
      return previous_report if as_of == previous_quarter_end
    end

    # Default to the current quarter shell.
    KpiReport.find_or_create_by(
      entity_id: current_user.entity_id,
      portfolio_company_id: portfolio_company.id,
      as_of: as_of,
      period: period,
      tag_list: "Actual"
    ) do |report|
      report.user_id = current_user.id
      report.enable_portco_upload = true
    end
  end
end
