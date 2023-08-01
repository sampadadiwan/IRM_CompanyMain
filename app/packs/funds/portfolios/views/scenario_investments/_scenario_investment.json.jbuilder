json.extract! scenario_investment, :id, :entity_id, :fund_id, :portfolio_scenario_id, :user_id, :transaction_date, :portfolio_company_id, :price, :quantity, :notes, :created_at, :updated_at
json.url scenario_investment_url(scenario_investment, format: :json)
