class AmlReportIndex < Chewy::Index
  SEARCH_FIELDS = %i[match_status status investor_name entity_name].freeze

  index_scope AmlReport.includes(:entity, :investor)

  field :match_status
  field :status
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
