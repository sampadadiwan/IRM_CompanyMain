json.extract! secondary_sale, :id, :name, :entity_id, :start_date, :end_date, :percent_allowed, :min_price, :max_price, :active, :created_at, :updated_at
json.url secondary_sale_url(secondary_sale, format: :json)
json.active? secondary_sale.active?
