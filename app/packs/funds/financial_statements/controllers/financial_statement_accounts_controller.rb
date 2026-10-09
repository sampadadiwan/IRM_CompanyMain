# Statement accounts: add, edit, delete. Saving a fund's first account sets the fund up (core
# statements, settings, statement formula) and places the account on its default statement.
# Worked examples H1, H21, X5, X6 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementAccountsController < ApplicationController
  include FinancialStatementFundContext

  before_action :set_account, only: %i[edit update destroy]
  after_action :verify_authorized

  def new
    @fund = policy_scope(Fund).find(params[:fund_id])
    # Pre-selects a type when opened from a section ("+ Add" next to Assets)
    @account = FinancialStatementAccount.new(fund: @fund, entity_id: @fund.entity_id, account_type: params[:account_type].presence || "expense")
    authorize @account
    fund_breadcrumbs("New account")
  end

  def create
    # Only funds the user can see; fund and entity are never taken from the form
    @fund = policy_scope(Fund).find(params.dig(:financial_statement_account, :fund_id))
    @account = FinancialStatementAccount.new(account_params.merge(fund: @fund, entity_id: @fund.entity_id))
    authorize @account
    saved = false
    ActiveRecord::Base.transaction do
      # H1/H21: the first account sets the fund up
      setup = FinancialStatementSetup.new(@fund)
      setup.ensure!
      saved = @account.save
      # Placed under its section of the Balance Sheet / P&L unless the user opted out
      setup.place_account(@account) if saved && params[:place] != "0"
      raise ActiveRecord::Rollback unless saved
    end
    # Back to the tab the form came from (keeps the preview period)
    if saved
      redirect_to return_path(financial_statement_mappings_path(fund_id: @fund.id)), notice: "Account #{@account.name} added."
    else
      # X5: a duplicate name (or other invalid input) re-renders the form with the error
      fund_breadcrumbs("New account")
      render :new, status: :unprocessable_content
    end
  end

  def edit
    fund_breadcrumbs("Edit #{@account.name}")
  end

  def update
    # Type / behaviour / sign changes show up in the next preview and the next generation
    if @account.update(account_params)
      redirect_to return_path(financial_statement_mappings_path(fund_id: @fund.id)), notice: "Account #{@account.name} saved."
    else
      fund_breadcrumbs("Edit #{@account.name}")
      render :edit, status: :unprocessable_content
    end
  end

  # X6: refused while a rule or a statement row uses it, naming them
  def destroy
    # X6: before_destroy refuses (with the rule names) while anything uses the account
    if @account.destroy
      redirect_to return_path(financial_statement_mappings_path(fund_id: @fund.id)), notice: "Account #{@account.name} deleted."
    else
      redirect_to return_path(financial_statement_mappings_path(fund_id: @fund.id)), alert: @account.errors.full_messages.to_sentence
    end
  end

  private

  def set_account
    @account = policy_scope(FinancialStatementAccount).find(params[:id])
    @fund = @account.fund
    authorize @account
  end

  # fund_id, entity_id are set server-side
  def account_params
    params.expect(financial_statement_account: %i[name account_type behaviour flip_sign])
  end
end
