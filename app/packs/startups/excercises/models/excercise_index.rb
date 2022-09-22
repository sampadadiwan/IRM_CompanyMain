class ExcerciseIndex < Chewy::Index
  SEARCH_FIELDS = %i[entity_name pool_name user_full_name].freeze

  index_scope Excercise.includes(:entity, :user, :option_pool)
  field :entity_name, value: ->(h) { h.entity.name }
  field :pool_name, value: ->(h) { h.option_pool.name }
  field :entity_id
  field :approved
  field :user_full_name, value: ->(h) { h.user.full_name if h.user }
end
