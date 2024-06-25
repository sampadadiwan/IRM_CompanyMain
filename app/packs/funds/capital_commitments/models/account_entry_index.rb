class AccountEntryIndex < Chewy::Index
  SEARCH_FIELDS = %i[fund_name investor_name folio_id period entry_type name].freeze

  index_scope AccountEntry.includes(:entity, :fund, :investor)

  field :fund_name, value: ->(account_entry) { account_entry.fund&.name }
  field :investor_name, value: ->(account_entry) { account_entry.investor&.name }
  field :folio_id
  field :period
  field :entry_type
  field :name
  field :entity_id
end
