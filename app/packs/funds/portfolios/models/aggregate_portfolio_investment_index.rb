class AggregatePortfolioInvestmentIndex < Chewy::Index
  SEARCH_FIELDS = %i[portfolio_company_name investment_instrument fund_name].freeze

  index_scope AggregatePortfolioInvestment.includes(:entity, :fund)

  field :portfolio_company_name
  field :investment_instrument, value: ->(aggregate_portfolio_investment) { aggregate_portfolio_investment.investment_instrument&.name }
  field :fund_name, value: ->(aggregate_portfolio_investment) { aggregate_portfolio_investment.fund.name }
  field :entity_id
end
