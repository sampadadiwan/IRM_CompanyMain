json.extract! capital_commitment, :id, :entity_id, :investor_id, :fund_id, :committed_amount, :collected_amount, :unit_type, :percentage, :notes, :created_at, :updated_at
json.url capital_commitment_url(capital_commitment, format: :json)
