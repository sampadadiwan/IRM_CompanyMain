class KpiReportIndex < Chewy::Index
  SEARCH_FIELDS = %i[entity_name period tag_list portfolio_company_name owner_name user_name].freeze

  index_scope KpiReport.includes(:entity, :portfolio_company)
  field :id, value: ->(f) { f.id }
  field :user_name, value: ->(f) { f.user.full_name }
  field :entity_name, value: ->(f) { f.entity.name }
  field :portfolio_company_name, value: ->(f) { f.portfolio_company&.investor_name }
  field :period
  field :tag_list
  field :owner_name, value: ->(f) { f.owner&.name }
end
