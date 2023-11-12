json.extract! report, :id, :entity_id, :user_id, :name, :description, :url, :created_at, :updated_at
json.url report_url(report, format: :json)
