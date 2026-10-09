# Mapping rules: (entry type, optional exact name) -> account, or Excluded. "Map" on an Unmapped
# entry opens the new-rule form pre-filled with its entry type and name.
# Worked examples H4, H5, H7, H8, E2 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementMappingRulesController < ApplicationController
  include FinancialStatementFundContext

  EXCLUDED = "excluded".freeze

  before_action :set_rule, only: %i[edit update destroy]
  after_action :verify_authorized

  def new
    @fund = policy_scope(Fund).find(params[:fund_id])
    # H7: "Map" on an Unmapped row passes its entry type and name
    @rule = FinancialStatementMappingRule.new(fund: @fund, entity_id: @fund.entity_id, entry_type: params[:entry_type], name: params[:name])
    authorize @rule
    fund_breadcrumbs("Map entries")
  end

  def create
    # Only funds the user can see; fund and entity are never taken from the form
    @fund = policy_scope(Fund).find(params.dig(:financial_statement_mapping_rule, :fund_id))
    @rule = FinancialStatementMappingRule.new(rule_attributes.merge(fund: @fund, entity_id: @fund.entity_id))
    authorize @rule
    # Uniqueness (one rule per entry type + name) and account-xor-excluded are model validations
    if @rule.save
      redirect_to return_path(financial_statement_mappings_path(fund_id: @fund.id)), notice: "#{@rule.key_label} → #{@rule.target_label}."
    else
      fund_breadcrumbs("Map entries")
      render :new, status: :unprocessable_content
    end
  end

  def edit
    fund_breadcrumbs("Edit rule")
  end

  def update
    # H8: e.g. Excluded -> an account; the Mapping tab's preview reflects it on return, no entry is created
    if @rule.update(rule_attributes)
      redirect_to return_path(financial_statement_mappings_path(fund_id: @fund.id)), notice: "#{@rule.key_label} → #{@rule.target_label}."
    else
      fund_breadcrumbs("Edit rule")
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @rule.destroy!
    redirect_to return_path(financial_statement_mappings_path(fund_id: @fund.id)), notice: "Rule #{@rule.key_label} removed."
  end

  private

  def set_rule
    @rule = policy_scope(FinancialStatementMappingRule).find(params[:id])
    @fund = @rule.fund
    authorize @rule
  end

  # The form has one "Statement account" select whose "Excluded" option sets excluded
  def rule_attributes
    attrs = params.expect(financial_statement_mapping_rule: %i[entry_type name target])
    # target is an account id or "excluded"
    target = attrs.delete(:target)
    excluded = target == EXCLUDED
    attrs.merge(excluded:, financial_statement_account_id: excluded ? nil : target.presence)
  end
end
