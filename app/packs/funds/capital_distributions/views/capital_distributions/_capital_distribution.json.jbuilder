json.extract! capital_distribution, :id, :fund_id, :entity_id, :form_type_id, :title, :distribution_date, :created_at, :updated_at
json.url capital_distribution_url(capital_distribution, format: :json)
# G17 / G18 (phase 10): approval can be read back; units_job_finished_at says when the last redeem-units job ended
json.extract! capital_distribution, :approved, :approved_by_user_id, :units_job_finished_at

# Fund details
json.fund_name capital_distribution.fund.name
# The currency the amounts below are in (funds-json-api-hardening H13)
json.currency capital_distribution.fund.currency

# Amounts
json.gross_amount capital_distribution.gross_amount.to_f
# carry_cents is not monetized on CapitalDistribution, so read the cents (the bare getter raised and
# made every distribution JSON answer a 500); same major-unit value as the other amounts
json.carry capital_distribution.carry_cents.to_f / 100
# Payments amount
json.payments capital_distribution.distribution_amount.to_f
json.distribution_amount capital_distribution.distribution_amount.to_f
json.reinvestment capital_distribution.reinvestment.to_f
json.face_value_for_redemption capital_distribution.cost_of_investment.to_f
json.cost_of_investment capital_distribution.cost_of_investment.to_f
json.completed_distribution_amount capital_distribution.completed_distribution_amount.to_f
json.income capital_distribution.income.to_f
json.fee capital_distribution.fee.to_f

json.unit_prices capital_distribution.unit_prices

json.custom_fields capital_distribution.json_fields
