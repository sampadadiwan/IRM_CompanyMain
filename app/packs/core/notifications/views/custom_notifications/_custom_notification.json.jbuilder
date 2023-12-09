json.extract! custom_notification, :id, :subject, :body, :whatsapp, :entity_id, :owner_id, :owner_type, :created_at, :updated_at
json.url custom_notification_url(custom_notification, format: :json)
