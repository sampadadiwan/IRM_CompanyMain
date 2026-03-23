json.extract! capital_remittance, :id, :entity_id, :fund_id, :capital_call_id, :capital_commitment_id, :investor_id, :status, :verified, :payment_date, :remittance_date, :notes, :created_at, :updated_at
json.url capital_remittance_url(capital_remittance, format: :json)

# Fund details
json.fund_name capital_remittance.fund.name
json.fund_currency capital_remittance.fund.currency

# Investor / Folio details
json.investor_name capital_remittance.investor_name
json.folio_id capital_remittance.folio_id
json.investing_entity capital_remittance.investor_kyc&.full_name

# Capital call details
json.capital_call_name capital_remittance.capital_call.name
json.percentage_called capital_remittance.capital_call.percentage_called

# Amounts
json.call_amount capital_remittance.call_amount.to_f
json.collected_amount capital_remittance.collected_amount.to_f
json.committed_amount capital_remittance.committed_amount.to_f
json.due_amount capital_remittance.due_amount.to_f
json.capital_fee capital_remittance.capital_fee.to_f
json.other_fee capital_remittance.other_fee.to_f
json.investment_amount capital_remittance.investment_amount.to_f

# Folio currency amounts
json.folio_currency capital_remittance.capital_commitment.folio_currency
json.folio_call_amount capital_remittance.folio_call_amount.to_f
json.folio_collected_amount capital_remittance.folio_collected_amount.to_f
json.folio_committed_amount capital_remittance.folio_committed_amount.to_f
json.folio_due_amount capital_remittance.folio_due_amount.to_f
json.folio_capital_fee capital_remittance.folio_capital_fee.to_f
json.folio_other_fee capital_remittance.folio_other_fee.to_f
json.folio_investment_amount capital_remittance.folio_investment_amount.to_f

# Tracking currency amounts
json.tracking_collected_amount capital_remittance.tracking_collected_amount.to_f
json.tracking_call_amount capital_remittance.tracking_call_amount.to_f

json.units_quantity capital_remittance.units_quantity.to_f

json.custom_fields capital_remittance.json_fields
