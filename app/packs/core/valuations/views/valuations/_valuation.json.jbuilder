json.extract! valuation, :id, :entity_id, :owner_id, :owner_type, :investment_instrument_id, :valuation_date, :currency, :created_at, :updated_at
json.url valuation_url(valuation, format: :json)
json.per_share_value valuation.per_share_value.to_f.round(2)

# Portfolio company (owner when owner_type is Investor)
json.portfolio_company_name valuation.owner_type == "Investor" ? valuation.owner&.investor_name : nil

# Investment instrument details
json.investment_instrument_name valuation.investment_instrument&.name

json.custom_fields valuation.json_fields
