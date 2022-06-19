json.extract! message, :id, :user_id, :content, :owner_id, :owner_type, :created_at, :updated_at
json.url message_url(message, format: :json)
json.content message.content.to_s
