class PortfolioInvestmentDecorator < ApplicationDecorator
  def for
    portfolio_investment.Pool? ? "Pool" : link_to(portfolio_investment.capital_commitment)
  end

  def company_name
    h.link_to portfolio_investment.portfolio_company_name, portfolio_investment.aggregate_portfolio_investment
  end

  def currency_amount
    money_to_currency portfolio_investment.amount
  end

  def cost_in_currency
    money_to_currency portfolio_investment.cost
  end

  def fmv_currency
    money_to_currency portfolio_investment.fmv
  end

  def cost_of_sold_currency
    money_to_currency portfolio_investment.cost_of_sold
  end

  def investment_type
    "#{portfolio_investment.category} : #{portfolio_investment.sub_category}"
  end
end
