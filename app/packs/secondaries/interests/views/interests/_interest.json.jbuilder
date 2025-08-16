json.extract! interest, :id, :entity_id, :quantity, :price, :allocation_quantity, :user_id, :interest_entity_id, :secondary_sale_id, :buyer_entity_name

json.investor_name interest.investor&.investor_name
json.user interest.user&.full_name
json.allocation_amount interest.allocation_amount.to_f
json.short_listed_status interest.short_listed_status.humanize
json.verified(display_boolean(interest.verified))
json.dt_actions render(
  partial: '/interests/dt_actions',
  formats: [:html],
  locals: { interest: }
)
json.created_at l(interest.created_at)
json.updated_at l(interest.updated_at)

if interest.secondary_sale.interest_pivot_custom_fields.present?
  pivot_custom_fields = interest.secondary_sale.interest_pivot_custom_fields.split(",")
  filtered_fields = interest.json_fields.slice(*pivot_custom_fields.map(&:to_s))
  json.merge! filtered_fields if interest.json_fields.present?
end
