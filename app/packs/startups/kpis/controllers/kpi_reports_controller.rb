class KpiReportsController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[show edit update], if: -> { params[:signed_id].present? }
  before_action :set_kpi_report, only: %i[show edit update destroy recompute_percentage_change recompute_cumulative analyze]
  after_action :verify_authorized, except: %i[index search show_performance chart_refresh]
  after_action :verify_policy_scoped, only: %i[index chart_refresh]

  # GET /kpi_reports or /kpi_reports.json
  def index
    authorize(KpiReport)
    fetch_kpi_reports

    @pagy, @kpi_reports = pagy(@kpi_reports, limit: params[:per_page]) if params[:all].blank? && params[:grid_view].blank? && !request.format.xlsx?

    respond_to do |format|
      format.html { render :index }
      format.xlsx { render :index }
      format.json { render json: KpiReportDatatable.new(params, kpi_reports: @kpi_reports) }
      format.turbo_stream do
        if params[:flexible_chart] == "true"
          prepare_chart_configs
          render turbo_stream: turbo_stream.replace("kpi_grid_view_chart_container",
                                                    partial: "kpi_reports/grid_view_chart",
                                                    locals: { kpi_reports: @kpi_reports, investor_kpi_mappings: @investor_kpi_mappings, chart_configs: @chart_configs, investor: @investor })
        end
      end
    end
  end

  def chart_refresh
    authorize(KpiReport)
    fetch_kpi_reports
    prepare_chart_configs

    render turbo_stream: turbo_stream.replace("kpi_grid_view_chart_container",
                                              partial: "kpi_reports/grid_view_chart",
                                              locals: { kpi_reports: @kpi_reports, investor_kpi_mappings: @investor_kpi_mappings, chart_configs: @chart_configs, investor: @investor })
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
        format.html { redirect_to kpi_report_url(@kpi_report, signed_id: params[:signed_id]), notice: "Kpi report was successfully created." }
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
        format.html { redirect_to kpi_report_url(@kpi_report, signed_id: params[:signed_id]), notice: "Kpi report was successfully updated." }
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
    # Force recomputation by resetting autofill_completed if necessary
    # and ensuring the job picks up all reports for this portfolio company
    KpiReport.where(portfolio_company_id: @kpi_report.portfolio_company_id).update_all(autofill_completed: false)
    KpiCumulateJob.perform_later(@kpi_report.portfolio_company_id, user_id: current_user.id, force: true)
    redirect_to request.referer || kpi_report_url(@kpi_report), notice: "Recompute cumulative and forward fill started."
  end
  # rubocop:enable Rails/SkipsModelValidations

  def send_portco_notification
    # Ensure we handle single or multiple portfolio_company_ids
    portfolio_company_ids = params[:portfolio_company_ids] || [params[:portfolio_company_id]]
    portfolio_company_ids = portfolio_company_ids.compact.compact_blank

    if portfolio_company_ids.include?("all")
      portfolio_company_ids = Investor.where(entity_id: current_user.entity_id)
                                      .where(category: "Portfolio Company")
                                      .pluck(:id)
    end

    if portfolio_company_ids.empty?
      redirect_to request.referer || kpi_reports_path, alert: "No portfolio companies selected."
      return
    end

    # Authorization check: user should have update permissions for each portfolio company
    portfolio_company_ids.each do |pc_id|
      pc = Investor.find(pc_id)
      authorize pc, :update?
    end

    SendPortcoNotificationJob.perform_later(
      portfolio_company_ids,
      user_id: current_user.id,
      as_of: params[:as_of],
      period: params[:period]
    )

    notice = portfolio_company_ids.size > 1 ? "Notifications are being sent." : "Notification is being sent."
    respond_to do |format|
      format.html { redirect_to request.referer || kpi_reports_path, notice: notice }
      format.turbo_stream do
        flash.now[:notice] = notice
        streams = [
          turbo_stream.update("remote_modal", ""),
          turbo_stream.append("remote_modal", partial: "kpi_reports/alerts"),
          turbo_stream.update("remote_modal_alerts", partial: "kpi_reports/alerts")
        ]
        # rubocop:disable Rails/OutputSafety
        streams << turbo_stream.append("remote_modal_alerts", "<script>bootstrap.Modal.getInstance(document.getElementById('#{params[:modal_id]}'))?.hide()</script>".html_safe) if params[:modal_id].present?
        render turbo_stream: streams
        # rubocop:enable Rails/OutputSafety
      end
    end
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

  def new_notification
    authorize Investor, :index?
    @portfolio_companies = Investor.where(entity_id: current_user.entity_id)
                                   .where(category: "Portfolio Company")
                                   .order(:investor_name)
    @selected_ids = params[:portfolio_company_ids] || []

    render layout: false
  end

  private

  def extract_sorting_params
    q_param = params[:q]

    return [nil, nil, nil] unless q_param.is_a?(Hash) && q_param[:s]

    sort_field, sort_direction = params[:q][:s].split
    sort_field = nil unless sort_field == "entity_name"
    sort_direction = sort_direction&.downcase == 'desc' ? 'DESC' : 'ASC'
    sort_query = params[:q].delete(:s)

    [sort_field, sort_direction, sort_query]
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_kpi_report
    find_by_signed_id_for_user(params[:signed_id]) if params[:signed_id].present?
    @kpi_report ||= KpiReport.find(params[:id]) if params[:id].present? && params[:id] != 'shared'

    authorize @kpi_report
    @bread_crumbs = { Kpis: kpi_reports_path, "#{@kpi_report.as_of}": kpi_report_path(@kpi_report) }
  end

  # Only allow a list of trusted parameters through.
  def kpi_report_params
    params.require(:kpi_report).permit(:portfolio_company_id, :entity_id, :as_of, :tag_list, :notes, :user_id, :form_type_id, :delete_kpis, :update_existing_kpis, :upload_new_kpis, :period, properties: {}, kpis_attributes: %i[id entity_id name period value display_value notes _destroy], documents_attributes: Document::NESTED_ATTRIBUTES)
  end

  def search
    @q = KpiReport.ransack(params[:q])
    @kpi_reports = policy_scope(@q.result).includes(:entity, :portfolio_company)
    render json: @kpi_reports.map { |kr| { id: kr.id, text: kr.name } }
  end

  private

  def fetch_kpi_reports
    if params[:q].is_a?(String)
      begin
        params[:q] = JSON.parse(params[:q]).with_indifferent_access
      rescue JSON::ParserError
        params[:q] = nil
      end
    end

    # Ensure consistency in parameters for search window
    params[:portfolio_company_id] ||= params[:q][:portfolio_company_id_eq] if params[:q].present? && params[:q][:portfolio_company_id_eq].present?

    @q = KpiReport.ransack(params[:q])
    sort_field, sort_direction, sort_query = extract_sorting_params

    @kpi_reports = policy_scope(@q.result).includes(:entity, :portfolio_company)

    if params[:tag_list].blank?
      @tag_list = ["Actual"]
      @kpi_reports = @kpi_reports.where(tag_list: @tag_list)
    elsif params[:tag_list].is_a?(String)
      @tag_list = params[:tag_list].split(",").map(&:strip)
      @kpi_reports = @kpi_reports.where(tag_list: @tag_list)
    elsif params[:tag_list].is_a?(Array)
      @tag_list = params[:tag_list].map(&:strip)
      @kpi_reports = @kpi_reports.where(tag_list: @tag_list)
    end

    @kpi_reports = if params[:grid_view].present? || params[:flexible_chart] == "true"
                     @kpi_reports.includes(:kpis, :documents, :owner)
                   else
                     @kpi_reports.includes(:user)
                   end

    @kpi_reports = sort_field == "entity_name" ? @kpi_reports.order("entities.name #{sort_direction}") : @kpi_reports
    @kpi_reports = filter_params(@kpi_reports, :period, :owner_type, :entity_id, :import_upload_id)
    @kpi_reports = KpiReportSearch.perform(@kpi_reports, params)

    @investor = Investor.find_by(id: params[:portfolio_company_id])

    @investor_kpi_mappings = helpers.set_investor_kpi_mappings(@kpi_reports, @investor, current_user, category: params[:category])

    # Add back the sort field so UI can reflect the current sort if sorted by entity_name
    @q.sorts = sort_query if sort_query.present?
  end

  def prepare_chart_configs
    @chart_configs = []

    # Add current manual config if present
    if params[:chart_config].present?
      manual_config = params[:chart_config].is_a?(ActionController::Parameters) ? params[:chart_config].values : params[:chart_config]
      @chart_configs << { name: "Current Selection", config: manual_config } if manual_config.any?
    end

    # Add saved settings configs
    if params[:selected_setting_ids].present?
      saved_settings = KpiChartSetting.where(id: params[:selected_setting_ids], user_id: current_user.id)
      saved_settings.each do |s|
        @chart_configs << { name: s.name, config: s.config }
      end
    end
  end
end
