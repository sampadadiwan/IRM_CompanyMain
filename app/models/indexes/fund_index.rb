class FundIndex < Chewy::Index
  SEARCH_FIELDS = %i[name tag_list entity_name].freeze

  index_scope Fund.includes(:entity)
  field :name
  field :tag_list
  field :entity_id
  field :entity_name, value: ->(f) { f.entity.name if f.entity }
end
