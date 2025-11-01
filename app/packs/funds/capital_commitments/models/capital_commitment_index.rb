class CapitalCommitmentIndex < Chewy::Index
  SEARCH_FIELDS = %i[entity_name investor_name kyc_full_name fund_name folio_id].freeze

  index_scope CapitalCommitment.includes(:entity, :fund, :investor_kyc)
  field :entity_id
  field :fund_id
  field :folio_id, value: ->(f) { SearchHelper.sanitize_text_for_search(f.folio_id) }
  field :fund_name, value: ->(f) { SearchHelper.sanitize_text_for_search(f.fund.name) }
  field :entity_name, value: ->(f) { SearchHelper.sanitize_text_for_search(f.entity.name) }
  field :investor_name, value: ->(f) { SearchHelper.sanitize_text_for_search(f.investor_name) }
  field :kyc_full_name, value: ->(f) { SearchHelper.sanitize_text_for_search(f.investor_kyc&.full_name) }
end
