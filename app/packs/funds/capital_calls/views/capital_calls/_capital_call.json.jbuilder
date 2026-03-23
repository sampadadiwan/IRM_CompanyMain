json.extract! capital_call, :id, :entity_id, :fund_id, :name, :percentage_called, :due_date, :call_date, :notes, :created_at, :updated_at
json.url capital_call_url(capital_call, format: :json)

# Fund details
json.fund_name capital_call.fund.name

# Amounts
json.call_amount capital_call.call_amount.to_f
json.collected_amount capital_call.collected_amount.to_f
json.due_amount capital_call.due_amount.to_f

json.fund_closes capital_call.fund_closes&.join(',')
json.custom_fields capital_call.json_fields
