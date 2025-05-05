json.extract! account_entry, :id, :capital_commitment_id, :entity_id, :fund_id, :investor_id, :folio_id, :entry_type, :name, :amount, :notes, :created_at, :updated_at

json.amount_number account_entry.amount.to_f
json.amount_cents account_entry.amount_cents
json.reporting_date l(account_entry.reporting_date)
json.unit_type account_entry.capital_commitment&.unit_type
json.fund_name account_entry.fund.name
json.url account_entry_url(account_entry, format: :json)
json.fund_currency account_entry.fund.currency
json.name_link link_to(account_entry.name, account_entry)
json.folio_link link_to(account_entry.folio_id, capital_commitment_path(id: account_entry.capital_commitment_id)) if account_entry.folio_id

json.investor_name account_entry.investor&.investor_name

json.dt_actions begin
  links = []
  links << link_to('Show', account_entry_path(account_entry), class: "btn btn-outline-primary ti ti-eye")
  links << link_to('Edit', edit_account_entry_path(account_entry), class: "btn btn-outline-success ti ti-edit") if policy(account_entry).update?
  safe_join(links, '')
end
