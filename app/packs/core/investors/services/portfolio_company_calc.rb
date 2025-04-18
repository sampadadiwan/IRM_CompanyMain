class PortfolioCompanyCalc
  def initialize(portfolio_company, fund_id: nil, as_of: nil)
    @portfolio_company = portfolio_company
    @fund_id = fund_id
    @as_of = as_of
    @fund = fund_id ? Fund.find(fund_id) : nil
  end

  # Returns the portfolio company investments for the given fund and as_of
  def portfolio_investments
    @portfolio_investments = @portfolio_company.portfolio_investments
    # Filter by fund if fund_id is provided
    @portfolio_investments = @portfolio_investments.where(fund_id: @fund_id) if @fund_id
    # Filter by as_of date if provided
    @portfolio_investments = @portfolio_investments.where(investment_date: ..@as_of) if @as_of
    if @as_of
      # Convert to the as_of date if provided
      @portfolio_investments.map { |pi| pi.as_of(@as_of) }
    else
      @portfolio_investments
    end
  end

  def calculate
    # To enable ExchangeRate to be used in the calculation
    bank = ExchangeRate.setup_variable_exchange(@as_of, @portfolio_company.entity_id)
    currency = @fund ? @fund.currency : @portfolio_company.entity.currency

    # This is a dummy PI, which will be used to hold aggregated values from the portfolio investments
    aggregated_portfolio_investment = PortfolioInvestment.new(entity_id: @portfolio_company.entity_id, fund_id: @fund_id, investment_date: @as_of, portfolio_company: @portfolio_company, fund: Fund.new(currency: currency), net_amount_cents: 0)

    # Iterate through the portfolio investments and aggregate the values, ensure to convert to the entity currency
    portfolio_investments.each do |pi|
      aggregated_portfolio_investment.amount += bank.exchange_with(pi.amount, currency)
      aggregated_portfolio_investment.net_amount += bank.exchange_with(pi.net_amount, currency)
      aggregated_portfolio_investment.fmv += bank.exchange_with(pi.fmv, currency)
      aggregated_portfolio_investment.gain += bank.exchange_with(pi.gain, currency)
      aggregated_portfolio_investment.unrealized_gain += bank.exchange_with(pi.unrealized_gain, currency)
      aggregated_portfolio_investment.cost_of_sold += bank.exchange_with(pi.cost_of_sold, currency)
      aggregated_portfolio_investment.transfer_amount = bank.exchange_with(pi.transfer_amount, currency)
    end

    # return the aggregated portfolio investment
    aggregated_portfolio_investment
  end
end
