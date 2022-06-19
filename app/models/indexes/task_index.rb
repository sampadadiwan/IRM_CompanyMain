class TaskIndex < Chewy::Index
  SEARCH_FIELDS = %i[investor_name entity_name user_full_name details].freeze

  index_scope Task.includes(:user, :investor, :entity)
  field :entity_name, value: ->(h) { h.entity.name }
  field :investor_name, value: ->(h) { h.investor.investor_name if h.investor }
  field :entity_id
  field :user_full_name, value: ->(h) { h.user.full_name if h.user }
  field :details
end
