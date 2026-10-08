class KpiReportsController < ApplicationController
  include WithJourneyPanel # show's journey evaluation and the journey action (kpi-report-journey)

  skip_before_action :authenticate_user!, only: %i[show edit update validate_upload template], if: -> { params[:signed_id].present? }
  # validate_upload is called by JS after Uppy finishes; the magic link's signed_id keeps it usable
  # by unauthenticated portco users, and CSRF is enforced by the token the form page carries.
  before_action :set_kpi_report, only: %i[show edit update destroy recompute_percentage_change recompute_cumulative recompute_fx_conversion analyze refresh_import mark_reviewed reopen journey send_completion_email]
  before_action :set_kpi_report_for_validation, only: %i[validate_upload template]
  # edit.html.erb shows a portfolio company the submitted page instead of the wizard by the same rule
  helper_method :portco_actor?
  after_action :verify_authorized, except: %i[index search show_performance chart_refresh refresh_import portco_pending]
  after_action :verify_policy_scoped, only: %i[index chart_refresh]

  # GET /kpi_reports or /kpi_reports.json
  def index
    @bread_crumbs = { Kpis: kpi_reports_path }
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
  # Fund users see the KPI report journey (step bar + what's needed now) — never portco users, who
  # reach this page by magic link or as investors.
  # Worked examples H4, H9 — openspec/changes/kpi-report-journey/design.md#worked-examples
  def show
    @journey = evaluate_journey(@kpi_report) if current_user && policy(@kpi_report).journey?
  end

  # GET /kpi_reports/:id/journey — just the journey panel, for the frame a real-time update inserts.
  # Worked examples H9 — openspec/changes/kpi-report-journey/design.md#worked-examples
  def journey
    authorize @kpi_report
    render_journey_panel(@kpi_report)
  end

  # PATCH /kpi_reports/:id/send_completion_email — the optional "Send completion email" step's button.
  # Worked examples H8, E10 — openspec/changes/kpi-report-journey/design.md#worked-examples
  def send_completion_email
    authorize @kpi_report
    result = KpiReportCompletionEmail.call(kpi_report: @kpi_report, user: current_user)
    flash_key, message = case result[:outcome]
                         when :sent then [:notice, "Completion email sent to #{result[:recipients].map(&:full_name).to_sentence}."]
                         when :already_sent then [:notice, "The completion email was already sent."]
                         else [:alert, "No recipients — set Managed by on the portfolio company or pick the step's actors."]
                         end
    redirect_to kpi_report_url(@kpi_report), flash_key => message
  end

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
    @bread_crumbs = { Kpis: kpi_reports_path }
    @bread_crumbs[@kpi_report.portfolio_company.investor_name.to_s] = investor_path(@kpi_report.portfolio_company) if @kpi_report.portfolio_company.present?
    @bread_crumbs[:New] = nil

    authorize @kpi_report

    @kpi_mappings = @kpi_report.portfolio_company.investor_kpi_mappings.order(:reported_kpi_name) if @kpi_report.portfolio_company.present?
    setup_custom_fields(@kpi_report)
    @kpi_report.custom_kpis
  end

  # GET /kpi_reports/1/edit
  def edit
    @bread_crumbs[:Edit] = nil
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

    # A workbook with blocking errors is never saved — for fund users too (§2.1 applies to everyone;
    # the requested-period rule is only a warning on fund-created reports, so what blocks here are
    # genuine file problems: no header, unreadable values, duplicates, no mappings …).
    if (blocked = uploaded_workbook_blocked?(current_user))
      setup_custom_fields(@kpi_report)
      @kpi_mappings = @kpi_report.portfolio_company.investor_kpi_mappings.order(:reported_kpi_name) if @kpi_report.portfolio_company.present?
      flash.now[:alert] = blocked
      render :new, status: :unprocessable_entity
      return
    end

    respond_to do |format|
      if @kpi_report.save
        # A report created on the New screen is a request: it gets the KPI report journey (no email)
        # Worked examples H14 — openspec/changes/kpi-report-journey/design.md#worked-examples
        @kpi_report.start_journey!(current_user)
        format.html { redirect_to edit_kpi_report_url(@kpi_report, signed_id: params[:signed_id]), notice: "Kpi report was successfully created." }
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

    was_already_submitted = @kpi_report.status_submitted? || @kpi_report.status_reviewed?
    status_attrs = resolve_status_transition(params[:submit_action])
    # current_user is nil for unauthenticated magic-link submissions; fall back to @signed_id_user.
    acting_user = current_user || @signed_id_user
    merged = kpi_report_params.merge(user_id: acting_user&.id).merge(status_attrs)
    # Portco uploads always refresh existing staged values — set here rather than trusted from the wire.
    # (string — KpiReport#import_kpis tests %w[1 true])
    merged[:update_existing_kpis] = 'true' if portco_actor?

    # A fund user may re-point a report to another portfolio company, but only one of their own —
    # authorisation ran against the record as loaded, so re-check the target (§2.8).
    return unless authorized_target_portfolio_company?(merged[:portfolio_company_id])

    # Fund users: a newly uploaded workbook with blocking errors is not saved either — same rule as the
    # portco gate, minus the "requested period" strictness (a warning for fund-created reports).
    if !portco_actor? && (blocked = uploaded_workbook_blocked?(acting_user))
      setup_custom_fields(@kpi_report)
      @kpi_mappings = @kpi_report.portfolio_company.investor_kpi_mappings.order(:reported_kpi_name) if @kpi_report.portfolio_company.present?
      flash.now[:alert] = blocked
      render :edit, status: :unprocessable_entity
      return
    end

    # Submit gate (§2.1 / §2.2 D): a portco's final submission must carry a KPI workbook that passes
    # the same server-side check the pre-save panel showed. If it does not, save what they sent as a
    # draft (so the upload is not lost), keep the status, do not notify the fund, and show the errors.
    if status_attrs[:status] == 'submitted' && !was_already_submitted && portco_actor?
      verdict = gate_verdict(acting_user)
      # Passed the gate: mark the import as pending — ImportKpiWorkbookJob flips it to imported/failed
      # and is the one that notifies the fund (§2.2 E), so "submitted" always means "and staged".
      if verdict['ok']
        merged[:import_status] = 'pending'
        # The import job is what completes the submission — make sure after_commit enqueues it
        # (string — KpiReport#import_kpis tests %w[1 true]).
        merged[:upload_new_kpis] = 'true'
      end
      unless verdict['ok']
        merged = merged.except(:status, :submitted_at)
        merged[:status] = 'draft_saved' if @kpi_report.status_shell_created? || @kpi_report.status_link_sent?
        status_attrs = {}
        error_count = Array(verdict['errors']).size
        flash[:alert] = "Not submitted — the KPI workbook has #{helpers.pluralize(error_count, 'blocking error')}. " \
                        "Your changes were saved as a draft; please fix the errors shown below and submit again."
      end
    end

    Rails.logger.info "=== KPI UPDATE ==="
    # Use filtered_parameters (not params.inspect) so signed_id bearer tokens are
    # never written to logs in plaintext — raw params.inspect bypasses filter_parameters.
    Rails.logger.info "params: #{request.filtered_parameters.inspect}"
    Rails.logger.info "merged: #{merged.inspect}"
    # Hard-deletes every Kpi on the report — fund-only, so leave a trace of who asked for it.
    Rails.logger.warn "KpiReport##{@kpi_report.id}: delete_kpis requested by user #{acting_user&.id} (#{@kpi_report.kpis.count} rows)" if %w[1 true].include?(merged[:delete_kpis].to_s)

    # Taken before anything changes, for the journey undo below (sign-offs given before it are reset)
    journey_started_at = Time.current
    respond_to do |format|
      if @kpi_report.update(merged)
        Rails.logger.info "KPI update succeeded!"
        # KPI report journey: deleting the report's KPIs is an undo (back to "Import workbook"); any other
        # save — a portco submit, a fund edit — only moves it on. Worked examples E12 —
        # openspec/changes/kpi-report-journey/design.md#worked-examples
        if %w[1 true].include?(merged[:delete_kpis].to_s)
          @kpi_report.journey_undo_evaluate(note: "KPIs deleted", started_at: journey_started_at, actor: acting_user)
        else
          @kpi_report.journey_progress!(actor: acting_user)
        end
        # The document just attached (if any) is now the report's KPIs file — refresh the stored
        # verdict so the panel the user lands on reflects it (display only; the gate recomputed above).
        KpiUploadValidate.call(kpi_report: @kpi_report, user: acting_user) if merged[:documents_attributes].present? && @kpi_report.documents.exists?(name: "KPIs")
        # Fund users submitting on a portco's behalf (no import gate) are notified immediately as before;
        # portco submissions notify from the import job once the data is staged.
        notify_fund_on_submission(@kpi_report) if status_attrs[:status] == 'submitted' && !was_already_submitted && !portco_actor?
        notice = if flash[:alert].present?
                   nil
                 elsif status_attrs[:status] == 'submitted'
                   "KPI report submitted. Your workbook is being imported and the fund team will be notified."
                 else
                   "Kpi report was successfully updated."
                 end
        format.html { redirect_to edit_kpi_report_url(@kpi_report, signed_id: params[:signed_id]), notice: notice }
        format.json { render :show, status: :ok, location: @kpi_report }
      else
        Rails.logger.info "KPI update failed: #{@kpi_report.errors.full_messages}"
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @kpi_report.errors, status: :unprocessable_entity }
      end
    end
  end

  # POST /kpi_reports/:id/validate_upload
  #
  # Dry-run validation of a KPI workbook (docs/modules/portfolio/kpis/kpi_portco_upload_validation_review.md §3.1 C).
  # The browser holds NO rules — Uppy uploads to the Shrine cache, JS posts the cached-file JSON here,
  # KpiWorkbookReader#validate parses it exactly as the import would (writing nothing), and the
  # verdict is rendered into the validation panel. The same reader gates final submission, so what
  # the portco sees is what will be stored. Accepts `file_data` (Shrine cached JSON), a multipart
  # `file`, or neither (re-check the already-attached KPIs document, e.g. on page load).
  # Member route: an existing report (portco magic link, fund edit page). Collection route: the fund's
  # New page — the report context (portfolio company, as_of, period, tag) is built from the form fields.
  def validate_upload
    acting_user = current_user || @signed_id_user
    result = KpiUploadValidate.call(kpi_report: @kpi_report, user: acting_user,
                                    file_data: params[:file_data], file: params[:file])
    @verdict = result[:verdict]

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "kpi_validation_panel",
          partial: "kpi_reports/validation_panel",
          locals: { verdict: @verdict, kpi_report: @kpi_report }
        )
      end
      format.json { render json: @verdict }
      format.html { redirect_to(@kpi_report.persisted? ? edit_kpi_report_url(@kpi_report, signed_id: params[:signed_id]) : new_kpi_report_url) }
    end
  end

  # PATCH /kpi_reports/:id/reopen — fund side "reopen and ask for re-upload" (§3.4 Q): back to
  # draft_saved, submission markers cleared, magic link re-sent to the portco's Kpi users.
  def reopen
    authorize @kpi_report
    @kpi_report.reopen_for_portco!(current_user.entity_id, actor: current_user)
    redirect_to kpi_report_url(@kpi_report), notice: "Report reopened and the portfolio company has been asked to upload again."
  end

  # GET /kpi_reports/:id/template.xlsx (or /kpi_reports/template.xlsx before the report is saved) —
  # a workbook pre-filled with this portco's KPI names and the requested period (plus the two
  # previous ones), so uploads start from a file the importer reads without guesswork (§3.4 P).
  # Magic-link users can download it too; set_kpi_report_for_validation resolves @kpi_report from
  # params[:id]/params[:signed_id] when present, or from the New page's in-progress form fields
  # otherwise (same split as validate_upload, for the same reason: the wizard has no id yet).
  def template
    result = KpiTemplateGenerate.call(kpi_report: @kpi_report)
    send_data result[:xlsx], filename: result[:filename],
                             type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  # PATCH /kpi_reports/:id/mark_reviewed — the Close report button: approves every KPI still pending
  # for the portfolio company (on any period of the upload, not just this report) and marks it reviewed.
  # Worked examples H5 — openspec/changes/kpi-report-journey/design.md#worked-examples
  def mark_reviewed
    authorize @kpi_report
    result = KpiReportClose.call(kpi_report: @kpi_report, user: current_user)
    redirect_to kpi_report_url(@kpi_report),
                notice: "Report closed — #{helpers.pluralize(result[:approved], 'KPI')} approved across #{helpers.pluralize(result[:periods], 'period')}."
  end

  # GET /kpi_reports/portco_pending — dashboard of outstanding requests for the logged-in portco user
  def portco_pending
    authorize KpiReport, :portco_pending?
    # policy_scope uses the for_investor scope which joins on access_rights — portco users have no
    # access_rights entries on the fund's KPI reports, so we query directly by the portco's entity.
    @kpi_reports = KpiReport
                   .portco_pending
                   .joins(:portfolio_company)
                   .where(investors: { investor_entity_id: current_user.entity_id })
                   .includes(:portfolio_company, :entity)
    @bread_crumbs = { 'Pending KPI Requests': portco_pending_kpi_reports_path }
  end

  def refresh_import
    respond_to do |format|
      if @kpi_report.update(kpi_report_params.slice(:upload_new_kpis, :update_existing_kpis).merge(user_id: current_user.id))
        format.html { redirect_to(request.referer || kpi_report_url(@kpi_report, signed_id: params[:signed_id]), notice: "KPI Report refresh enqueued.") }
        format.json { render :show, status: :ok, location: @kpi_report }
      else
        format.html do
          flash.now[:alert] = "KPI Report refresh failed: #{@kpi_report.errors.full_messages.join(', ')}"
          redirect_to(request.referer || kpi_report_url(@kpi_report, signed_id: params[:signed_id]))
        end
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

  def recompute_cumulative
    # Force recomputation by resetting autofill_completed if necessary
    # and ensuring the job picks up all reports for this portfolio company
    KpiReport.where(portfolio_company_id: @kpi_report.portfolio_company_id).update_all(autofill_completed: false)
    KpiCumulateJob.perform_later(@kpi_report.portfolio_company_id, user_id: current_user.id, force: true)
    redirect_to request.referer || kpi_report_url(@kpi_report), notice: "Recompute cumulative and forward fill started."
  end
  # rubocop:enable Rails/SkipsModelValidations

  # Enqueues a background job to re-convert all FX-converted KPIs for the
  # portfolio company using current exchange rates.
  def recompute_fx_conversion
    KpiCurrencyRecomputeJob.perform_later(@kpi_report.portfolio_company_id, user_id: current_user.id)
    redirect_to request.referer || kpi_report_url(@kpi_report), notice: "FX conversion recompute started."
  end

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

    # Authorization check: user must have KPI access, and all portcos must belong to their entity.
    authorize KpiReport.new(entity_id: current_user.entity_id), :index?
    portfolio_company_ids.each do |pc_id|
      pc = Investor.find(pc_id)
      raise Pundit::NotAuthorizedError, "portfolio company does not belong to your entity" unless pc.entity_id == current_user.entity_id
    end

    # Validate as_of before enqueueing so the user gets immediate feedback instead
    # of a silent job failure + error email.
    if params[:as_of].present?
      begin
        # Use local_parse so locale-specific formats (DD/MM/YYYY vs MM/DD/YYYY) are
        # interpreted consistently with the rest of the app rather than Ruby's default.
        Date.local_parse(params[:as_of])
      rescue ArgumentError
        redirect_to request.referer || kpi_reports_path, alert: "Invalid date format for 'As Of'."
        return
      end
    end

    # The report page's "Send upload request" names its own report: it must be this entity's and belong to
    # the one portfolio company being sent to. Worked examples H18 — openspec/changes/kpi-report-journey/design.md#worked-examples
    kpi_report_id = params[:kpi_report_id].presence
    if kpi_report_id && (portfolio_company_ids.size != 1 ||
                          !KpiReport.exists?(id: kpi_report_id, entity_id: current_user.entity_id, portfolio_company_id: portfolio_company_ids.first))
      redirect_to request.referer || kpi_reports_path, alert: "That KPI report was not found for this portfolio company."
      return
    end

    # One company with a date (the investor page's Send Reminder, or a single pick in the reminder modal):
    # create — or find — its report shell now and start its journey, so the user can be sent straight to
    # it. The job below finds this same report (same lookup), emails the link and moves it to Link Sent.
    target_report = nil
    if kpi_report_id.nil? && portfolio_company_ids.size == 1 && params[:as_of].present?
      target_report = SendPortcoNotificationJob.find_or_create_dated_report(
        Investor.find(portfolio_company_ids.first), current_user, params[:as_of], params[:period]
      )
      target_report.start_journey!(current_user)
    end

    # A period the company already submitted gets no reminder — the job would skip it anyway, so say so now
    already_submitted = target_report && (target_report.status_submitted? || target_report.status_reviewed?)
    unless already_submitted
      SendPortcoNotificationJob.perform_later(
        portfolio_company_ids,
        user_id: current_user.id,
        as_of: params[:as_of],
        period: params[:period],
        kpi_report_id:
      )
    end

    notice = if already_submitted
               "The KPI report for #{l(target_report.as_of)} is already #{target_report.status.humanize.downcase} — no reminder was sent."
             elsif portfolio_company_ids.size > 1
               "Notifications are being sent."
             else
               "Notification is being sent."
             end
    # A portco with no non-computed KPI mappings can upload nothing usable — say so now, at send time (§2.7).
    unmapped = Investor.where(id: portfolio_company_ids)
                       .where.not(id: InvestorKpiMapping.not_compute.select(:investor_id))
                       .order(:investor_name).pluck(:investor_name)
    unmapped_alert = "No KPI mappings configured for: #{unmapped.join(', ')} — their uploads will be rejected until mappings are added under Investors → KPI Mappings." if unmapped.any?

    # Land on the report the reminder is for, with its journey step bar. A full-page visit (the forms target
    # _top) also closes the reminder modal and its backdrop. Users who can't open the report stay put.
    if target_report && policy(target_report).show?
      redirect_to kpi_report_path(target_report), status: :see_other, notice: notice, alert: unmapped_alert
      return
    end

    respond_to do |format|
      format.html { redirect_to request.referer || kpi_reports_path, notice: notice, alert: unmapped_alert }
      format.turbo_stream do
        flash.now[:notice] = notice
        flash.now[:alert] = unmapped_alert if unmapped_alert
        render turbo_stream: [
          turbo_stream.update("remote_modal", ""),
          turbo_stream.append("remote_modal", partial: "kpi_reports/alerts"),
          turbo_stream.update("remote_modal_alerts", partial: "kpi_reports/alerts")
        ]
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

  # True when the acting user is NOT an employee of the fund that owns the report — i.e. a portco
  # self-reporting via magic link or a logged-in portco user. Drives param scoping and the submit gate.
  def portco_actor?
    acting_user = current_user || @signed_id_user
    return true if @signed_id_user.present?
    return false if acting_user.blank? || @kpi_report.blank?

    acting_user.entity_id != @kpi_report.entity_id
  end

  # Runs the same server-side check the pre-save panel uses, against the workbook this request is
  # submitting: a freshly uploaded file (Shrine cached JSON in documents_attributes) if present,
  # otherwise the KPIs document already attached to the report. Persists the verdict for display.
  def gate_verdict(acting_user)
    docs = params.dig(:kpi_report, :documents_attributes)
    file_data = nil
    if docs.respond_to?(:values)
      kpi_doc = docs.values.find { |d| d[:name].to_s == "KPIs" && d[:file].present? }
      file_data = kpi_doc[:file] if kpi_doc
    end
    KpiUploadValidate.call(kpi_report: @kpi_report, user: acting_user, file_data: file_data)[:verdict] || { 'ok' => false, 'errors' => [] }
  end

  # When this request attaches a NEW KPIs workbook (Shrine cached JSON in documents_attributes), run the
  # workbook check on it. Returns an alert message when it has blocking errors, nil otherwise
  # (no new file → nothing to check here; the existing document was checked when it was attached).
  def uploaded_workbook_blocked?(acting_user)
    docs = params.dig(:kpi_report, :documents_attributes)
    return nil unless docs.respond_to?(:values)

    kpi_doc = docs.values.find { |d| d[:name].to_s == "KPIs" && d[:file].present? }
    return nil unless kpi_doc

    verdict = KpiUploadValidate.call(kpi_report: @kpi_report, user: acting_user, file_data: kpi_doc[:file])[:verdict]
    return nil if verdict.blank? || verdict['ok']

    @verdict = verdict
    "Not saved — the KPI workbook has #{helpers.pluralize(Array(verdict['errors']).size, 'blocking error')}. Please fix the errors shown in the workbook check and try again."
  end

  # For a fund user changing portfolio_company_id: the target must belong to their own entity.
  # Renders a 403 and returns false when it does not (mirrors send_portco_notification's check).
  def authorized_target_portfolio_company?(new_pc_id)
    return true if new_pc_id.blank? || new_pc_id.to_i == @kpi_report.portfolio_company_id

    target = Investor.find_by(id: new_pc_id)
    raise Pundit::NotAuthorizedError, "portfolio company does not belong to this report's entity" if target.nil? || target.entity_id != @kpi_report.entity_id

    true
  end

  # Determines the status transition for the update action based on submit_action param.
  # "final" submits the report; anything else advances from shell/link_sent to draft_saved.
  def resolve_status_transition(submit_action)
    if submit_action == 'final'
      { status: 'submitted', submitted_at: Time.current }
    elsif @kpi_report.status_shell_created? || @kpi_report.status_link_sent?
      { status: 'draft_saved' }
    else
      {}
    end
  end

  # Notifies fund employees when a portco submits their KPI report.
  # Sends only to employees tagged "Kpi" if any exist; falls back to all employees.
  def notify_fund_on_submission(kpi_report)
    fund_entity = kpi_report.entity
    recipients = fund_entity.employees.with_tag('Kpi')
    recipients = fund_entity.employees if recipients.empty?
    recipients.find_each do |employee|
      KpiReportSubmittedNotifier.with(record: kpi_report, entity_id: fund_entity.id).deliver_later(employee)
    end
  end

  def extract_sorting_params
    q_param = params[:q]

    return [nil, nil, nil] unless q_param.is_a?(Hash) && q_param[:s]

    sort_field, sort_direction = params[:q][:s].split
    sort_field = nil unless sort_field == "entity_name"
    sort_direction = sort_direction&.downcase == 'desc' ? 'DESC' : 'ASC'
    sort_query = params[:q].delete(:s)

    [sort_field, sort_direction, sort_query]
  end

  # Pundit uses this method to determine the authorizing user.
  # When a signed magic link is used, @signed_id_user is the portco user extracted
  # from the token — use them instead of current_user (which is nil for unauthenticated requests).
  def pundit_user
    @signed_id_user || current_user
  end

  # Used by validate_upload and template: works for a persisted report (member route, incl. magic
  # link) or for the New page (collection route) where the report is built from the submitted form
  # fields and never saved.
  def set_kpi_report_for_validation
    if params[:id].present? || params[:signed_id].present?
      set_kpi_report
    else
      attrs = params[:kpi_report].present? ? params.require(:kpi_report).permit(:portfolio_company_id, :as_of, :period, :tag_list, :entity_id) : {}
      @kpi_report = KpiReport.new(attrs)
      # The report always belongs to the caller's entity, and the portfolio company must be one of
      # theirs — otherwise a fund user could point the check at another tenant's portco and read its
      # KPI mapping names / values back through the panel.
      @kpi_report.entity_id = current_user.entity_id
      @kpi_report.tag_list = "Actual" if @kpi_report.tag_list.blank?
      raise Pundit::NotAuthorizedError, "portfolio company does not belong to your entity" if @kpi_report.portfolio_company_id.present? && @kpi_report.portfolio_company&.entity_id != current_user.entity_id

      authorize @kpi_report
    end
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_kpi_report
    if params[:signed_id].present?
      find_by_signed_id_for_user(params[:signed_id])
      # Token was invalid or expired — render error inline so unauthenticated
      # users see a friendly message rather than being bounced to the sign-in page.
      unless @kpi_report
        render inline: <<~HTML, layout: false, status: :gone
          <!DOCTYPE html><html><body>
          <div style="font-family:sans-serif;max-width:600px;margin:4rem auto;padding:1rem">
            <h4>This link has expired or is invalid</h4>
            <p>Please contact your fund manager to request a new invitation link.</p>
          </div>
          </body></html>
        HTML
        return
      end
    end
    @kpi_report ||= KpiReport.find(params[:id]) if params[:id].present? && params[:id] != 'shared'

    authorize @kpi_report
    @bread_crumbs = { Kpis: kpi_reports_path }
    @bread_crumbs[@kpi_report.portfolio_company.investor_name.to_s] = investor_path(@kpi_report.portfolio_company) if @kpi_report.portfolio_company.present?
    @bread_crumbs[@kpi_report.as_of.to_s] = kpi_report_path(@kpi_report)
  end

  # Only allow a list of trusted parameters through.
  # Portco actors (magic link or logged-in portco user) may only change what their form shows:
  # notes, custom fields, the workbook and the upload flag. Report identity (portfolio company,
  # period, tag, entity), nested KPI rows and delete_kpis are fund-only (§2.8) — the browser used to
  # enforce this with disabled inputs, which is not enforcement.
  def kpi_report_params
    if action_name != 'create' && @kpi_report.present? && portco_actor?
      params.require(:kpi_report).permit(:notes, :upload_new_kpis, properties: {}, documents_attributes: Document::NESTED_ATTRIBUTES)
    else
      # entity_id is only settable on create — a report never moves tenant on update.
      permitted = %i[portfolio_company_id as_of tag_list notes user_id form_type_id delete_kpis update_existing_kpis upload_new_kpis period]
      permitted << :entity_id if action_name == 'create'
      params.require(:kpi_report).permit(*permitted, properties: {}, kpis_attributes: %i[id entity_id name period value display_value notes _destroy], documents_attributes: Document::NESTED_ATTRIBUTES)
    end
  end

  def search
    @q = KpiReport.ransack(params[:q])
    @kpi_reports = policy_scope(@q.result).includes(:entity, :portfolio_company)
    render json: @kpi_reports.map { |kr| { id: kr.id, text: kr.name } }
  end

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

    @kpi_reports = policy_scope(@q.result).includes(:entity, :portfolio_company, :kpis)

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
