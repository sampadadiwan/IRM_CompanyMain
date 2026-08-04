class FundFormulaIndex < Chewy::Index
  # do not index/search on ai_description
  SEARCH_FIELDS = %i[name entry_type rule_type rule_for description formula fund_name entity_name].freeze

  index_scope FundFormula.includes(:entity, :fund)

  field :name
  field :entry_type
  field :rule_type
  field :rule_for
  field :description
  field :formula
  field :entity_name, value: ->(formula) { formula.entity.name if formula.entity }
  field :fund_name, value: ->(formula) { formula.fund.name if formula.fund }
  field :fund_id
  field :entity_id
end
