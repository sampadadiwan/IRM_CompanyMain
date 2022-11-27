class CapitalDistributionPaymentIndex < Chewy::Index
  SEARCH_FIELDS = %i[entity_name investor_name fund_name capital_distribution_title].freeze

  index_scope CapitalDistributionPayment.includes(:entity, :investor, :fund, :capital_distribution)
  field :entity_id
  field :capital_distribution_id
  field :fund_id
  field :fund_name, value: ->(f) { f.fund.name }
  field :capital_distribution_title, value: ->(f) { f.capital_distribution.title }
  field :entity_name, value: ->(f) { f.entity.name }
  field :investor_name, value: ->(f) { f.investor.investor_name }
end
