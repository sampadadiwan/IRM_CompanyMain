# Statements tab (list + Generate), the statement view, Regenerate, Lock and the Excel / PDF
# downloads. Generate and Lock refusals come back as flash alerts with the guard's message.
# Worked examples H12, H15, H19, H20, E1, E25, X1, X2, X3, X8, X9, X13, X14 —
# openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementsController < ApplicationController
  include FinancialStatementFundContext

  before_action :set_fund_from_params, only: %i[index create setup]
  before_action :set_financial_statement, only: %i[show regenerate lock]
  after_action :verify_authorized

  # GET /financial_statements?fund_id= — the Statements tab, or the set-up screen for a new fund
  def index
    authorize FinancialStatement.new(fund: @fund, entity_id: @fund.entity_id)
    # No settings row yet = the fund hasn't started: the view shows the two set-up choices
    @setting = FinancialStatementSetting.find_by(fund_id: @fund.id)
    # Newest period first, with what each row shows preloaded (runs for state, locker for "Locked by")
    @financial_statements = policy_scope(FinancialStatement).where(fund_id: @fund.id).order(end_date: :desc, start_date: :desc)
                                                            .includes(:statements_allocation_run, :accounting_allocation_run, :locked_by)
    # Pre-fills the Generate form with the next period to do
    @period_start, @period_end = default_generate_period
    fund_breadcrumbs("Statements")
  end

  # POST /financial_statements/setup?fund_id= — "Set up manually": settings, core statements, formula
  def setup
    authorize FinancialStatement.new(fund: @fund, entity_id: @fund.entity_id)
    # Idempotent: a second click changes nothing
    FinancialStatementSetup.ensure!(@fund)
    # Next step for the user is the Mapping tab
    redirect_to financial_statement_mappings_path(fund_id: @fund.id),
                notice: "Financial statements are set up. Add the fund's accounts and map its entries to them."
  end

  # GET /financial_statements/:id (.xlsx / .pdf)
  def show
    @fund = @financial_statement.fund
    # Rendered statements: frozen copy when locked, live layout + figures when ready. Skipped while
    # generating or failed (the page polls every 5 s and shows no figures then)
    @statements = %w[ready locked].include?(@financial_statement.state) ? @financial_statement.statements : []
    # The statement switcher: the chosen statement, else the first (Balance Sheet)
    @definition_id = (params[:definition_id].presence || @statements.first&.dig("definition_id")).to_i
    @current = @statements.find { |s| s["definition_id"].to_i == @definition_id } || @statements.first
    fund_breadcrumbs(@financial_statement.period_label)
    respond_to do |format|
      format.html
      # H19: one sheet per statement
      format.xlsx do
        send_data FinancialStatementXlsx.new(@financial_statement).to_stream.read, filename: export_filename("xlsx"),
                                                                                   type: Mime[:xlsx].to_s
      end
      # H19: one section per statement, DRAFT watermark on drafts
      format.pdf do
        send_data FinancialStatementPdf.new(@financial_statement).render, filename: export_filename("pdf"), type: "application/pdf"
      end
    end
  end

  # POST /financial_statements?fund_id= — Generate statements for a period (E1: same period regenerates)
  def create
    authorize FinancialStatement.new(fund: @fund, entity_id: @fund.entity_id)
    # Dates arrive in the locale's format from the date inputs
    start_date = fs_parse_date(params.dig(:financial_statement, :start_date))
    end_date = fs_parse_date(params.dig(:financial_statement, :end_date))
    # Guards, the Draft record and the statements run; raises Refused with the user's message
    statement = FinancialStatementGenerate.call(fund: @fund, start_date:, end_date:, user: current_user)
    # The statement view polls itself until the run is done
    redirect_to financial_statement_path(statement), notice: "Generating statements for #{statement.period_label}. This page updates when they are ready."
  rescue FinancialStatementGenerate::Refused => e
    Rails.logger.info { "FinancialStatementsController#create refused for fund #{@fund.id}: #{e.message}" }
    redirect_to financial_statements_path(fund_id: @fund.id), alert: e.message
  end

  # POST /financial_statements/:id/regenerate (X3 refused when locked)
  def regenerate
    # Same period, same record: Generate's guards apply (locked, run in progress, ...)
    statement = FinancialStatementGenerate.call(fund: @financial_statement.fund, start_date: @financial_statement.start_date,
                                                end_date: @financial_statement.end_date, user: current_user)
    redirect_to financial_statement_path(statement, definition_id: params[:definition_id]), notice: "Regenerating statements for #{statement.period_label}."
  rescue FinancialStatementGenerate::Refused => e
    redirect_to financial_statement_path(@financial_statement, definition_id: params[:definition_id]), alert: e.message
  end

  # PATCH /financial_statements/:id/lock (X8, X9 refused)
  def lock
    # Refuses unless ready, nothing unmapped and every check passed or skipped
    FinancialStatementLock.call(@financial_statement, user: current_user)
    redirect_to financial_statement_path(@financial_statement, definition_id: params[:definition_id]),
                notice: "Statements for #{@financial_statement.period_label} are locked."
  rescue FinancialStatementLock::Refused => e
    redirect_to financial_statement_path(@financial_statement, definition_id: params[:definition_id]), alert: e.message
  end

  private

  # X14: another entity's statement is not found
  def set_financial_statement
    # X14: scoped to the user's entity, so another entity's id is not found
    @financial_statement = policy_scope(FinancialStatement).find(params[:id])
    # H20 / X13: show for read access; regenerate / lock need update access
    authorize @financial_statement
  end

  # The quarter after the latest statement set, else the last completed quarter
  def default_generate_period
    latest = @financial_statements.first
    # Continue from the latest set; a fund's first set defaults to the last completed quarter
    end_date = latest ? (latest.end_date + 1).end_of_quarter : (Time.zone.today.beginning_of_quarter - 1)
    # Never suggest a period that hasn't ended yet
    end_date = Time.zone.today.beginning_of_quarter - 1 if end_date >= Time.zone.today
    [end_date.beginning_of_quarter, end_date]
  end

  # alpha-fund-i-financial-statements-2026-09-30-draft.pdf (machine date format: a filename, not display text)
  def export_filename(ext)
    "#{@fund.name.parameterize}-financial-statements-#{@financial_statement.end_date.strftime('%Y-%m-%d')}#{'-draft' unless @financial_statement.locked?}.#{ext}"
  end
end
