# Layout tab: the fund's statements (core + schedules) and the rows of the selected one. Core
# statements can be renamed, not deleted; schedules are added with a column style.
# Worked examples H21, H22, H23, X17 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementDefinitionsController < ApplicationController
  include FinancialStatementFundContext

  before_action :set_definition, only: %i[edit update destroy]
  after_action :verify_authorized

  # GET /financial_statement_definitions?fund_id=&definition_id=
  def index
    @fund = policy_scope(Fund).find(params[:fund_id])
    authorize FinancialStatementDefinition.new(fund: @fund, entity_id: @fund.entity_id)
    # Not set up yet: start on the set-up screen
    return redirect_to(financial_statements_path(fund_id: @fund.id)) unless FinancialStatementSetting.exists?(fund_id: @fund.id)

    # Pills along the top: every statement; the selected one's rows below
    @definitions = FinancialStatementDefinition.where(fund_id: @fund.id).ordered
    @definition = @definitions.find { |d| d.id == params[:definition_id].to_i } || @definitions.first
    @rows = @definition.layout_rows.includes(:account).to_a
    # Live preview of the selected statement beside its rows, so layout edits show their effect
    @period_start, @period_end = preview_period
    @preview_statement = FinancialStatementPreview.new(fund: @fund, start_date: @period_start, end_date: @period_end)
                                                  .statements.find { |s| s["definition_id"] == @definition.id }
    fund_breadcrumbs("Layout")
  end

  def new
    @fund = policy_scope(Fund).find(params[:fund_id])
    @definition = FinancialStatementDefinition.new(fund: @fund, entity_id: @fund.entity_id, kind: "schedule", column_style: "for_period")
    authorize @definition
    fund_breadcrumbs("Add schedule")
  end

  # H23: a schedule is a new statement over the same accounts
  def create
    @fund = policy_scope(Fund).find(params.dig(:financial_statement_definition, :fund_id))
    # H23: a schedule is a new statement; it goes after the existing ones
    position = (FinancialStatementDefinition.where(fund_id: @fund.id).maximum(:position) || 0) + 1
    # kind is always "schedule" here: core statements are created only by FinancialStatementSetup
    @definition = FinancialStatementDefinition.new(definition_params.merge(fund: @fund, entity_id: @fund.entity_id, kind: "schedule", position:))
    authorize @definition
    if @definition.save
      redirect_to financial_statement_definitions_path(fund_id: @fund.id, definition_id: @definition.id),
                  notice: "#{@definition.name} added. Add its headings, accounts and subtotals below."
    else
      fund_breadcrumbs("Add schedule")
      render :new, status: :unprocessable_content
    end
  end

  def edit
    fund_breadcrumbs("Rename #{@definition.name}")
  end

  # H22: renaming a core statement ("Statement of Operations")
  def update
    # H22: a core statement can be renamed; it keeps its column style (fixed by kind in the model)
    if @definition.update(definition_params)
      redirect_to financial_statement_definitions_path(fund_id: @fund.id, definition_id: @definition.id), notice: "#{@definition.name} saved."
    else
      fund_breadcrumbs("Rename #{@definition.name}")
      render :edit, status: :unprocessable_content
    end
  end

  # X17: core statements are refused
  def destroy
    # X17: refused for core statements; a schedule's rows go with it
    if @definition.destroy
      redirect_to financial_statement_definitions_path(fund_id: @fund.id), notice: "#{@definition.name} deleted."
    else
      redirect_to financial_statement_definitions_path(fund_id: @fund.id, definition_id: @definition.id), alert: @definition.errors.full_messages.to_sentence
    end
  end

  private

  def set_definition
    @definition = policy_scope(FinancialStatementDefinition).find(params[:id])
    @fund = @definition.fund
    authorize @definition
  end

  # kind is never permitted (set server-side); a core statement's column style is fixed by its kind
  def definition_params
    params.expect(financial_statement_definition: %i[name column_style])
  end
end
