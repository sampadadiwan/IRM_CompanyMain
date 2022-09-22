class DealIndex < Chewy::Index
  SEARCH_FIELDS = %i[name status entity_name].freeze

  index_scope Deal.includes(:entity)
  field :entity_name
  field :name
  field :status
  field :entity_id
  field :amount_cents
  field :start_date, type: "date"
  field :end_date, type: "date"
  field :currency
end
