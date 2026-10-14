class FundsController < ApplicationController
  include EvergreenSettingParams

  # evergreen-fund-on-create ②: the open-ended steps of New Fund use the evergreen settings helpers
  helper EvergreenSettingsHelper
  helper CapitalCommitmentDashboardHelper
  helper CapitalCallDashboardHelper
  helper CapitalDistributionDashboardHelper
  helper CapitalRemittanceDashboardHelper
  helper AggregatePortfolioInvestmentDashboardHelper
  helper AggregatePortfolioInvestmentsHelper
  helper PortfolioHelper
  helper FundStatisticsHelper
  helper LpFlowHelper
  before_action :set_fund, only: %i[show dashboard edit update destroy last report generate_fund_ratios allocate_form allocate copy_formulas export generate_documentation check_access_rights delete_all generate_tracking_numbers change_tracking_currency retry_tracking_currency_change show_email_list trigger_adhoc_notification analytics]

  # GET /funds/1/analytics
  def analytics
    case params[:type]
    when "CapitalCall"
      render "/capital_calls/analytics_content", layout: false
    when "CapitalDistribution"
      render "/capital_distributions/analytics_content", layout: false
    when "CapitalRemittance"
      # SECURITY (finding M7): scope through the authorized @fund so a capital_call_id from another
      # fund/tenant cannot be loaded (raises RecordNotFound → handled).
      @owner = params[:capital_call_id].present? ? @fund.capital_calls.find(params[:capital_call_id]) : @fund
      render "/capital_remittances/analytics_content", layout: false
    when "AggregatePortfolioInvestment"
      render "/aggregate_portfolio_investments/analytics_content", layout: false
    when "LPFlow"
      render "/lp_flow/analytics_content", layout: false
    when "FundRatio"
      render "/fund_ratios/analytics_content", layout: false
    else
      render "/capital_commitments/analytics_content", layout: false
    end
  end

  # GET /funds or /funds.json
  def index
    @bread_crumbs = { Funds: funds_path }
    # Serves both Fund and FundSnapshot
    @funds = ransack_with_snapshot.includes(:entity)
    @funds = @funds.where(entity_id: params[:entity_id]) if params[:entity_id].present?
    @funds = @funds.where("funds.tag_list LIKE ?", "%#{params[:tag]}%") if params[:tag].present?
    @funds = @funds.includes(:fund_ratios) if params[:card].present?
    @pagy, @funds = pagy(@funds) if params[:card].present? || params[:all].present?
    # Closed-ended / Open-ended badge per fund, without a query per row (evergreen-fund-on-create)
    # (a snapshot row has its own id; its live fund is orignal_id — WithSnapshot)
    @evergreen_fund_ids = EvergreenFundSetting.where(fund_id: @funds.map { |f| f.orignal_id || f.id })
                                              .distinct.pluck(:fund_id).to_set
  end

  def export
    export_file = FundXlExport.new.generate(@fund)
    send_file export_file, type: "application/vnd.ms-excel", filename: "#{@fund.name}.xlsx", stream: false
    # File.delete(export_file)
  end

  # Simple path segments only (letters/digits joined by "_" or "/"); no ".." or absolute paths.
  SAFE_REPORT_TEMPLATE = %r{\A[a-z0-9]+(?:[_/][a-z0-9]+)*\z}i

  def report
    if params[:report].present? && params[:report] == "generate_reports"
      XlReportJob.perform_later(@fund.id, current_user.id)
      redirect_to fund_path(@fund), notice: "Report generation started, please check back in a few mins. Your report will be generated in the 'Fund Reports' folder."
    else
      # SECURITY (finding M8): confine params[:report] to a safe template name so a crafted value
      # cannot traverse out of funds/ or render an unintended template.
      return head(:not_found) unless params[:report].to_s.match?(SAFE_REPORT_TEMPLATE)

      render "/funds/#{params[:report]}"
    end
  end

  def check_access_rights
    if params[:create_missing] == "true"
      FundAccessRightsJob.perform_later(@fund.id, true, current_user.id)
      redirect_to fund_path(@fund), notice: "AccessRights creation started, please check back in a few mins"
    else
      cars = @fund.check_access_rights
      redirect_to fund_path(@fund), notice: "Missing Access Rights #{cars.length} : #{cars}"
    end
  end

  # GET /funds/1 or /funds/1.json
  def show; end

  def dashboard
    @dashboard_name = params[:dashboard_name] || "Fund Dashboard"
    @dashboard_names, @name = resolve_dashboard(@dashboard_name, params[:name])
    @favorite_title = "#{@fund.name} Dashboard"
    @favorite_url = dashboard_fund_path(id: @fund.id)
    respond_to do |format|
      format.html
      format.pdf do
        FerrumPdf.browser(timeout: 180)
        pdf = render_pdf
        send_data pdf, disposition: :inline, filename: "#{@fund.name}.pdf"
      end
    end
  end

  # GET /funds/new
  def new
    @bread_crumbs = { Funds: funds_path, New: nil }
    # Entity first, so the new fund starts with the entity's feature defaults (E3)
    @fund = Fund.new(entity_id: current_user.entity_id)
    @fund.currency = @fund.entity.currency
    setup_custom_fields(@fund)
    authorize(@fund)
    # evergreen-fund-on-create ①: blank evergreen terms for the open-ended steps of the wizard
    @evergreen_setting = new_evergreen_setting if open_ended_available?
  end

  # GET /funds/1/edit
  def edit
    @bread_crumbs[:Edit] = nil
    setup_custom_fields(@fund)
    # evergreen-fund-on-create: an open-ended fund's edit carries on into its open-ended terms, as on create
    @evergreen_setting = @fund.evergreen_fund_setting if @fund.evergreen?
  end

  def last
    cc = nil
    cc = @fund.capital_calls.order(due_date: :asc).last if params[:entry] == "CapitalCall"
    if cc
      redirect_to capital_call_path(id: cc.id, tab: "remittances-tab")
    else
      redirect_to fund_path(id: @fund.id, tab: "capital-calls-tab")
    end
  end

  # POST /funds or /funds.json
  def create
    # SECURITY (finding H6): pin the tenant key to the acting user's entity — never trust a
    # client-supplied entity_id (it is not permitted in fund_params). Support users create for a
    # client entity by first switching into it (SupportClientMapping#switch sets their entity_id).
    # Set before the other attributes so the new fund starts with the entity's feature defaults (E3).
    @fund = Fund.new(entity_id: current_user.entity_id)
    @fund.assign_attributes(fund_params)
    authorize(@fund)
    # evergreen-fund-on-create H1: an open-ended fund is created with its evergreen terms, or not at all
    return create_open_ended if open_ended_requested?

    respond_to do |format|
      if assign_feature_params && @fund.save
        format.html { redirect_to fund_url(@fund), notice: "Fund was successfully created." }
        format.json { render :show, status: :created, location: @fund }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @fund.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /funds/1 or /funds/1.json
  def update
    # The edit form disables tracking_currency once the fund exists, but fund_params still permits
    # it (it is set on #create), so a direct PATCH could otherwise change it. A plain update would
    # only relabel the stored tracking amounts, never convert them - refuse it for everyone,
    # support included, and point at the change that does the conversion (ChangeTrackingCurrencyJob).
    if tracking_currency_change_requested?
      message = "The tracking currency cannot be edited here. Support can change it from " \
                "Actions > Change Tracking Currency, which also rebuilds the tracking amounts."
      respond_to do |format|
        format.html { redirect_to fund_path(@fund), alert: message }
        format.json { render json: { tracking_currency: [message] }, status: :unprocessable_entity }
      end
      return
    end

    # An open-ended fund's edit also saves its open-ended terms — fund and terms together, or neither
    return update_open_ended if @fund.evergreen? && params[:evergreen_fund_setting].present?

    respond_to do |format|
      @fund.assign_attributes(fund_params)
      if assign_feature_params && @fund.save
        format.html { redirect_to fund_url(@fund), notice: "Fund was successfully updated." }
        format.json { render :show, status: :ok, location: @fund }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @fund.errors, status: :unprocessable_entity }
      end
    end
  end

  def delete_all
    delete_class_name = params[:type]
    FundDeleteAllJob.perform_later(@fund.id, delete_class_name, current_user.id)
    redirect_to fund_path(@fund), notice: "Deletion of #{delete_class_name} started, please check back in a few mins"
  end

  def generate_fund_ratios
    if params[:end_date].present?
      generate_for_commitments = params[:generate_for_commitments] == "1"

      # Build a throwaway FundRatio record so blockers can be evaluated before the job is enqueued.
      # Only the "fund" type has a meaningful end_date to validate; cross-fund/cross-portfolio
      # share the same form field so we check it universally.
      temp_ratio = FundRatio.new(entity_id: @fund.entity_id, fund_id: @fund.id,
                                 end_date: Date.local_parse(params[:end_date]))
      blockers = ValidationRuleEvaluator.call(record: temp_ratio, entity: current_user.entity)
                                        .select(&:blocker?)
      if blockers.any?
        flash[:alert] = blockers.map(&:message).join(" ")
        redirect_back_or_to(generate_fund_ratios_fund_path(@fund)) and return
      end

      case params[:type]
      when "fund"
        FundRatiosJob.perform_later(@fund.id, nil, Date.local_parse(params[:end_date]), current_user.id, generate_for_commitments, return_cash_flows: params[:return_cash_flows] == "1")

      when "cross-fund", "cross-portfolio"
        # scenario param removed — FundRatioRun.name is now the fingerprint derived from inputs.
        fund_ids = params[:fund_ids].nil? ? policy_scope(Fund).pluck(:id) : params[:fund_ids]
        FundRatiosScenarioJob.set(wait: 3.seconds).perform_later(
          @fund.id,
          Date.local_parse(params[:end_date]),
          current_user.id,
          fund_ids: fund_ids,
          portfolio_company_ids: params[:portfolio_company_ids],
          portfolio_companies_tags: params[:portfolio_companies_tags],
          portfolio_companies_sectors: params[:portfolio_companies_sectors],
          currency: params[:currency],
          type: params[:type]
        )
      else
        # Invalid type, handle accordingly
        notice = "Invalid type specified for fund ratios generation."
      end

      notice ||= "Fund ratios calculations in progress, please check back in a few mins."
      redirect_to fund_path(@fund, tab: "fund-ratios-tab"), notice: notice
    else
      render "generate_fund_ratios"
    end
  end

  def generate_documentation
    CapitalCommitmentDocJob.perform_later(@fund.id, nil, current_user.id, template_id: params[:template_id])
    redirect_to fund_path(@fund), notice: "Documentation generation started, please check back in a few mins."
  end

  # DELETE /funds/1 or /funds/1.json
  def destroy
    # allocation_run_templates is dependent: :restrict_with_error, so destroy can return
    # false without raising (e.g. the fund still has a saved allocation run template).
    # The old code ignored the return value and always reported success.
    if @fund.destroy
      respond_to do |format|
        format.html { redirect_to funds_url, notice: "Fund was successfully destroyed." }
        format.json { head :no_content }
      end
    else
      respond_to do |format|
        format.html { redirect_to fund_path(@fund), alert: @fund.errors.full_messages.join(", ") }
        format.json { render json: @fund.errors, status: :unprocessable_entity }
      end
    end
  end

  def allocate_form; end

  def allocate
    start_date = nil
    end_date = nil

    begin
      start_date = Date.local_parse(params[:start_date])
      end_date = Date.local_parse(params[:end_date])
      template_id = params[:template_id]
      generate_soa = %w[1 true].include?(params[:generate_soa].to_s)
      statement_for = params[:statement_for]
      fund_ratios = %w[1 true].include?(params[:fund_ratios].to_s)
      run_allocations = %w[1 true].include?(params[:run_allocations].to_s)
      explain = %w[1 true].include?(params[:explain].to_s)
      sample = %w[1 true].include?(params[:sample].to_s)
      rule_for = params[:rule_for]
      tag_list = nil
      tag_list = params[:tag_list].join(",") if params[:tag_list].present? && params[:tag_list].is_a?(Array)
      user_id = current_user.id

      if params["run_allocations"]
        existing_allocation_run = AllocationRun.locked_and_overlapping(@fund.id, start_date, end_date)
        if existing_allocation_run
          flash[:alert] = "This AllocationRun already exists for the specified period and is locked. Start Date - #{existing_allocation_run.start_date.strftime('%d-%m-%Y')} and End Date - #{existing_allocation_run.end_date.strftime('%d-%m-%Y')}."
          redirect_back_or_to(root_path) and return
        end
      end
      # Decision 10(c) of the allocation run groups design: a fund that a running group is
      # using, or has yet to reach, must not be touched by a manual run — overlapping runs
      # produce entries in an undefined order.
      if AllocationGroupRun.fund_busy?(@fund.id)
        flash[:alert] = "An allocation run group is currently running on this fund. Wait for it to finish before starting a manual run."
        redirect_back_or_to(root_path) and return
      end
      # A run starting while formulas are being switched could load formulas from before the write and
      # the incremental flag from after it (FundFormulaOperation).
      if FundAllocationActivity.formula_operation_applying?(@fund)
        flash[:alert] = "The fund's formulas are being changed (Actions > Incremental allocation). Wait for that to finish before starting a run."
        redirect_back_or_to(root_path) and return
      end
      # Allocation writes tracking amounts; mid-change they would be in whichever currency is saved.
      if @fund.tracking_currency_change_pending?
        flash[:alert] = "The fund's tracking currency is being changed. Wait for that to finish before starting a run."
        redirect_back_or_to(root_path) and return
      end

      template_name = template_id ? Document.find(template_id).name : nil

      # Build a temporary (unsaved) record so blocker rules can be evaluated.
      # If any blockers fire the run is halted regardless of force_save — blockers
      # are always enforced server-side. Warnings are handled by the Stimulus modal.
      temp_run = AllocationRun.new(entity_id: @fund.entity_id, fund_id: @fund.id,
                                   start_date:, end_date:, locked: false)
      blockers = ValidationRuleEvaluator.call(record: temp_run, entity: current_user.entity)
                                        .select(&:blocker?)
      if blockers.any?
        flash[:alert] = blockers.map(&:message).join(" ")
        redirect_back_or_to(allocate_form_fund_path(@fund)) and return
      end

      # Blocker check above confirmed no rules fire — skip the model-level re-evaluation
      # to avoid running the rule engine twice on the same record.
      allocation_run = WithValidationRules.skip do
        AllocationRun.create!(entity_id: @fund.entity_id, fund_id: @fund.id, start_date:, end_date:, run_allocations:, generate_soa:, statement_for:, template_name:, fund_ratios:, user_id: current_user.id, rule_for:, tag_list:)
      end
    rescue StandardError => e
      Rails.logger.debug { "allocate: Errors #{e.message}" }
      Rails.logger.debug "allocate: Dates not sent properly"
      redirect_back_or_to(root_path, alert: "Please specify the start_date and end_date for allocation.")
      return
    end

    if start_date.present? && end_date.present?
      AccountEntryAllocationJob.perform_later(@fund.id, start_date, end_date, rule_for:, tag_list:, run_allocations:, explain:, user_id:, generate_soa:, statement_for:, template_id:, fund_ratios:, sample:, allocation_run_id: allocation_run.id)
      redirect_to(@fund, notice: "Fund account entries allocation in progress. Please wait for a few minutes and refresh the page.")
    else
      redirect_back_or_to(root_path, alert: "Please specify the start_date and end_date for allocation.")
    end
  end

  def copy_formulas
    from_fund = Fund.find(params[:from_fund_id])
    # SECURITY (finding H5): the SOURCE fund was previously loaded without authorization, letting
    # its formulas be copied out. Authorizing show? enforces exactly the intended boundary:
    #   - regular users may only copy from a fund in their own entity (permissioned_employee?
    #     requires belongs_to_entity? for non-support users), and
    #   - support users may copy cross-entity (the accepted support fallthrough — see H1).
    # The destination (@fund) is already authorized in set_fund via copy_formulas? (update?).
    authorize from_fund, :show?

    from_fund.fund_formulas.order(sequence: :asc).each do |ff|
      new_ff = ff.dup
      new_ff.fund = @fund
      new_ff.entity_id = @fund.entity_id
      new_ff.save
    end

    redirect_back_or_to(fund_path(@fund), notice: "Formulas copied successfully.")
  end

  def generate_tracking_numbers
    force = params[:force].to_s.downcase == "true"
    authorize(@fund, :force_generate_tracking_numbers?) if force
    # TrackingCurrencyJob skips a fund mid-change anyway; say so rather than report a start.
    if @fund.tracking_currency_change_pending?
      redirect_to fund_path(@fund), alert: "A tracking currency change is pending on this fund; it rebuilds the tracking numbers itself."
      return
    end

    TrackingCurrencyJob.perform_later(fund_id: @fund.id, user_id: current_user.id, force: force)
    redirect_to fund_path(@fund), notice: "Tracking currency update started, please check back in a few mins."
  end

  # GET  - the change form (current value, target currency, consequences, typed confirmation).
  # POST - checks the request, claims the fund and enqueues ChangeTrackingCurrencyJob, which checks
  #        exchange rates, saves the currency and rebuilds every tracking amount and fund ratio.
  # Support only (FundPolicy#change_tracking_currency?).
  def change_tracking_currency
    return render(:change_tracking_currency) unless request.post?

    new_currency = params[:new_tracking_currency].presence
    error = tracking_currency_change_error(new_currency)
    if error
      flash.now[:alert] = error
      render :change_tracking_currency, status: :unprocessable_entity
      return
    end

    begin
      ChangeTrackingCurrencyJob.perform_later(@fund.id, current_user.id, @fund.tracking_currency_change_token)
    rescue StandardError
      # Claimed but never queued: nothing would ever release the fund, so let go before reporting.
      @fund.release_tracking_currency_change!
      raise
    end
    redirect_to fund_path(@fund), notice: "Tracking currency change to #{new_currency || 'none'} started. " \
                                          "You will be notified when the tracking amounts have been rebuilt."
  end

  # Re-runs a ChangeTrackingCurrencyJob that raised partway, or whose worker died (stale), to the
  # same target currency.
  def retry_tracking_currency_change
    if @fund.reclaim_failed_tracking_currency_change!
      begin
        ChangeTrackingCurrencyJob.perform_later(@fund.id, current_user.id, @fund.tracking_currency_change_token)
      rescue StandardError
        # Back to failed, so the Retry button is offered again rather than a change that never runs.
        @fund.mark_tracking_currency_change_failed!
        raise
      end
      redirect_to fund_path(@fund), notice: "Tracking currency change restarted."
    else
      redirect_to fund_path(@fund), alert: "There is no failed tracking currency change to retry on this fund."
    end
  end

  def show_email_list
    # SECURITY (finding M7): load these through the authorized @fund's associations so a record id
    # belonging to another fund/tenant cannot be surfaced (raises RecordNotFound → handled).
    @capital_call = @fund.capital_calls.find(params[:capital_call_id]) if params[:capital_call_id].present?
    @capital_distribution = @fund.capital_distributions.find(params[:capital_distribution_id]) if params[:capital_distribution_id].present?
    @capital_distribution_payment = @fund.capital_distribution_payments.find(params[:capital_distribution_payment_id]) if params[:capital_distribution_payment_id].present?
  end

  def trigger_adhoc_notification
    # SECURITY (finding M7): a CustomNotification belongs to an entity; scope the lookup to the
    # authorized @fund's entity so a template from another tenant cannot be triggered.
    @custom_notification = CustomNotification.where(entity_id: @fund.entity_id).find(params[:custom_notification_id])
    commitment_ids = params[:commitment_ids].presence # nil when blank → all commitments
    # Only populated by the "Select Investor KYCs to Notify" picker, which the view only
    # renders when @custom_notification.email_method == "adhoc_kyc_notification" — harmless
    # to always pass through since FundNotificationJob ignores whichever of the two doesn't apply.
    investor_kyc_ids = params[:investor_kyc_ids].presence

    # Documents attached to the notification itself go to EVERY recipient, so if one of them
    # breaches the size limit this send cannot succeed for anyone - and that is knowable right
    # here, synchronously. FundNotificationJob preflights the rest (attachment_names resolves
    # per recipient and needs the recipient list), but its verdict only reaches the operator as
    # an email minutes later. Saying so now, on the page they are already looking at, is the
    # difference between a caught mistake and a mystery.
    oversize = NotificationAttachmentPreflight.error_message(
      @custom_notification.documents.to_a,
      context: "Cannot send \"#{@custom_notification.subject}\""
    )
    return redirect_back_or_to(fund_path(@fund), alert: oversize) if oversize

    @fund.adhoc_notification(@custom_notification.id, commitment_ids:, investor_kyc_ids:, triggered_by_user_id: current_user.id)
    redirect_back_or_to(fund_path(@fund), notice: "Notification trigger started for #{@fund.name}.")
  end

  private

  # ---- evergreen-fund-on-create: choose closed-ended or open-ended on New Fund ----

  # The Fund type choice is offered only to companies with evergreen funds and units switched on (E1)
  def open_ended_available?
    perms = current_user.entity.permissions
    perms.enable_evergreen_funds? && perms.enable_units?
  end

  # E1, E4: a sent value is ignored unless the company has evergreen; Closed-ended is the default
  def open_ended_requested?
    params[:fund_type] == "open_ended" && open_ended_available?
  end

  def new_evergreen_setting(attrs = {})
    setting = EvergreenFundSetting.new(entity_id: current_user.entity_id)
    setting.assign_attributes(attrs.except(:class_terms))
    # Re-show the class cards typed before a failed create (X2), in the order of the fund's unit types
    Array(attrs[:class_terms]).each { |c| setting.evergreen_class_terms.build(c.except(:id, :early_redemption_fee)) }
    setting
  end

  # Edit of an open-ended fund: the fund's fields and its open-ended terms in one transaction. Terms change
  # forward only, as on Evergreen Settings: open dealing dates follow a changed payment timing.
  def update_open_ended
    setting = @fund.evergreen_fund_setting
    authorize setting, :update?
    attrs = evergreen_setting_attributes_for_update
    saved = false
    ActiveRecord::Base.transaction do
      saved = @fund.update(fund_params) && setting.update(attrs)
      raise ActiveRecord::Rollback unless saved
    end
    if saved
      @fund.dealing_dates.where(status: "open").where.not(payment_timing: setting.payment_timing)
           .update_all(payment_timing: setting.payment_timing, updated_at: Time.current)
      redirect_to fund_url(@fund), notice: "Fund was successfully updated."
    else
      render_open_ended_edit(setting, @fund.errors.full_messages + setting.errors.full_messages)
    end
  rescue EvergreenFormParsing::BadDates => e
    render_open_ended_edit(@fund.evergreen_fund_setting, [e.message])
  end

  def render_open_ended_edit(setting, errors)
    @evergreen_setting = setting
    @evergreen_errors = errors
    setup_custom_fields(@fund)
    render :edit, status: :unprocessable_entity, formats: [:html]
  end

  # H1, X1–X3: fund and terms together; any error shows the wizard again with every value kept
  def create_open_ended
    setting_params = evergreen_setting_attributes
    result = EvergreenFundCreate.call(fund: @fund, setting_params:, current_user:)
    if result.success?
      redirect_to fund_url(@fund), notice: "#{@fund.name} created as an open-ended fund"
    else
      @evergreen_setting = new_evergreen_setting(setting_params)
      @evergreen_errors = Array(result[:errors])
      @fund_type = "open_ended"
      setup_custom_fields(@fund)
      # The form posts as a Turbo request: answer with HTML, or Turbo ignores the page and no error shows
      render :new, status: :unprocessable_entity, formats: [:html]
    end
  rescue EvergreenFormParsing::BadDates => e
    @evergreen_setting = new_evergreen_setting
    @evergreen_errors = [e.message]
    @fund_type = "open_ended"
    setup_custom_fields(@fund)
    render :new, status: :unprocessable_entity, formats: [:html]
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_fund
    @fund = Fund.with_snapshots.find(params[:id])
    authorize(@fund)
    @bread_crumbs = { Funds: funds_path, "#{@fund.name}": fund_path(@fund) }
  end

  def tracking_currency_change_requested?
    fund_params.key?(:tracking_currency) &&
      fund_params[:tracking_currency].presence != @fund.tracking_currency.presence
  end

  # Why a tracking currency change cannot start, or nil after claiming the fund for it. The claim
  # is last, so a rejected request never leaves the fund marked as changing.
  # @param new_currency [String, nil] nil removes the tracking currency
  def tracking_currency_change_error(new_currency)
    return "Type the fund name exactly to confirm." if params[:confirm_fund_name].to_s.strip != @fund.name
    return "#{new_currency} is not a currency this entity has exchange rates for." if new_currency && @fund.tracking_currency_options.exclude?(new_currency)
    return "The tracking currency is already #{new_currency || 'not set'}." if new_currency == @fund.tracking_currency.presence

    # An allocation run writes tracking amounts as it creates account entries; one running under the
    # change would write them at whichever currency is saved at that moment.
    busy = FundAllocationActivity.new(@fund).reason
    return busy if busy
    return "A tracking currency change is already pending on this fund." unless @fund.claim_tracking_currency_change!(new_currency)

    nil
  end

  # Only allow a list of trusted parameters through.
  def fund_params
    # SECURITY (finding H6): :entity_id is intentionally NOT permitted. The tenant key is set
    # server-side from current_user in #create and can never be changed on #update, so a fund
    # cannot be created in — or relocated to — another entity via mass assignment.
    params.require(:fund).permit(:name, :category, :committed_amount, :details, :lp_commentary,
                                 :collected_amount, :commitment_doc_list, :master_fund_id,
                                 :tag_list,
                                 :currency, :unit_types, :units_allocation_engine, :form_type_id, :first_close_date, :last_close_date, :tracking_currency,
                                 :esign_emails,
                                 # Legacy switch names still accepted from JSON clients; they write the fund features
                                 *FundEnabled::LEGACY_FLAGS.excluding(:editable_formulas),
                                 documents_attributes: Document::NESTED_ATTRIBUTES, properties: {},
                                 market_data_setting_attributes: %i[id max_rate_age_days max_price_age_days price_move_threshold_pct])
  end

  # Fund feature switches (FundEnabled) from the Features section. FundFeatureGuard keeps flags the
  # form doesn't manage and refuses a market-data flag whose entity feature is off.
  # Worked examples H3, X3 — openspec/changes/fund-market-data/business-rules.md
  def assign_feature_params
    return true unless params[:fund]&.key?(:features)

    result = FundFeatureGuard.call(@fund, params[:fund][:features])
    if result.refused.any?
      # X3 — Error case: direct submission of an unavailable switch
      @fund.errors.add(:features, "#{result.refused.map { |f| FundFeatureGuard.label(f) }.to_sentence} is not available for this fund")
      return false
    end

    @fund.features = result.features
    true
  end
end
