class InvestmentIndex < Chewy::Index
  SEARCH_FIELDS = %i[investor_name investee_name category funding_round_name investment_instrument].freeze

  index_scope Investment.includes(:investor, :entity, :funding_round)
  field :investor_id
  field :investor_name
  field :entity_id
  field :investee_name
  field :investment_instrument
  field :quantity
  field :category

  field :percentage_holding
  field :currency
  field :funding_round_name
end
