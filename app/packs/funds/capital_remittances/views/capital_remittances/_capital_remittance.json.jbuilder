json.extract! capital_remittance, :id, :entity_id, :fund_id, :capital_call_id, :investor_id, :status, :call_amount, :collected_amount, :notes, :created_at, :updated_at
json.url capital_remittance_url(capital_remittance, format: :json)
