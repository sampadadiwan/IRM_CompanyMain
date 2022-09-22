class SecondarySaleIndex < Chewy::Index
  SEARCH_FIELDS = %i[name entity_name].freeze

  index_scope SecondarySale.includes(:entity)
  field :entity_name, value: ->(h) { h.entity.name }
  field :entity_id
  field :name
  field :visible_externally
  field :start_date, type: "date"
  field :end_date, type: "date"
end
