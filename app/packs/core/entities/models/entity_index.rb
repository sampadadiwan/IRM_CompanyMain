class EntityIndex < Chewy::Index
  index_scope Entity
  field :name
  field :pan
  field :entity_type
  field :active
  field :category
  field :currency
  field :equity
  field :preferred
  field :options
end
