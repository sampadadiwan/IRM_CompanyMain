json.extract! stock_conversion, :id, :entity_id, :portfolio_investment_id, :fund_id, :from_instrument_id, :from_quantity, :to_instrument_id, :to_quantity, :note, :created_at, :updated_at
json.url stock_conversion_url(stock_conversion, format: :json)
