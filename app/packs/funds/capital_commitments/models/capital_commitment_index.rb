class CapitalCommitmentIndex < Chewy::Index
  SEARCH_FIELDS = %i[entity_name investor_name kyc_full_name fund_name folio_id unit_type fund_close].freeze

  index_scope CapitalCommitment.includes(:entity, :fund, :investor_kyc, :investor)
  field :entity_id
  field :investor_entity_id, value: ->(c) { c.investor.investor_entity_id }
  field :fund_id
  field :unit_type, value: ->(f) { SearchHelper.sanitize_text_for_search(f.unit_type) }
  field :fund_close, value: ->(f) { SearchHelper.sanitize_text_for_search(f.fund_close) }
  field :folio_id, value: ->(f) { SearchHelper.sanitize_text_for_search(f.folio_id) }
  field :fund_name, value: ->(f) { SearchHelper.sanitize_text_for_search(f.fund.name) }
  field :entity_name, value: ->(f) { SearchHelper.sanitize_text_for_search(f.entity.name) }
  field :investor_name, value: ->(f) { SearchHelper.sanitize_text_for_search(f.investor_name) }
  field :kyc_full_name, value: ->(f) { SearchHelper.sanitize_text_for_search(f.investor_kyc&.full_name) }
end
