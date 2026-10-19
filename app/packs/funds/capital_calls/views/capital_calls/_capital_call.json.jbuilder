json.extract! capital_call, :id, :entity_id, :fund_id, :name, :percentage_called, :due_date, :call_date, :notes, :created_at, :updated_at
json.url capital_call_url(capital_call, format: :json)
# G17 / G18 (phase 10): approval can be read back; units_job_finished_at says when the last allocate-units job ended
json.extract! capital_call, :approved, :approved_by_user_id, :units_job_finished_at

# Fund details
json.fund_name capital_call.fund.name
# The currency the amounts below are in (funds-json-api-hardening H13)
json.currency capital_call.fund.currency

# Amounts
json.call_amount capital_call.call_amount.to_f
json.collected_amount capital_call.collected_amount.to_f
json.due_amount capital_call.due_amount.to_f

json.fund_closes capital_call.fund_closes&.join(',')
# G21 (client onboarding): CapitalCall#setup_defaults zeroes percentage_called for every basis but
# "Percentage of Commitment" (by design); the percentage per close the client sent is kept in close_percentages
json.extract! capital_call, :call_basis, :close_percentages
json.custom_fields capital_call.json_fields
