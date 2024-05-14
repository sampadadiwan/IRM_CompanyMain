class DealInvestorIndex < Chewy::Index
  SEARCH_FIELDS = %i[deal_name status entity_name investor_name tags notes].freeze

  index_scope DealInvestor.includes(:deal, :investor, :entity)
  field :entity_name, value: ->(di) { di.entity.name if di.entity }
  field :deal_name, value: ->(di) { di.deal.name }
  field :status
  field :entity_id
  field :investor_name
  field :pre_money_valuation_cents
  field :primary_amount_cents
  field :secondary_investment_cents
  field :tags
  field :notes, value: ->(di) { di.notes.present? ? ActionText::Content.new(di.notes).to_plain_text : nil }
end
