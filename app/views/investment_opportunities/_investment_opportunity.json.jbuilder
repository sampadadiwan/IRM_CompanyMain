json.extract! investment_opportunity, :id, :entity_id, :company_name, :fund_raise_amount, :valuation, :min_ticket_size, :last_date, :currency, :created_at, :updated_at
json.url investment_opportunity_url(investment_opportunity, format: :json)
