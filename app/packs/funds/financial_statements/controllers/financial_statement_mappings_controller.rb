# Mapping tab: the fund's accounts and rules, the Unmapped list, the checks and a live preview of
# every account (and every statement) for a chosen period. Computed on each request by the
# calculator; nothing is run or saved.
# Worked examples H4, H5, H6, H7, H8, E2, E3, E17, E22 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementMappingsController < ApplicationController
  include FinancialStatementFundContext

  before_action :set_fund_from_params
  after_action :verify_authorized

  def index
    authorize FinancialStatementMappingRule.new(fund: @fund, entity_id: @fund.entity_id)
    # A fund that hasn't been set up starts on the Statements tab's set-up screen
    @setting = FinancialStatementSetting.find_by(fund_id: @fund.id)
    return redirect_to(financial_statements_path(fund_id: @fund.id)) unless @setting

    # The period the preview, Unmapped list and checks are computed for
    @period_start, @period_end = preview_period
    # One calculator call: figures, checks, unmapped and which rule took each entry
    @preview = FinancialStatementPreview.new(fund: @fund, start_date: @period_start, end_date: @period_end)
    @result = @preview.result
    @accounts = FinancialStatementAccount.where(fund_id: @fund.id).ordered
    @rules = FinancialStatementMappingRule.where(fund_id: @fund.id).includes(:account).order(:entry_type, :name)
    # Per-rule "what did this rule pick up" column
    @rule_previews = rule_previews
    fund_breadcrumbs("Mapping")
  end

  # GET /financial_statement_mappings/preview?fund_id=&period_start=&period_end=
  # The statements for a period, one tab each, with only the accounts that statement uses and the
  # entries feeding them. Opened in a new browser tab from the Mapping tab; nothing is run or saved.
  # Worked examples H2, H8 — openspec/changes/fund-financial-statements/design.md#worked-examples
  def preview
    authorize FinancialStatementMappingRule.new(fund: @fund, entity_id: @fund.entity_id), :index?
    return redirect_to(financial_statements_path(fund_id: @fund.id)) unless FinancialStatementSetting.exists?(fund_id: @fund.id)

    @period_start, @period_end = preview_period
    # One calculator call for every statement, its accounts and the checks
    @preview = FinancialStatementPreview.new(fund: @fund, start_date: @period_start, end_date: @period_end)
    @result = @preview.result
    @accounts = FinancialStatementAccount.where(fund_id: @fund.id).index_by(&:id)
    # Account ids placed on each statement, in layout order
    @accounts_by_definition = FinancialStatementLayoutRow.where(fund_id: @fund.id, row_type: "account").order(:position, :id)
                                                         .pluck(:financial_statement_definition_id, :financial_statement_account_id)
                                                         .group_by(&:first).transform_values { |pairs| pairs.map(&:last).uniq }
    # account id => [[entry_type, name, figures]] of the entries feeding it this period
    @entries_by_account = Hash.new { |h, k| h[k] = [] }
    @result.assignments.each do |(entry_type, name), rule|
      next if rule["excluded"]

      @entries_by_account[rule["account_key"]] << [entry_type, name, @result.pairs[[entry_type, name]]]
    end
    fund_breadcrumbs("Statements preview")
  end

  private

  # [entry_type, rule name] => { "count", "period", "balance" } of the entries each rule took
  def rule_previews
    previews = Hash.new { |h, k| h[k] = { "count" => 0, "period" => 0.to_d, "balance" => 0.to_d } }
    @result.assignments.each do |pair, rule|
      # Rules are keyed by entry type + rule name ("" = any name)
      preview = previews[[rule["entry_type"], rule["name"].to_s]]
      preview["count"] += 1
      preview["period"] += @result.pairs[pair]["period"]
      preview["balance"] += @result.pairs[pair]["balance"]
    end
    previews
  end
end
