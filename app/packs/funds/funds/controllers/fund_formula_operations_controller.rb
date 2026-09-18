# Support-only operations on a fund's formulas, from the fund formulas page's Actions menu:
#   index        Incremental allocation: the fund's state, recommended steps, history, and preview buttons
#   suggestions  Suggest run checks: opens the fund's latest suggestion set (or offers to generate one)
#   create       starts a preview (FundFormulaOperationJob) — one in progress per fund
#   show         a preview or suggestion set; reloads itself while the job runs
#   apply        applies a previewed plan, refused while the fund is busy
#   add_suggestions / download_suggestions  the selected suggestions, added as formulas or as an importable xlsx
#
# See openspec/changes/incremental-allocation-ui.
class FundFormulaOperationsController < ApplicationController
  before_action :set_fund, only: %i[index suggestions create]
  before_action :set_operation, only: %i[show apply add_suggestions download_suggestions]
  after_action :verify_authorized

  # GET /fund_formula_operations?fund_id=
  def index
    authorize FundFormulaOperation
    @operations = policy_scope(FundFormulaOperation).where(fund: @fund, operation: FundFormulaOperation::APPLICABLE)
                                                    .recent.includes(:requested_by, :applied_by)
    @steps = IncrementalAllocationSteps.new(@fund)
    @bread_crumbs = breadcrumbs("Incremental allocation")
  end

  # GET /fund_formula_operations/suggestions?fund_id=
  def suggestions
    authorize FundFormulaOperation
    latest = policy_scope(FundFormulaOperation).where(fund: @fund, operation: "suggest_checks").recent.first
    return redirect_to(fund_formula_operation_path(latest)) if latest

    @bread_crumbs = breadcrumbs("Suggest run checks")
  end

  # POST /fund_formula_operations  fund_id, operation, date (reseed), ai (suggestions)
  def create
    authorize FundFormulaOperation.new(entity_id: @fund.entity_id, fund: @fund)
    operation = FundFormulaOperation.start!(fund: @fund, operation: params[:operation], user: current_user, params: operation_params)
    return redirect_to(fund_formula_operation_path(operation), alert: "#{operation} is still #{operation.status} on this fund. Wait for it to finish.") unless operation.new_preview?

    redirect_to fund_formula_operation_path(operation), notice: "#{operation.suggestions? ? 'Generating suggestions' : 'Preparing the preview'}. This page updates when it is ready."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back_or_to(fund_formulas_path(fund_id: @fund.id), alert: e.record.errors.full_messages.to_sentence)
  rescue Date::Error
    redirect_back_or_to(fund_formula_operations_path(fund_id: @fund.id), alert: "Enter a valid date for the starting values.")
  end

  # GET /fund_formula_operations/:id
  def show
    authorize @operation
    @fund = @operation.fund
    @bread_crumbs = breadcrumbs(@operation.suggestions? ? "Suggest run checks" : "Incremental allocation", @operation.to_s)
    @addable_keys = @operation.suggestion_list.select { |s| @operation.addable?(s) }.to_set(&:key) if @operation.suggestions? && @operation.previewed?
  end

  # PATCH /fund_formula_operations/:id/apply
  def apply
    authorize @operation
    refusal = @operation.start_apply!(current_user)
    return redirect_to(fund_formula_operation_path(@operation), alert: refusal) if refusal

    redirect_to fund_formula_operation_path(@operation), notice: "Applying. This page updates when it is done."
  end

  # POST /fund_formula_operations/:id/add_suggestions  keys[], severity[key]
  def add_suggestions
    authorize @operation
    outcome = @operation.add_suggestions!(keys: params[:keys], severities: severity_params, user: current_user)
    added = outcome[:added].size
    flash[:notice] = "Added #{added} check #{'formula'.pluralize(added)}." if added.positive?
    flash[:alert] = "Not added: #{outcome[:failed].map { |name, why| "#{name} (#{why})" }.join('; ')}" if outcome[:failed].any?
    flash[:alert] = "Select at least one suggestion." if added.zero? && outcome[:failed].empty?
    redirect_to fund_formula_operation_path(@operation)
  end

  # POST /fund_formula_operations/:id/download_suggestions  keys[], severity[key]
  def download_suggestions
    authorize @operation
    return redirect_to(fund_formula_operation_path(@operation), alert: "Select at least one suggestion.") if Array(params[:keys]).empty?

    send_data @operation.suggestions_xlsx(keys: params[:keys], severities: severity_params),
              filename: "run_checks_fund_#{@operation.fund_id}_#{Time.zone.now.strftime('%Y%m%d%H%M%S')}.xlsx",
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  private

  def set_fund
    @fund = policy_scope(Fund).find(params[:fund_id])
  end

  def set_operation
    @operation = policy_scope(FundFormulaOperation).find(params[:id])
  end

  def operation_params
    case params[:operation]
    when "reseed_carry_forward" then { "date" => params[:date].presence && Date.local_parse(params[:date]).iso8601 }.compact
    when "suggest_checks" then { "ai" => ActiveRecord::Type::Boolean.new.cast(params[:ai]) || false }
    when "enable_incremental" then { "with_values" => true }
    else {}
    end
  end

  def breadcrumbs(*trail)
    { Funds: funds_path, "#{@fund}": fund_path(@fund), 'Fund Formulas': fund_formulas_path(fund_id: @fund.id) }
      .merge(trail.index_with(nil))
  end

  def severity_params
    params[:severity].respond_to?(:to_unsafe_h) ? params[:severity].to_unsafe_h.slice(*Array(params[:keys])) : {}
  end
end
