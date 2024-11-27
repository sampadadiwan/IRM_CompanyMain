json.extract! viewed_by, :id, :owner_id, :owner_type, :user_id, :created_at, :updated_at
json.url viewed_by_url(viewed_by, format: :json)
