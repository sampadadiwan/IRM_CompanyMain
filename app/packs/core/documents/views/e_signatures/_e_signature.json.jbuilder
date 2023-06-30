json.extract! e_signature, :id, :entity_id, :user_id, :label, :signature_type, :sequence, :owner_id, :owner_type, :notes, :status, :created_at, :updated_at
json.url e_signature_url(e_signature, format: :json)
