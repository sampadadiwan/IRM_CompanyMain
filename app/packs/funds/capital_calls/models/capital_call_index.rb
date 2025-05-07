class CapitalCallIndex < Chewy::Index
  SEARCH_FIELDS = %i[entity_name name fund_name].freeze

  index_scope CapitalCall.includes(:entity, :fund)
  field :entity_id
  field :fund_id
  field :name
  field :fund_name, value: ->(f) { f.fund.name }
  field :entity_name, value: ->(f) { f.entity.name }
end
