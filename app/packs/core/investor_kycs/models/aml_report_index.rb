class AmlReportIndex < Chewy::Index
  SEARCH_FIELDS = %i[match_status name entity_name investor_name].freeze

  index_scope AmlReport.includes(:entity, :investor)

  field :match_status
  # The name screened. The column is custom_name (renamed from name); a bare `field :name`
  # raised NoMethodError, so this index could never be built (found by the DR reindex, 2026-11-08)
  field :name, value: ->(ar) { ar.custom_name }
  field :entity_name, value: ->(ar) { ar.entity.name if ar.entity }
  field :investor_name, value: ->(ar) { ar.investor.investor_name if ar.investor }
  field :entity_id
end

# def afake(amlr)
#   u = User.find 17
#   amlr.entity = u.entity
#   amlr.investor = u.entity.investors.first
#   amlr.investor_kyc= InvestorKyc.first
# end
