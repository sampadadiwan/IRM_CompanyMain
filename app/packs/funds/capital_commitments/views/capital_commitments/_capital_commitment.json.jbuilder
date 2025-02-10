json.extract! capital_commitment, :id, :entity_id, :investor_id, :fund_id, :committed_amount, :collected_amount, :call_amount, :distribution_amount, :folio_id, :investor_name, :unit_type, :notes, :created_at, :updated_at, :folio_currency

json.url capital_commitment_url(capital_commitment, format: :json)

json.investor_link link_to(capital_commitment.investor_name, capital_commitment.investor)
json.folio_link link_to(capital_commitment.folio_id, capital_commitment)

json.percentage capital_commitment.percentage.to_f.round(2)
json.full_name capital_commitment.investor_kyc&.full_name
json.committed_amount_number capital_commitment.committed_amount.to_f
json.call_amount_number capital_commitment.call_amount.to_f
json.collected_amount_number capital_commitment.collected_amount.to_f
json.distribution_amount_number capital_commitment.distribution_amount.to_f
json.fund_currency capital_commitment.fund.currency
json.fund_name capital_commitment.fund.name

json.dt_actions begin
  links = []
  links << link_to('Show', capital_commitment_path(capital_commitment), class: "btn btn-outline-primary")
  links << link_to('Edit', edit_capital_commitment_path(capital_commitment), class: "btn btn-outline-success") if policy(capital_commitment).update?
  safe_join(links, '')
end
