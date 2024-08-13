class AggregatePortfolioInvestmentDecorator < ApplicationDecorator
  include CurrencyHelper

  def company_link
    h.link_to object.portfolio_company_name, object.portfolio_company
  end

  def investment_instrument
    h.link_to object.investment_instrument, object
  end

  def fund_name
    h.link_to object.fund, object
  end

  def current_quantity
    custom_format_number(aggregate_portfolio_investment.quantity)
  end
end
