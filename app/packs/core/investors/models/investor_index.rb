class InvestorIndex < Chewy::Index
  SEARCH_FIELDS = %i[investor_name investee_name category tag_list city properties pan primary_email].freeze

  index_scope Investor.includes(:investor_entity, :entity)
  field :investor_name
  field :investee_name
  field :category
  field :primary_email
  field :city
  field :pan
  field :tag_list
  field :properties, value: ->(i) { i.properties.to_json if i.properties }
  field :entity_id
  field :investor_access_count
  field :unapproved_investor_access_count
end
