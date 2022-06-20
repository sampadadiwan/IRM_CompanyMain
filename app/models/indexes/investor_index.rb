class InvestorIndex < Chewy::Index
  SEARCH_FIELDS = %i[investor_name investee_name category tags city properties].freeze

  index_scope Investor.includes(:investor_entity, :entity, tags: :taggings)
  field :investor_name
  field :investee_name
  field :category
  field :city
  field :tags
  field :properties
  field :entity_id
  field :is_holdings_entity
  field :investor_access_count
  field :unapproved_investor_access_count
end
