# SpecificFundAssistantDataManager
#
# A specialized version of FundAssistantDataManager that is restricted to a specific fund.
# It ensures that all data retrieval is automatically scoped to the provided fund.
#
class SpecificFundAssistantDataManager < FundAssistantDataManager
  attr_reader :fund

  # Initializes the data manager with a specific fund.
  #
  # @param user [User] The user context.
  # @param fund [Fund] The specific fund to restrict access to.
  def initialize(user:, fund:)
    super(user: user)
    @fund = fund
  end

  # Overrides list_funds to only return the current fund.
  def list_funds(*)
    super(query: { id_eq: @fund.id })
  end

  # Overrides get_fund_details to prefer the provided fund_id, falling back to @fund.id.
  def get_fund_details(fund_id: nil)
    super(fund_id: fund_id || @fund.id)
  end

  # Overrides list_capital_calls to prefer the provided fund_id, falling back to @fund.id.
  def list_capital_calls(fund_id: nil, query: {}, sort: nil)
    super(fund_id: fund_id || @fund.id, query: query, sort: sort)
  end

  # Overrides list_capital_commitments to prefer the provided fund_id, falling back to @fund.id.
  def list_capital_commitments(fund_id: nil, folio_id: nil, scope: nil, query: {}, sort: nil)
    super(fund_id: fund_id || @fund.id, folio_id: folio_id, scope: scope, query: query, sort: sort)
  end

  # Overrides list_capital_remittances to prefer the provided fund_id, falling back to @fund.id.
  def list_capital_remittances(fund_id: nil, folio_id: nil, scope: nil, query: {}, sort: nil)
    super(fund_id: fund_id || @fund.id, folio_id: folio_id, scope: scope, query: query, sort: sort)
  end

  # Overrides list_capital_distributions to prefer the provided fund_id, falling back to @fund.id.
  def list_capital_distributions(fund_id: nil, query: {}, sort: nil)
    super(fund_id: fund_id || @fund.id, query: query, sort: sort)
  end

  # Overrides list_capital_remittance_payments to prefer the provided fund_id, falling back to @fund.id.
  def list_capital_remittance_payments(fund_id: nil, folio_id: nil, query: {}, sort: nil)
    super(fund_id: fund_id || @fund.id, folio_id: folio_id, query: query, sort: sort)
  end

  # Overrides list_capital_distribution_payments to prefer the provided fund_id, falling back to @fund.id.
  def list_capital_distribution_payments(fund_id: nil, folio_id: nil, scope: nil, sort: nil)
    super(fund_id: fund_id || @fund.id, folio_id: folio_id, scope: scope, sort: sort)
  end

  # Overrides list_portfolio_investments to prefer the provided fund_id, falling back to @fund.id.
  def list_portfolio_investments(fund_id: nil, scope: nil, query: {}, sort: nil)
    super(fund_id: fund_id || @fund.id, scope: scope, query: query, sort: sort)
  end

  # Overrides list_fund_ratios to prefer the provided fund_id, falling back to @fund.id.
  def list_fund_ratios(fund_id: nil, query: {}, sort: nil)
    super(fund_id: fund_id || @fund.id, query: query, sort: sort)
  end
end
