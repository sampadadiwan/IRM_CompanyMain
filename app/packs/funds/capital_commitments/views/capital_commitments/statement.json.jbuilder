# One folio's statement (funds-json-api-hardening ⑦ — H9 E12 E13). Amounts in major units: fund
# currency unless the key says folio_.
commitment = @statement.capital_commitment
cents = ->(value) { value.to_f / 100 }

json.capital_commitment_id commitment.id
json.folio_id commitment.folio_id
json.fund_id commitment.fund_id
json.currency commitment.fund.currency
json.folio_currency commitment.folio_currency

# Called, collected and due across the folio, as on the commitment page
json.committed_amount commitment.committed_amount.to_f
json.call_amount commitment.call_amount.to_f
json.collected_amount commitment.collected_amount.to_f
json.due_amount commitment.due_amount.to_f
json.distribution_amount commitment.distribution_amount.to_f

json.remittances @statement.remittances do |remittance|
  json.id remittance.id
  json.capital_call_id remittance.capital_call_id
  json.call_name remittance.call_name
  json.call_date remittance.call_date
  json.due_date remittance.due_date
  json.status remittance.status
  json.call_amount cents.call(remittance.call_amount_cents)
  json.collected_amount cents.call(remittance.collected_amount_cents)
  json.due_amount cents.call(remittance.call_amount_cents.to_d - remittance.collected_amount_cents.to_d)
  json.folio_call_amount cents.call(remittance.folio_call_amount_cents)
  json.folio_collected_amount cents.call(remittance.folio_collected_amount_cents)
end

json.remittance_payments @statement.remittance_payments do |payment|
  json.id payment.id
  json.capital_remittance_id payment.capital_remittance_id
  json.payment_date payment.payment_date
  json.reference_no payment.reference_no
  json.amount cents.call(payment.amount_cents)
  json.folio_amount cents.call(payment.folio_amount_cents)
end

json.distribution_payments @statement.distribution_payments do |payment|
  json.id payment.id
  json.capital_distribution_id payment.capital_distribution_id
  json.payment_date payment.payment_date
  json.completed payment.completed
  json.income cents.call(payment.income_cents)
  json.net_payable cents.call(payment.net_payable_cents)
  json.folio_amount cents.call(payment.folio_amount_cents)
end

# E13: totals by entry type, never the entries (they are at /account_entries.json?capital_commitment_id=)
json.ledger_totals @statement.ledger_totals
