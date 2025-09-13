class FundRatioIndex < Chewy::Index
  SEARCH_FIELDS = %i[entity_name name fund_name end_date scenario portfolio_scenario_name portfolio_scenario_id label].freeze

  index_scope FundRatio.includes(:entity, :fund)
  field :fund_id
  field :valuation_id
  field :name
  field :scenario
  field :capital_commitment_id
  field :portfolio_scenario_id
  field :end_date
  field :label
  field :entity_id
  field :fund_name, value: ->(f) { f.fund&.name }
  field :entity_name, value: ->(f) { f.entity.name }
  field :portfolio_scenario_name, value: ->(f) { f.portfolio_scenario&.name }
end
