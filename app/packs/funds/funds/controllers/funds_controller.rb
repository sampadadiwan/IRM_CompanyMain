class FundsController < ApplicationController
  helper CapitalCommitmentDashboardHelper
  helper CapitalCallDashboardHelper
  helper CapitalDistributionDashboardHelper
  helper CapitalRemittanceDashboardHelper
  helper AggregatePortfolioInvestmentDashboardHelper
  helper AggregatePortfolioInvestmentsHelper
  helper PortfolioHelper
  helper FundStatisticsHelper
  helper LpFlowHelper
  before_action :set_fund, only: %i[show dashboard edit update destroy last report generate_fund_ratios allocate_form allocate copy_formulas export generate_documentation check_access_rights delete_all generate_tracking_numbers show_email_list trigger_adhoc_notification analytics]

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
    @fund = Fund.new
    @fund.entity_id = current_user.entity_id
    @fund.currency = @fund.entity.currency
    setup_custom_fields(@fund)
    authorize(@fund)
  end

  # GET /funds/1/edit
  def edit
    @bread_crumbs[:Edit] = nil
    setup_custom_fields(@fund)
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
    @fund = Fund.new(fund_params)
    # SECURITY (finding H6): pin the tenant key to the acting user's entity — never trust a
    # client-supplied entity_id (it is not permitted in fund_params). Support users create for a
    # client entity by first switching into it (SupportClientMapping#switch sets their entity_id).
    @fund.entity_id = current_user.entity_id
    authorize(@fund)
    respond_to do |format|
      if @fund.save
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
    # SECURITY: the edit form disables the tracking_currency select for non-support users, but
    # that's UI-only - fund_params still permits it, so a direct PATCH could otherwise bypass
    # the lock. Re-check server-side (see FundPolicy#update_tracking_currency?).
    authorize(@fund, :update_tracking_currency?) if tracking_currency_change_requested?

    respond_to do |format|
      if @fund.update(fund_params)
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
    @fund.destroy

    respond_to do |format|
      format.html { redirect_to funds_url, notice: "Fund was successfully destroyed." }
      format.json { head :no_content }
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
    TrackingCurrencyJob.perform_later(fund_id: @fund.id, user_id: current_user.id, force: force)
    redirect_to fund_path(@fund), notice: "Tracking currency update started, please check back in a few mins."
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
    @fund.adhoc_notification(@custom_notification.id, commitment_ids:, investor_kyc_ids:, triggered_by_user_id: current_user.id)
    redirect_back_or_to(fund_path(@fund), notice: "Notification trigger started for #{@fund.name}.")
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_fund
    @fund = Fund.with_snapshots.find(params[:id])
    authorize(@fund)
    @bread_crumbs = { Funds: funds_path, "#{@fund.name}": fund_path(@fund) }
  end

  def tracking_currency_change_requested?
    fund_params.key?(:tracking_currency) &&
      fund_params[:tracking_currency].presence != @fund.tracking_currency
  end

  # Only allow a list of trusted parameters through.
  def fund_params
    # SECURITY (finding H6): :entity_id is intentionally NOT permitted. The tenant key is set
    # server-side from current_user in #create and can never be changed on #update, so a fund
    # cannot be created in — or relocated to — another entity via mass assignment.
    params.require(:fund).permit(:name, :category, :committed_amount, :details, :lp_commentary,
                                 :collected_amount, :commitment_doc_list, :master_fund_id,
                                 :tag_list, :show_valuations, :show_fund_ratios,
                                 :currency, :unit_types, :units_allocation_engine, :form_type_id, :first_close_date, :show_portfolios, :show_fund_units, :last_close_date, :tracking_currency,
                                 :esign_emails, :enable_ai_commentary, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
