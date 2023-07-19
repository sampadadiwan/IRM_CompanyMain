json.extract! notification, :id, :recipient_id, :recipient_type, :type, :params, :read_at, :created_at, :updated_at
json.url notification_url(notification, format: :json)
