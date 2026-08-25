class KpisController < ApplicationController
  before_action :set_kpi, only: %i[show edit update destroy approve reject unapprove]

  # GET /kpis or /kpis.json
  def index
    @bread_crumbs = { Kpis: kpis_path }
    authorize(Kpi)

    # For XLSX format, hand off to background job (can be a large dataset)
    if request.format.xlsx?
      trigger_model_download
      return # Ensure we don't continue with the rest of the action after triggering the download
    end

    service = KpiList.call(current_user, params) { |relation| policy_scope(relation) }
    @q = service.q
    @kpis = service.kpis

    if params[:grid_view].present?
      # Paginate by the exact series the grid groups by:
      # [name, portfolio_company_id, entity_id, owner_id, tag_list].
      # Each unique combination = exactly one table row, so the count matches.
      per_page = (params[:per_page] || 10).to_i
      @pagy_series, paged_series = pagy(service.kpi_series, limit: per_page)

      # Scope the full kpi records to only those belonging to the current page's series.
      # unscope(:includes) prevents AR from running includes as a separate preload query
      # which would conflict with the explicit JOIN on kpi_reports used in the WHERE clause.
      series_tuples = paged_series.map { |s| [s.name, s.portfolio_company_id, s.entity_id, s.owner_id, s.tag_list] }
      @kpis = if series_tuples.any?
                conditions = series_tuples.map do |_|
                  "( kpis.name = ? AND kpis.portfolio_company_id <=> ? AND kpis.entity_id <=> ? AND kpis.owner_id <=> ? AND kpi_reports.tag_list <=> ? )"
                end.join(" OR ")
                @kpis.unscope(:includes)
                     .includes(kpi_report: :portfolio_company)
                     .joins(:kpi_report)
                     .where(conditions, *series_tuples.flatten)
                     .order("kpis.name ASC, kpi_reports.tag_list ASC, kpis.portfolio_company_id ASC, kpis.owner_id ASC")
              else
                @kpis.none
              end
    elsif params[:all].blank?
      @pagy, @kpis = pagy(@kpis, limit: params[:per_page] || 10)
    end

    respond_to do |format|
      format.html
    end
  end

  # GET /kpis/1 or /kpis/1.json
  def show
    @bread_crumbs = { Kpis: kpis_path }
    # A KpiReport can exist with no portfolio_company_id (legacy/orphaned data) — guard on the
    # association itself, not just kpi_report.present?, so this doesn't 500 on those rows.
    if @kpi.kpi_report&.portfolio_company.present?
      @bread_crumbs[@kpi.kpi_report.portfolio_company.investor_name.to_s] = investor_path(@kpi.kpi_report.portfolio_company)
      @bread_crumbs[@kpi.kpi_report.as_of.to_s] = kpi_report_path(@kpi.kpi_report)
    end
    @bread_crumbs[@kpi.name.to_s] = kpi_path(@kpi)
  end

  # GET /kpis/new
  def new
    @kpi = Kpi.new(kpi_params)
    @kpi.entity_id = current_user.entity_id
    @bread_crumbs = { Kpis: kpis_path }
    # A KpiReport can exist with no portfolio_company_id (legacy/orphaned data) — guard on the
    # association itself, not just kpi_report.present?, so this doesn't 500 on those rows.
    if @kpi.kpi_report&.portfolio_company.present?
      @bread_crumbs[@kpi.kpi_report.portfolio_company.investor_name.to_s] = investor_path(@kpi.kpi_report.portfolio_company)
      @bread_crumbs[@kpi.kpi_report.as_of.to_s] = kpi_report_path(@kpi.kpi_report)
    end
    @bread_crumbs[:New] = nil

    authorize @kpi
    setup_custom_fields(@kpi)
  end

  # GET /kpis/1/edit
  def edit
    @bread_crumbs = { Kpis: kpis_path }
    # A KpiReport can exist with no portfolio_company_id (legacy/orphaned data) — guard on the
    # association itself, not just kpi_report.present?, so this doesn't 500 on those rows.
    if @kpi.kpi_report&.portfolio_company.present?
      @bread_crumbs[@kpi.kpi_report.portfolio_company.investor_name.to_s] = investor_path(@kpi.kpi_report.portfolio_company)
      @bread_crumbs[@kpi.kpi_report.as_of.to_s] = kpi_report_path(@kpi.kpi_report)
    end
    @bread_crumbs[@kpi.name.to_s] = kpi_path(@kpi)
    @bread_crumbs[:Edit] = nil
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
    @kpi = KpiApproveService.call([@kpi.id], current_user.id)
    respond_to do |format|
      format.html { redirect_back_or_to(kpi_reports_path, notice: "KPI was successfully approved.") }
      format.json { render :show, status: :ok, location: @kpi }
    end
  end

  def reject
    @kpi.destroy
    respond_to do |format|
      format.html { redirect_back_or_to(kpi_reports_path, notice: "KPI was successfully rejected.") }
      format.json { head :no_content }
    end
  end

  def unapprove
    @kpi.unapprove!
    respond_to do |format|
      format.html { redirect_back_or_to(kpi_path(@kpi), notice: "KPI was successfully unapproved.") }
      format.json { render :show, status: :ok, location: @kpi }
    end
  end

  def approve_all
    portfolio_company_id = params[:portfolio_company_id]
    entity_id = params[:entity_id] || current_user.entity_id

    unapproved_kpis = Kpi.unapproved.where(portfolio_company_id: portfolio_company_id, entity_id: entity_id)

    if params[:reject] == 'true'
      unapproved_kpis.find_each do |kpi|
        authorize kpi, :reject?
        kpi.destroy
      end
      notice = "All pending KPIs were successfully rejected."
    else
      kpi_ids = []
      unapproved_kpis.find_each do |kpi|
        authorize kpi, :approve?
        kpi_ids << kpi.id
      end

      KpiApproveService.call(kpi_ids, current_user.id)
      notice = "All pending KPIs were successfully approved."
    end

    respond_to do |format|
      format.html { redirect_back_or_to(kpi_reports_path, notice: notice) }
      format.json { head :no_content }
    end
  end

  private

  def trigger_model_download
    skip_policy_scope # Policy scope is applied inside ModelDownloadJob via KpiList

    url = begin
      URI(request.referer).request_uri
    rescue URI::InvalidURIError, ArgumentError
      nil
    end

    # Strip Rails-internal keys that are meaningless (and potentially sensitive) inside a job.
    # All domain/query params (q[], grid_view, per_page, kpi_report_id, etc.) are preserved
    # intentionally so the job reproduces exactly the same filtered dataset as the index page.
    job_params = params.to_unsafe_h.except("authenticity_token", "utf8", "_method", "format", "action", "controller")

    if params[:grid_view].present?
      ModelDownloadJob.set(wait: 2.seconds).perform_later(
        model_class: "Kpi",
        params: job_params,
        user_id: current_user.id,
        template: "kpis/grid_view",
        filename: "kpis_grid.xlsx",
        url: url
      )
    else
      ModelDownloadJob.set(wait: 2.seconds).perform_later(
        model_class: "Kpi",
        params: job_params,
        user_id: current_user.id,
        template: "kpis/index",
        filename: "kpis.xlsx",
        url: url
      )
    end

    redirect_params = params.to_unsafe_h.except(:format, :all)
    redirect_to kpis_path(params: redirect_params),
                notice: "Your download is being prepared. You will receive a notification with a download link and an email when it's ready."
    nil
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_kpi
    @kpi = Kpi.find(params[:id])
    authorize @kpi
  end

  # Only allow a list of trusted parameters through.
  def kpi_params
    params.require(:kpi).permit(:entity_id, :name, :value, :status, :display_value, :notes, :kpi_report_id, :form_type_id, properties: {})
  end
end
