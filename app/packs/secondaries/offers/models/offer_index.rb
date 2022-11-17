class OfferIndex < Chewy::Index
  SEARCH_FIELDS = %i[investor_name entity_name user_full_name acquirer_name PAN interest_entity_name investment_instrument custom_matching_vals].freeze

  index_scope Offer.includes(:user, :investor, :secondary_sale, :entity, :interest)
  field :entity_name, value: ->(h) { h.entity.name }
  field :investor_name, value: ->(h) { h.investor.investor_name if h.investor }
  field :entity_id
  field :interest_id
  field :secondary_sale_id
  field :acquirer_name
  field :custom_matching_vals
  field :investment_instrument, value: ->(h) { h.holding.investment_instrument }
  field :PAN
  field :user_full_name, value: ->(h) { h.user.full_name if h.user }
  field :interest_entity_name, value: ->(h) { h.interest&.interest_entity&.name }
end
