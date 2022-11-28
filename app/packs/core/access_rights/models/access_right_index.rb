class AccessRightIndex < Chewy::Index
  SEARCH_FIELDS = %i[owner_name owner_type metadata entity_name access_type access_to_category investor_name user_name].freeze

  index_scope AccessRight.includes(:entity, :owner, :investor, :user)
  field :entity_name, value: ->(ar) { ar.entity.name if ar.entity }
  field :investor_name, value: ->(ar) { ar.investor.investor_name if ar.investor }
  field :user_name, value: ->(ar) { ar.user.full_name if ar.user }
  field :entity_id
  field :owner_type
  field :owner_id
  field :access_type
  field :metadata
  field :access_to_category
  field :owner_name, value: ->(ar) { ar.owner.name if ar.owner }
end
