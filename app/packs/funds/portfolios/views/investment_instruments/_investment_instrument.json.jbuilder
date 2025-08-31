json.extract! investment_instrument, :id, :name, :currency, :category, :sub_category, :sector, :entity_id, :portfolio_company_id, :deleted_at, :created_at, :updated_at
json.url investment_instrument_url(investment_instrument, format: :json)
