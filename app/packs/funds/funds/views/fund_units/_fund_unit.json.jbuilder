json.extract! fund_unit, :id, :fund_id, :capital_commitment_id, :investor_id, :unit_type, :quantity, :reason, :issue_date, :created_at, :updated_at
json.price fund_unit.price.to_f
json.amount fund_unit.amount.to_f
json.url fund_unit_url(fund_unit, format: :json)
