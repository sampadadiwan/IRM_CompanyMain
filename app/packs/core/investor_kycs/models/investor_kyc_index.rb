class InvestorKycIndex < Chewy::Index
  SEARCH_FIELDS = %i[full_name investor_name entity_name PAN bank_account_number].freeze

  index_scope InvestorKyc.includes(:entity, :investor)

  field :full_name
  field :PAN
  field :bank_account_number
  field :verified
  field :kyc_type
  field :entity_name, value: ->(kyc) { kyc.entity.name if kyc.entity }
  field :investor_name, value: ->(kyc) { kyc.investor.investor_name if kyc.investor }
  field :entity_id
end
