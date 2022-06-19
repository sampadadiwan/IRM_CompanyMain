json.extract! task, :id, :details, :entity_id, :investor_id, :owner_id, :owner_name, :completed, :user_id, :created_at, :updated_at
json.url task_url(task, format: :json)
