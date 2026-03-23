json.extract! capital_distribution_payment, :id, :fund_id, :entity_id, :capital_distribution_id, :capital_commitment_id, :investor_id, :form_type_id, :folio_id, :investor_name, :percentage, :units_quantity, :payment_date, :completed, :properties, :created_at, :updated_at
json.url capital_distribution_payment_url(capital_distribution_payment, format: :json)

# Fund details
json.fund_name capital_distribution_payment.fund.name

# Capital distribution details
json.capital_distribution_title capital_distribution_payment.capital_distribution.title

# Folio currency amounts
json.folio_currency capital_distribution_payment.capital_commitment&.folio_currency.to_s
json.folio_amount capital_distribution_payment.folio_amount.to_f
json.folio_payment_amount capital_distribution_payment.folio_amount.to_f

# Face Value for Redemption
json.cost_of_investment capital_distribution_payment.cost_of_investment.to_f
json.cost_of_investment_with_fees capital_distribution_payment.cost_of_investment_with_fees.to_f

# Fund currency amounts
json.income capital_distribution_payment.income.to_f
json.reinvestment capital_distribution_payment.reinvestment.to_f
json.reinvestment_with_fees capital_distribution_payment.reinvestment_with_fees.to_f
json.income_with_fees capital_distribution_payment.income_with_fees.to_f
json.gross_payable capital_distribution_payment.gross_payable.to_f
json.net_payable capital_distribution_payment.net_payable.to_f
json.gross_of_account_entries capital_distribution_payment.gross_of_account_entries.to_f
json.net_of_account_entries capital_distribution_payment.net_of_account_entries.to_f

# excel labels
json.face_value_for_redemption capital_distribution_payment.cost_of_investment.to_f
json.face_value_for_redemption_with_fees capital_distribution_payment.cost_of_investment_with_fees.to_f

# Tracking currency
json.tracking_net_payable capital_distribution_payment.tracking_net_payable.to_f

# KYC fields
json.bank_account capital_distribution_payment.investor_kyc&.bank_account_number
json.ifsc_code capital_distribution_payment.investor_kyc&.ifsc_code
json.investing_entity capital_distribution_payment.investor_kyc&.full_name
json.pan capital_distribution_payment.investor_kyc&.PAN

json.investor_kyc_id capital_distribution_payment.investor_kyc&.id

json.custom_fields capital_distribution_payment.json_fields
