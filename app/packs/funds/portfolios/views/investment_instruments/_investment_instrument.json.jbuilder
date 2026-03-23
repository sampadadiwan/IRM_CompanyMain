json.extract! investment_instrument, :id, :name, :currency, :category, :sub_category, :sector, :investment_domicile, :entity_id, :portfolio_company_id, :deleted_at, :created_at, :updated_at
json.url investment_instrument_url(investment_instrument, format: :json)

# Portfolio company details
json.portfolio_company_name investment_instrument.portfolio_company.investor_name

json.custom_fields investment_instrument.json_fields
