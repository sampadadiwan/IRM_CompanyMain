class DealInvestorIndex < Chewy::Index
  SEARCH_FIELDS = %i[deal_name status entity_name investor_name].freeze

  index_scope DealInvestor.includes(:deal, :investor, :entity)
  field :entity_name, value: ->(di) { di.entity.name if di.entity }
  field :deal_name, value: ->(di) { di.deal.name }
  field :status
  field :entity_id
  field :investor_name
  field :pre_money_valuation_cents
  field :primary_amount_cents
  field :secondary_investment_cents
end
