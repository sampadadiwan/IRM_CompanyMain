class EntityIndex < Chewy::Index
  index_scope Entity
  field :name
  field :entity_type
  field :active
  field :category
  field :currency
  field :equity
  field :preferred
  field :options
end
