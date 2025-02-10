class PortfolioInvestmentIndex < Chewy::Index
  SEARCH_FIELDS = %i[portfolio_company_name investment_instrument fund_name].freeze

  index_scope PortfolioInvestment.includes(:entity, :fund)

  field :portfolio_company_name
  field :investment_instrument, value: ->(portfolio_investment) { portfolio_investment.investment_instrument&.name }
  field :fund_name, value: ->(portfolio_investment) { portfolio_investment.fund.name }
  field :entity_id
end
