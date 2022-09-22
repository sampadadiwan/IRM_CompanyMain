class InvestorAccessIndex < Chewy::Index
  settings analysis: {
    analyzer: {
      email: {
        tokenizer: 'keyword',
        filter: ['lowercase']
      }
    }
  }

  SEARCH_FIELDS = %i[entity_name user_full_name email investor_name].freeze

  index_scope InvestorAccess.includes(:entity, :user, :investor)
  field :entity_name, value: ->(ar) { ar.entity.name if ar.entity }
  field :investor_name, value: ->(ar) { ar.investor.investor_name if ar.investor }
  field :entity_id
  field :email, analyzer: 'email'
  field :user_full_name, value: ->(ar) { ar.user.full_name if ar.user }
end
