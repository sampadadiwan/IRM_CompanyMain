json.extract! valuation, :id, :entity_id, :valuation_date, :created_at, :updated_at
json.url valuation_url(valuation, format: :json)
json.per_share_value valuation.per_share_value.to_f.round(2)
