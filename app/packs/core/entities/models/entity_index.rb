class EntityIndex < Chewy::Index
  SEARCH_FIELDS = %i[name pan entity_type active category].freeze
  index_scope Entity
  field :name
  field :pan
  field :entity_type
  field :active
  field :category
end
