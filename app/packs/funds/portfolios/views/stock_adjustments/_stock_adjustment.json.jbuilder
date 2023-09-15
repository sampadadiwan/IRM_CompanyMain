json.extract! stock_adjustment, :id, :entity_id, :portfolio_company_id, :user_id, :adjustment, :notes, :created_at, :updated_at
json.url stock_adjustment_url(stock_adjustment, format: :json)
