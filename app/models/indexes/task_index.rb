class TaskIndex < Chewy::Index
  SEARCH_FIELDS = %i[for_entity_name entity_name user_full_name details].freeze

  index_scope Task.includes(:user, :for_entity, :entity)
  field :entity_name, value: ->(h) { h.entity.name }
  field :for_entity_name, value: ->(h) { h.for_entity.name }
  field :entity_id
  field :for_entity_id
  field :user_full_name, value: ->(h) { h.user.full_name if h.user }
  field :details
end
