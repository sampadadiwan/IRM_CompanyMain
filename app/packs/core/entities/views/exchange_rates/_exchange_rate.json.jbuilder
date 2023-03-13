json.extract! exchange_rate, :id, :entity_id, :from, :to, :rate, :created_at, :updated_at
json.url exchange_rate_url(exchange_rate, format: :json)
