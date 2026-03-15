json.extract! incoming_email, :id, :from, :to, :subject, :body, :owner_id, :owner_type, :entity_id, :created_at, :updated_at
json.url incoming_email_url(incoming_email, format: :json)
