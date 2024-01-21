class UserIndex < Chewy::Index
  settings analysis: {
    analyzer: {
      email: {
        tokenizer: 'keyword',
        filter: ['lowercase']
      }
    }
  }

  SEARCH_FIELDS = %i[first_name last_name email entity_id active].freeze
  index_scope User.includes(:entity)
  field :first_name
  field :last_name
  field :email, analyzer: 'email'
  field :active
  field :entity_name, value: ->(user) { user.entity.name if user.entity }
  field :entity_id
end
