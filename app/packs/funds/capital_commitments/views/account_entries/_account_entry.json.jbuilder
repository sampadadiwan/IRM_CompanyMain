json.extract! account_entry, :id, :capital_commitment_id, :entity_id, :fund_id, :investor_id, :folio_id, :entry_type, :name, :notes, :created_at, :updated_at, :reporting_date, :period, :cumulative, :parent_type, :parent_id, :parent_name, :commitment_name, :generated, :exchange_rate_id, :fund_formula_id, :rule_for, :import_upload_id, :allocation_run_id

json.amount_number account_entry.amount.to_f
json.amount account_entry.amount.to_f
json.folio_amount account_entry.folio_amount.to_f
json.custom_fields account_entry.json_fields

json.folio_id account_entry.capital_commitment&.folio_id
json.unit_type account_entry.capital_commitment&.unit_type
json.fund_name account_entry.fund.name
json.url account_entry_url(account_entry, format: :json)
json.fund_currency account_entry.fund.currency
json.name_link link_to(account_entry.name, account_entry)
json.folio_link link_to(account_entry.folio_id, capital_commitment_path(id: account_entry.capital_commitment_id)) if account_entry.folio_id && account_entry.capital_commitment_id

json.investor_name account_entry.investor&.investor_name

json.dt_actions begin
  links = []
  links << link_to('Show', account_entry_path(account_entry), class: "btn btn-outline-primary ti ti-eye")
  links << link_to('Edit', edit_account_entry_path(account_entry), class: "btn btn-outline-success ti ti-edit") if policy(account_entry).update?
  safe_join(links, '')
end
