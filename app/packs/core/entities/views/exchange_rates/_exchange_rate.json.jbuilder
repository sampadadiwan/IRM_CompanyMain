json.extract! exchange_rate, :id, :entity_id, :from, :to, :rate, :as_of, :latest, :notes, :created_at, :updated_at
json.url exchange_rate_url(exchange_rate, format: :json)
