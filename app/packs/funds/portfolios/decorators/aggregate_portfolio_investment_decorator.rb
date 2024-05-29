class AggregatePortfolioInvestmentDecorator < ApplicationDecorator
  def company_link
    h.link_to object.portfolio_company_name, object.portfolio_company
  end

  def investment_instrument
    h.link_to object.investment_instrument, object
  end

  def fund_name
    h.link_to object.fund, object
  end

  def dt_actions
    links = []
    links << h.link_to('Show', h.aggregate_portfolio_investment_path(object), class: "btn btn-outline-primary")
    if h.policy(object).add_valuation?
      valuation_params = {
        'valuation[owner_id]': object.portfolio_company_id,
        'valuation[owner_type]': 'Investor',
        'valuation[investment_instrument_id]': object.investment_instrument_id
      }
      valuation_path = h.new_valuation_path(valuation_params)
      links << h.link_to('Add Valuation', valuation_path, class: "btn btn-outline-success")
    end
    h.safe_join(links, '')
  end
end
