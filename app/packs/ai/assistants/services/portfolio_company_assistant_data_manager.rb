# PortfolioCompanyAssistantDataManager
#
# Handles business logic and data retrieval for the PortfolioCompanyAssistant.
# Focused on a specific portfolio company: valuations, investments, KPIs, and documents.
#
class PortfolioCompanyAssistantDataManager < PortfolioAssistantDataManager
  def initialize(user:, portfolio_company:)
    super(user: user)
    @portfolio_company = portfolio_company
  end

  # Lists valuations for the mandatory portfolio company.
  def list_valuations(scope: nil, query: {}, sort: nil)
    super(portfolio_company_id: @portfolio_company.id, scope: scope, query: query, sort: sort)
  end

  # Lists portfolio investments for the mandatory portfolio company.
  def list_portfolio_investments(scope: nil, query: {}, sort: nil)
    super(portfolio_company_id: @portfolio_company.id, scope: scope, query: query, sort: sort)
  end

  # Lists KPIs for the mandatory portfolio company.
  def list_portfolio_kpis(scope: nil, query: {}, sort: nil)
    super(portfolio_company_ids: [@portfolio_company.id], scope: scope, query: query, sort: sort)
  end

  # Lists fund ratios for the mandatory portfolio company.
  def list_fund_ratios(query: {}, sort: nil)
    super(portfolio_company_id: @portfolio_company.id, query: query, sort: sort)
  end

  # Lists documents for the mandatory portfolio company.
  def list_documents(scope: nil, query: {}, sort: nil)
    super(portfolio_company_id: @portfolio_company.id, scope: scope, query: query, sort: sort)
  end

  # Generates a cap table for the mandatory portfolio company.
  def get_cap_table(funding_rounds: nil, group_by_field: :investor_name)
    super(portfolio_company_id: @portfolio_company.id, funding_rounds: funding_rounds, group_by_field: group_by_field)
  end

  # Gets investments in cap table for the mandatory portfolio company.
  def get_investments_in_cap_table(query: {}, sort: nil)
    super(portfolio_company_ids: [@portfolio_company.id], query: query, sort: sort)
  end

  # Gets details for the mandatory portfolio company.
  def get_portfolio_company_details
    super(portfolio_company_id: @portfolio_company.id)
  end
end
