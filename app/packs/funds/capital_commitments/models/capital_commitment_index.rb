class CapitalCommitmentIndex < Chewy::Index
  SEARCH_FIELDS = %i[entity_name investor_name fund_name].freeze

  index_scope CapitalCommitment.includes(:entity, :investor, :fund)
  field :entity_id
  field :fund_id
  field :folio_id
  field :fund_name, value: ->(f) { f.fund.name }
  field :entity_name, value: ->(f) { f.entity.name }
  field :investor_name, value: ->(f) { f.investor.investor_name }
end
