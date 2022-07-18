json.extract! approval_response, :id, :entity_id, :approval_id, :status, :created_at, :updated_at
json.url approval_response_url(approval_response, format: :json)
