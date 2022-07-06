json.extract! reminder, :id, :entity_id, :owner_id, :owner_type, :unit, :count, :sent, :created_at, :updated_at
json.url reminder_url(reminder, format: :json)
