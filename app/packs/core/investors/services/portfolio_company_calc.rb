class PortfolioCompanyCalc
  def initialize(portfolio_company, fund_id: nil, as_of: nil)
    @portfolio_company = portfolio_company
    @fund_id = fund_id
    @as_of = as_of
    @fund = fund_id ? Fund.find(fund_id) : nil
  end

  # Returns the portfolio company investments for the given fund and as_of
  def aggregate_portfolio_investments
    @aggregate_portfolio_investments = @portfolio_company.aggregate_portfolio_investments
    # Filter by fund if fund_id is provided
    @aggregate_portfolio_investments = @aggregate_portfolio_investments.where(fund_id: @fund_id) if @fund_id

    if @as_of
      # Convert to the as_of date if provided
      @aggregate_portfolio_investments = @aggregate_portfolio_investments.map { |pi| pi.as_of(@as_of) }
    else
      @aggregate_portfolio_investments
    end

    @aggregate_portfolio_investments
  end

  def calculate
    # To enable ExchangeRate to be used in the calculation
    bank = ExchangeRate.setup_variable_exchange(@as_of, @portfolio_company.entity_id)
    currency = @fund ? @fund.currency : @portfolio_company.entity.currency

    # This is a dummy PI, which will be used to hold aggregated values from the portfolio investments
    aggregated_portfolio_investment = AggregatePortfolioInvestment.new(entity_id: @portfolio_company.entity_id, fund_id: @fund_id, portfolio_company: @portfolio_company, fund: Fund.new(currency: currency))

    # Iterate through the portfolio investments and aggregate the values, ensure to convert to the entity currency
    aggregate_portfolio_investments.each do |pi|
      aggregated_portfolio_investment.bought_amount += bank.exchange_with(pi.bought_amount, currency)
      aggregated_portfolio_investment.cost_of_remaining += bank.exchange_with(pi.cost_of_remaining, currency)
      aggregated_portfolio_investment.cost_of_sold += bank.exchange_with(pi.cost_of_sold, currency)
      aggregated_portfolio_investment.sold_amount += bank.exchange_with(pi.sold_amount, currency)
      aggregated_portfolio_investment.fmv += bank.exchange_with(pi.fmv, currency)
      aggregated_portfolio_investment.gain += bank.exchange_with(pi.gain, currency)
      aggregated_portfolio_investment.unrealized_gain += bank.exchange_with(pi.unrealized_gain, currency)
    end

    # return the aggregated portfolio investment
    aggregated_portfolio_investment
  end
end
