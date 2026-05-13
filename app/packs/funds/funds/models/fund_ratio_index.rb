class FundRatioIndex < Chewy::Index
  SEARCH_FIELDS = %i[entity_name name fund_name end_date scenario computation_context_name computation_context_id label].freeze

  index_scope FundRatio.includes(:entity, :fund)
  field :fund_id
  field :valuation_id
  field :name
  field :scenario
  field :capital_commitment_id
  field :computation_context_type
  field :computation_context_id
  field :end_date
  field :label
  field :entity_id
  field :fund_name,                value: ->(f) { f.fund&.name }
  field :entity_name,              value: ->(f) { f.entity.name }
  # Resolves the parent's display name regardless of context type (FundRatioRun or PortfolioScenario).
  field :computation_context_name, value: ->(f) { f.computation_context&.name }
end
