json.extract! interest, :id, :entity_id, :quantity, :price, :allocation_quantity, :user_id, :interest_entity_id, :secondary_sale_id, :created_at, :updated_at, :buyer_entity_name

json.investor_name interest.investor&.investor_name
json.user interest.user&.full_name
json.allocation_amount interest.allocation_amount.to_f
json.short_listed_status short_listed_status(interest)
json.verified(display_boolean(interest.verified))
json.dt_actions render(
  partial: '/interests/dt_actions',
  formats: [:html],
  locals: { interest: }
)
