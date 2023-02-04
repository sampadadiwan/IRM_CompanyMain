json.extract! account_entry, :id, :capital_commitment_id, :entity_id, :fund_id, :investor_id, :folio_id, :reporting_date, :entry_type, :name, :amount, :notes, :created_at, :updated_at
json.url account_entry_url(account_entry, format: :json)
