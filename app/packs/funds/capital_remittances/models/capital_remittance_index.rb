class CapitalRemittanceIndex < Chewy::Index
  SEARCH_FIELDS = %i[entity_name investor_name fund_name status capital_call_name folio_id].freeze

  index_scope CapitalRemittance.includes(:entity, :investor, :fund, :capital_call)
  field :entity_id
  field :fund_id
  field :folio_id
  field :capital_call_id
  field :status
  field :capital_call_name, value: ->(f) { f.capital_call.name }
  field :fund_name, value: ->(f) { f.fund.name }
  field :entity_name, value: ->(f) { f.entity.name }
  field :investor_name, value: ->(f) { f.investor.investor_name }
end
