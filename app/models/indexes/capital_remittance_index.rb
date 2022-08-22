class CapitalRemittanceIndex < Chewy::Index
  SEARCH_FIELDS = %i[entity_name investor_name fund_name status].freeze

  index_scope CapitalRemittance.includes(:entity, :investor, :fund)
  field :entity_id
  field :status
  field :fund_name, value: ->(f) { f.fund.name }
  field :entity_name, value: ->(f) { f.entity.name }
  field :investor_name, value: ->(f) { f.investor.investor_name }
end
