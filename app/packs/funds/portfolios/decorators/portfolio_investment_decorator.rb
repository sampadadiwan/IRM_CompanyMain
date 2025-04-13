class PortfolioInvestmentDecorator < ApplicationDecorator
  include ActiveSupport::NumberHelper

  delegate :category, to: :investment_instrument, prefix: true

  def portfolio_company_name
    h.link_to portfolio_investment.portfolio_company_name, portfolio_investment.aggregate_portfolio_investment
  end

  def investment_instrument_name
    h.link_to object.investment_instrument, object.investment_instrument
  end

  def amount
    money_to_currency portfolio_investment.amount
  end

  def cost
    money_to_currency portfolio_investment.cost
  end

  def fmv
    money_to_currency portfolio_investment.fmv
  end

  def cost_of_sold
    money_to_currency portfolio_investment.cost_of_sold
  end

  def quantity
    number_to_delimited(object.quantity)
  end

  def category
    "#{portfolio_investment.category} : #{portfolio_investment.sub_category}"
  end
end
