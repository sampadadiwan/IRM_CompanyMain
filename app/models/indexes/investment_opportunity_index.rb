class InvestmentOpportunityIndex < Chewy::Index
  SEARCH_FIELDS = %i[company_name tag_list city properties].freeze

  index_scope InvestmentOpportunity.includes(:entity, tags: :taggings)
  field :company_name
  field :tag_list, value: ->(i) { i.tags.map(&:name).join(", ") }
  field :properties, value: ->(i) { i.properties.to_json if i.properties }
  field :entity_id
end
