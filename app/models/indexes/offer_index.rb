class OfferIndex < Chewy::Index
  SEARCH_FIELDS = %i[investor_name entity_name user_full_name acquirer_name PAN].freeze

  index_scope Offer.includes(:user, :investor, :secondary_sale, :entity)
  field :entity_name, value: ->(h) { h.entity.name }
  field :investor_name, value: ->(h) { h.investor.investor_name if h.investor }
  field :entity_id
  field :secondary_sale_id
  field :acquirer_name
  field :PAN
  field :user_full_name, value: ->(h) { h.user.full_name if h.user }
end
