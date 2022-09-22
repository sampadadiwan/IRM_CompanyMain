class HoldingIndex < Chewy::Index
  SEARCH_FIELDS = %i[investor_name investment_instrument holding_type entity_name funding_round_name user_full_name].freeze

  index_scope Holding.includes(:entity, :user, :investor, :funding_round)
  field :entity_name, value: ->(h) { h.entity.name }
  field :investor_name, value: ->(h) { h.investor.investor_name if h.investor }
  field :funding_round_name, value: ->(h) { h.funding_round.name }
  field :entity_id
  field :holding_type
  field :investment_instrument
  field :user_full_name, value: ->(h) { h.user.full_name if h.user }
end
