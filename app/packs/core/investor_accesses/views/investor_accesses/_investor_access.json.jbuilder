json.extract! investor_access, :id, :investor_id, :user_id, :email, :approved, :granted_by, :entity_id, :created_at, :updated_at
json.url investor_access_url(investor_access, format: :json)
