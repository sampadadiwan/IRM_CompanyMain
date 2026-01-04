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
  def list_funds(aggregate: nil, **)
    super(query: { id_eq: @fund.id }, aggregate: aggregate)
  end

  # Overrides get_fund_details to force the use of @fund.id.
  def get_fund_details(*)
    details = super(fund_id: @fund.id)
    return details if details.is_a?(String) # Error message

    details.merge!(
      collected_amount: @fund.collected_amount.format,
      committed_amount: @fund.committed_amount.format,
      distribution_amount: @fund.distribution_amount.format,
      call_amount: @fund.call_amount.format
    )

    details
  end

  # Overrides list_capital_calls to force the use of @fund.id.
  def list_capital_calls(scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    super(fund_ids: @fund.id, scope: scope, query: query, sort: sort, limit: limit, aggregate: aggregate)
  end

  # Overrides list_capital_commitments to force the use of @fund.id.
  def list_capital_commitments(folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    super(fund_ids: @fund.id, folio_ids: folio_ids, scope: scope, query: query, sort: sort, limit: limit, aggregate: aggregate)
  end

  # Overrides list_capital_remittances to force the use of @fund.id.
  def list_capital_remittances(folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    super(fund_ids: @fund.id, folio_ids: folio_ids, scope: scope, query: query, sort: sort, limit: limit, aggregate: aggregate)
  end

  # Overrides list_capital_distributions to force the use of @fund.id.
  def list_capital_distributions(scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    super(fund_ids: @fund.id, scope: scope, query: query, sort: sort, limit: limit, aggregate: aggregate)
  end

  # Overrides list_capital_remittance_payments to force the use of @fund.id.
  def list_capital_remittance_payments(folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    super(fund_ids: @fund.id, folio_ids: folio_ids, scope: scope, query: query, sort: sort, limit: limit, aggregate: aggregate)
  end

  # Overrides list_capital_distribution_payments to force the use of @fund.id.
  def list_capital_distribution_payments(folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    super(fund_ids: @fund.id, folio_ids: folio_ids, scope: scope, query: query, sort: sort, limit: limit, aggregate: aggregate)
  end

  # Overrides list_portfolio_investments to force the use of @fund.id.
  def list_portfolio_investments(scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    super(fund_ids: @fund.id, scope: scope, query: query, sort: sort, limit: limit, aggregate: aggregate)
  end

  # Overrides list_fund_ratios to force the use of @fund.id.
  def list_fund_ratios(scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    super(fund_ids: @fund.id, scope: scope, query: query, sort: sort, limit: limit, aggregate: aggregate)
  end

  # Overrides list_account_entries to force the use of @fund.id.
  def list_account_entries(folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    super(fund_ids: @fund.id, folio_ids: folio_ids, scope: scope, query: query, sort: sort, limit: limit, aggregate: aggregate)
  end
end
