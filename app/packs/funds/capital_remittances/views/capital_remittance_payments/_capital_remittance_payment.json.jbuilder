json.extract! capital_remittance_payment, :id, :fund_id, :capital_remittance_id, :entity_id, :payment_date, :payment_notification_sent, :notes, :reference_no, :created_at, :updated_at
json.url capital_remittance_payment_url(capital_remittance_payment, format: :json)

# Fund details
json.fund_name capital_remittance_payment.fund.name

# Amounts
json.amount capital_remittance_payment.amount.to_f
json.folio_amount capital_remittance_payment.folio_amount.to_f

# Investing Entity / Folio details
json.investor_name capital_remittance_payment.investor&.investor_name
json.investing_entity capital_remittance_payment.investor_kyc&.full_name
json.folio_id capital_remittance_payment.capital_commitment&.folio_id
json.folio_currency capital_remittance_payment.capital_commitment&.folio_currency.to_s

# Tracking currency
json.tracking_amount capital_remittance_payment.tracking_amount.to_f

json.custom_fields capital_remittance_payment.json_fields
