class CapitalCallsController < ApplicationController
  include HasWorkflowable
  include ActionView::Helpers::TextHelper # pluralize, for the bulk-confirm flash

  before_action :set_capital_call, only: %i[show edit update destroy reminder approve unapprove notify generate_docs allocate_units recompute_fees
                                            confirm_reconciliation_deposit reassign_reconciliation_deposit undo_reconciliation_deposit
                                            confirm_all_exact_reconciliation_deposits]
  before_action :set_workflowable, only: [:show] # runs after set_capital_call so @capital_call is available

  # GET /capital_calls or /capital_calls.json
  def index
    @q = CapitalCall.ransack(params[:q])
    # Create the scope for the model
    @capital_calls = policy_scope(@q.result).includes(:fund)
    @capital_calls = CapitalCallSearch.perform(@capital_calls, current_user, params)
    @capital_calls = filter_params(
      @capital_calls,
      :fund_id,
      :import_upload_id
    )
    @capital_calls = @capital_calls.order(:call_date) if params[:order].blank?
    @fund = Fund.find(params[:fund_id]) if params[:fund_id].present?

    @pagy, @capital_calls = pagy(@capital_calls, limit: params[:per_page] || 10) if params[:all].blank?

    respond_to do |format|
      format.xlsx
      format.html { render :index }
      format.json
    end
  end

  def recompute_fees
    CapitalRemittancesRecomputeFeesJob.perform_later(@capital_call.id, current_user.id)
    redirect_to capital_call_path(@capital_call), notice: "Recompute Call job started."
  end

  # GET /capital_calls/1 or /capital_calls/1.json
  def show; end

  def generate_docs
    # custom field value can be kyc or folio
    CapitalRemittanceDocJob.perform_later(@capital_call.id, nil, current_user.id)
    redirect_to capital_call_path(@capital_call), notice: "Documentation generation started, please check back in a few mins. Each remittance will have the customized document attached"
  end

  def allocate_units
    FundUnitsJob.perform_later(@capital_call.id, "CapitalCall", @capital_call.name, current_user.id)
    redirect_to capital_call_path(@capital_call), notice: "Allocation process started, please check back in a few mins."
  end

  # GET /capital_calls/new
  def new
    @capital_call = CapitalCall.new(capital_call_params)
    @capital_call.entity_id = @capital_call.fund.entity_id
    @capital_call.due_date = Time.zone.today + 2.weeks
    @capital_call.call_date = Time.zone.today
    @bread_crumbs = { Funds: funds_path, "#{@capital_call.fund.name}": fund_path(@capital_call.fund), New: nil }
    authorize @capital_call
    setup_custom_fields(@capital_call)
  end

  # GET /capital_calls/1/edit
  def edit
    @bread_crumbs[:Edit] = nil
    setup_custom_fields(@capital_call)
  end

  # POST /capital_calls or /capital_calls.json
  def create
    @capital_call = CapitalCall.new(capital_call_params)
    authorize @capital_call

    respond_to do |format|
      if CapitalCallCreate.call(capital_call: @capital_call).success?
        format.html { redirect_to capital_call_url(@capital_call), notice: "Capital call was successfully created." }
        format.json { render :show, status: :created, location: @capital_call }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @capital_call.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /capital_calls/1 or /capital_calls/1.json
  def update
    @capital_call.assign_attributes(capital_call_params)
    respond_to do |format|
      if CapitalCallUpdate.call(capital_call: @capital_call, current_user:).success?
        format.html { redirect_to capital_call_url(@capital_call), notice: "Capital call was successfully updated." }
        format.json { render :show, status: :ok, location: @capital_call }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @capital_call.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /capital_calls/1 or /capital_calls/1.json
  def destroy
    @capital_call.destroy

    respond_to do |format|
      format.html { redirect_to fund_url(id: @capital_call.fund_id, tab: "capital-calls-tab"), notice: "Capital call was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def approve
    # Evaluate rules against the current (pre-approval) record state.
    # Blockers prevent approval entirely; warnings are surfaced in the success notice.
    rule_results = ValidationRuleEvaluator.call(record: @capital_call, entity: current_user.entity)

    blockers = rule_results.select(&:blocker?)
    if blockers.any?
      redirect_to capital_call_url(@capital_call), alert: blockers.map(&:message).join(" ")
      return
    end

    warnings = rule_results.select(&:warning?)

    @capital_call.approved = true
    @capital_call.approved_by_user = current_user

    # Skip model-level re-evaluation — already evaluated above
    result = WithValidationRules.skip { CapitalCallApprove.call(capital_call: @capital_call) }
    respond_to do |format|
      if result.success?
        notice = "Capital call was successfully approved."
        notice += " Warning: #{warnings.map(&:message).join(' ')}" if warnings.any?
        format.html { redirect_to capital_call_url(@capital_call), notice: notice }
        format.json { render :show, status: :created, location: @capital_call }
      else
        format.html { redirect_to capital_call_url(@capital_call), alert: "Call not approved: #{result[:errors]}" }
        format.json { render json: @capital_call.errors, status: :unprocessable_entity }
      end
    end
  end

  def unapprove
    result = CapitalCallUnapprove.call(capital_call: @capital_call)
    respond_to do |format|
      if result.success?
        format.html { redirect_to capital_call_url(@capital_call), notice: "Capital call was reverted to unapproved." }
        format.json { render :show, status: :ok, location: @capital_call }
      else
        format.html { redirect_to capital_call_url(@capital_call), alert: "Call not unapproved: #{result[:errors]}" }
        format.json { render json: @capital_call.errors, status: :unprocessable_entity }
      end
    end
  end

  def reminder
    @capital_call.reminder_capital_call
    redirect_to capital_call_url(@capital_call), notice: "Reminder sent for capital call."
  end

  def notify
    @capital_call.send_notification
    redirect_to capital_call_url(@capital_call), notice: "Notification sending process started, please check back in a few mins."
  end

  # Manually confirms a Probable/Needs review deposit from a RemittanceReconciliationAgent
  # report against the identity it already matched — creates the payment via the same
  # RemittanceDepositPaymentApplier the agent's own auto-apply step uses.
  def confirm_reconciliation_deposit
    report, deposit, idx = find_reconciliation_deposit
    return unless deposit

    remittance = @capital_call.capital_remittances.find_by(id: deposit["matched_remittance_id"])
    return redirect_to_reconciliation(alert: "No matched remittance to confirm — use Reassign instead") unless remittance

    outcome = RemittanceDepositPaymentApplier.call(deposit: deposit, capital_remittance: remittance, fund: @capital_call.fund)
    save_reconciliation_outcome(report, idx, outcome)
    redirect_to_reconciliation(notice: reconciliation_outcome_message(outcome))
  end

  # Manually assigns a No-match (or misidentified) deposit to a CapitalRemittance by Folio No
  # or Virtual Bank Account, the same two lookup fields ImportCapitalRemittancePayment accepts,
  # then applies it the same way confirm_reconciliation_deposit does.
  def reassign_reconciliation_deposit
    report, deposit, idx = find_reconciliation_deposit
    return unless deposit

    fund = @capital_call.fund
    # The panel sends one `lookup` value (a Folio No or a Virtual Bank Account); the explicit
    # folio_id / virtual_bank_account params are still accepted for API-style callers.
    lookup = params[:lookup].to_s.strip.presence
    folio_id = params[:folio_id].presence || lookup
    virtual_bank_account = params[:virtual_bank_account].presence || lookup
    return redirect_to_reconciliation(alert: "Enter a Folio No or Virtual Bank Account to reassign") if folio_id.blank? && virtual_bank_account.blank?

    commitment = fund.capital_commitments.where(folio_id: folio_id).first if folio_id
    commitment ||= fund.capital_commitments.where(virtual_bank_account: virtual_bank_account).first if virtual_bank_account
    return redirect_to_reconciliation(alert: "No commitment found for Folio No / Virtual Bank Account \"#{lookup || folio_id || virtual_bank_account}\"") unless commitment

    remittance = @capital_call.capital_remittances.find_by(capital_commitment: commitment)
    return redirect_to_reconciliation(alert: "No remittance for folio #{commitment.folio_id} under this call — generate remittances first") unless remittance

    outcome = RemittanceDepositPaymentApplier.call(deposit: deposit, capital_remittance: remittance, fund: fund)
    # Only record the new match when a payment actually exists for it (created just now, or
    # already existed) — on :error (e.g. "deposit has no amount"), leave matched_remittance_id
    # etc. untouched rather than recording a match that has no payment behind it.
    unless outcome[:status] == :error
      deposit["matched_remittance_id"] = remittance.id
      deposit["matched_commitment_id"] = remittance.capital_commitment_id
      deposit["matched_investor_name"] = remittance.investor_name
      deposit["identity_via"] = "manual_reassign"
    end
    save_reconciliation_outcome(report, idx, outcome)
    redirect_to_reconciliation(notice: reconciliation_outcome_message(outcome))
  end

  # Records a payment for every Exact-tier deposit on the report that has no payment outcome
  # yet — the bulk form of confirm_reconciliation_deposit, through the same applier, one
  # report save at the end. Rows in any other tier, and Exact rows already recorded (here or
  # on another call), are left exactly as they are.
  def confirm_all_exact_reconciliation_deposits
    report = SupportAgentReport.find_by(id: params[:report_id], owner: @capital_call)
    return redirect_to_reconciliation(alert: "Reconciliation report not found") unless report

    deposits = report.json_fields["deposits"] || []
    counts = Hash.new(0)
    errors = []
    deposits.each do |deposit|
      next unless deposit["tier"] == "exact" && deposit["payment_status"].blank? && deposit["matched_remittance_id"].present?

      remittance = @capital_call.capital_remittances.find_by(id: deposit["matched_remittance_id"])
      outcome = if remittance
                  RemittanceDepositPaymentApplier.call(deposit: deposit, capital_remittance: remittance, fund: @capital_call.fund)
                else
                  { status: :error, error: "matched remittance no longer exists" }
                end
      apply_outcome_to_deposit(deposit, outcome)
      counts[outcome[:status]] += 1
      errors << "#{deposit['matched_investor_name']}: #{outcome[:error]}" if outcome[:status] == :error
    end

    report.json_fields = report.json_fields.merge("deposits" => deposits)
    report.json_fields_will_change! # MySQL doesn't auto-detect JSON field changes
    report.save!

    summary = ["#{pluralize(counts[:created], 'payment')} recorded."]
    summary << "#{counts[:already_recorded]} already recorded." if counts[:already_recorded].positive?
    summary << "#{counts[:recorded_elsewhere]} skipped (recorded on another call)." if counts[:recorded_elsewhere].positive?
    if counts[:error].positive?
      redirect_to_reconciliation(alert: "#{summary.join(' ')} #{counts[:error]} failed: #{errors.join('; ')}")
    else
      redirect_to_reconciliation(notice: summary.join(" "))
    end
  end

  # Reverses a payment recorded from a reconciliation deposit (auto-applied Exact, or a manual
  # Confirm/Reassign) and clears the deposit's payment fields on the report so the row returns
  # to its review section instead of lingering under "Payments recorded" with a dead link.
  # Scoped so only a payment on one of THIS call's remittances can be undone here, and goes
  # through CapitalRemittancePaymentDestroy so check_units_before_deletion still applies —
  # a payment with units already allocated against it is refused with the model's own message.
  def undo_reconciliation_deposit
    report, deposit, idx = find_reconciliation_deposit
    return unless deposit

    payment = CapitalRemittancePayment.joins(:capital_remittance)
                                      .where(capital_remittances: { capital_call_id: @capital_call.id })
                                      .find_by(id: deposit["payment_id"])
    unless payment
      # Already gone (deleted from the remittance page, say) — just clear the stale pointer.
      save_reconciliation_undo(report, idx)
      return redirect_to_reconciliation(notice: "That payment no longer exists — the deposit is back in its review section.")
    end

    result = CapitalRemittancePaymentDestroy.wtf?(capital_remittance_payment: payment)
    if result.success?
      save_reconciliation_undo(report, idx)
      redirect_to_reconciliation(notice: "Payment removed. The deposit is back in its review section.")
    else
      redirect_to_reconciliation(alert: "Could not undo: #{payment.errors.full_messages.join(', ')}")
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_capital_call
    @capital_call = CapitalCall.find(params[:id])
    authorize @capital_call
    @bread_crumbs = { Funds: funds_path, "#{@capital_call.fund.name}": fund_path(@capital_call.fund),
                      "#{@capital_call}": capital_call_path(@capital_call) }
  end

  # Looks up the report + deposit a confirm/reassign request refers to, scoped to
  # @capital_call so a report_id/deposit_index for a different call can never be used here.
  # Returns [report, deposit, index] — deposit is nil (with the redirect already issued) if
  # anything doesn't resolve, so callers can just `return unless deposit`.
  def find_reconciliation_deposit
    report = SupportAgentReport.find_by(id: params[:report_id], owner: @capital_call)
    unless report
      redirect_to_reconciliation(alert: "Reconciliation report not found")
      return [nil, nil, nil]
    end

    unless params[:deposit_index].present? && params[:deposit_index].match?(/\A\d+\z/)
      redirect_to_reconciliation(alert: "Deposit not found in this report")
      return [nil, nil, nil]
    end

    idx = params[:deposit_index].to_i
    deposit = (report.json_fields["deposits"] || [])[idx]
    redirect_to_reconciliation(alert: "Deposit not found in this report") unless deposit

    [report, deposit, idx]
  end

  # Writes one applier outcome onto a deposit entry (in memory). payment_id only for a payment
  # under THIS call — a :recorded_elsewhere payment belongs to another call's remittance, and
  # a present payment_id is what makes the panel offer Undo.
  def apply_outcome_to_deposit(deposit, outcome)
    deposit["payment_id"] = outcome[:payment_id] if outcome[:payment_id] && outcome[:status] != :recorded_elsewhere
    deposit["reference_no"] = outcome[:reference_no] if outcome[:reference_no]
    deposit["payment_status"] = outcome[:status].to_s
    deposit["payment_error"] = outcome[:error] if outcome[:error]
  end

  # Persists the outcome of applying one deposit back onto the report's json_fields, in place.
  def save_reconciliation_outcome(report, idx, outcome)
    deposits = report.json_fields["deposits"]
    apply_outcome_to_deposit(deposits[idx], outcome)
    report.json_fields = report.json_fields.merge("deposits" => deposits)
    report.json_fields_will_change! # MySQL doesn't auto-detect JSON field changes
    report.save!
  end

  # Drops every payment-related key from one deposit entry after an Undo, so the panel's
  # "payment_id present" test puts the row back under Ready to confirm / Needs review / No match.
  def save_reconciliation_undo(report, idx)
    deposits = report.json_fields["deposits"]
    deposits[idx] = deposits[idx].except("payment_id", "reference_no", "payment_status", "payment_error")
    report.json_fields = report.json_fields.merge("deposits" => deposits)
    report.json_fields_will_change! # MySQL doesn't auto-detect JSON field changes
    report.save!
  end

  def reconciliation_outcome_message(outcome)
    case outcome[:status]
    when :created then "Payment recorded."
    when :already_recorded then "This deposit was already recorded as a payment."
    when :recorded_elsewhere then "Not recorded: this deposit was #{outcome[:error]}. Undo it there first if it belongs to this call."
    else "Could not record payment: #{outcome[:error]}"
    end
  end

  # Every reconciliation action (confirm / confirm all / reassign / undo) lands back on the
  # call with the Reconciliation tab already open — the `tabs` Stimulus controller reads
  # ?tab=<pane id> — so the reviewer never has to re-open it after each row.
  def redirect_to_reconciliation(notice: nil, alert: nil)
    redirect_to capital_call_url(@capital_call, tab: "reconciliation-tab"), notice: notice, alert: alert
  end

  # Only allow a list of trusted parameters through.
  def capital_call_params
    params["capital_call"]["fund_closes"] = params["capital_call"]["close_percentages"].select { |_, percentage| percentage.to_d.positive? }.keys if params["capital_call"]["close_percentages"].present? && params["capital_call"]["fund_closes"].blank?
    if current_user.support?
      params.require(:capital_call).permit(:entity_id, :fund_id, :form_type_id, :name, :percentage_called, :add_fees, :generate_remittances, :due_date, :call_date, :notes, :call_basis, :amount_to_be_called, :send_call_notice_flag, :send_payment_notification_flag, fund_closes: [], unit_prices: {}, properties: {}, close_percentages: {}, call_fees_attributes: CallFee::NESTED_ATTRIBUTES_WITH_FORMULA, documents_attributes: Document::NESTED_ATTRIBUTES, fee_formula_ids: [])
    else
      params.require(:capital_call).permit(:entity_id, :fund_id, :form_type_id, :name, :percentage_called, :add_fees, :generate_remittances, :due_date, :call_date, :notes, :call_basis, :amount_to_be_called, :send_call_notice_flag, :send_payment_notification_flag, fund_closes: [], unit_prices: {}, properties: {}, close_percentages: {}, call_fees_attributes: CallFee::NESTED_ATTRIBUTES, documents_attributes: Document::NESTED_ATTRIBUTES, fee_formula_ids: [])
    end
  end
end
