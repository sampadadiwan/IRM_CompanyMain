json.extract! capital_commitment, :id, :entity_id, :investor_id, :fund_id, :folio_id, :investor_name, :unit_type, :notes, :created_at, :updated_at, :folio_currency

json.url capital_commitment_url(capital_commitment, format: :json)

json.investor_link link_to(capital_commitment.investor_name, capital_commitment.investor)
json.folio_link link_to(capital_commitment.folio_id, capital_commitment)

json.percentage capital_commitment.percentage.to_f.round(2)
json.full_name capital_commitment.investor_kyc&.full_name
json.committed_amount capital_commitment.committed_amount.to_f
json.call_amount capital_commitment.call_amount.to_f
json.collected_amount capital_commitment.collected_amount.to_f
json.distribution_amount capital_commitment.distribution_amount.to_f
json.fund_currency capital_commitment.fund.currency
json.fund_name capital_commitment.fund.name

json.investor_kyc capital_commitment.investor_kyc&.as_json
json.investor capital_commitment.investor&.as_json
json.custom_fields capital_commitment.json_fields

json.dt_actions begin
  links = []
  links << link_to('Show', capital_commitment_path(capital_commitment), class: "btn btn-outline-primary ti ti-eye")
  links << link_to('Edit', edit_capital_commitment_path(capital_commitment), class: "btn btn-outline-success ti ti-edit") if policy(capital_commitment).update?
  safe_join(links, '')
end
