class AggregatePortfolioInvestmentDecorator < ApplicationDecorator
  include CurrencyHelper
  include ActiveSupport::NumberHelper

  def portfolio_company_name
    h.link_to object.portfolio_company_name, object.portfolio_company
  end

  def investment_instrument
    h.link_to object.investment_instrument, object
  end

  def fund_name
    h.link_to object.fund, object
  end

  def net_bought_amount
    money_to_currency(object.bought_amount, {})
  end

  def sold_amount_currency
    money_to_currency(object.sold_amount, {})
  end

  def fmv_currency
    money_to_currency(object.fmv, {})
  end

  def avg_cost_currency
    money_to_currency(object.avg_cost, {})
  end

  def comma_quantity
    number_to_delimited(object.quantity)
  end

  def current_quantity
    custom_format_number(aggregate_portfolio_investment.quantity)
  end
end
