json.extract! portfolio_investment, :id, :entity_id, :fund_id, :investor_name, :investment_date, :amount, :quantity, :investment_type, :notes, :created_at, :updated_at
json.url portfolio_investment_url(portfolio_investment, format: :json)
