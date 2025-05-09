class FundRatioIndex < Chewy::Index
  SEARCH_FIELDS = %i[entity_name name fund_name end_date scenario].freeze

  index_scope FundRatio.includes(:entity, :fund)
  field :fund_id
  field :valuation_id
  field :name
  field :scenario
  field :capital_commitment_id
  field :end_date
  field :entity_id
  field :fund_name, value: ->(f) { f.fund&.name }
  field :entity_name, value: ->(f) { f.entity.name }
end
