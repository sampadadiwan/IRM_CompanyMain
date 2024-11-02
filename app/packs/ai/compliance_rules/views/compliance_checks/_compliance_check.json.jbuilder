json.extract! compliance_check, :id, :entity_id, :parent_id, :parent_type, :owner_id, :owner_type, :status, :explanation, :created_at, :updated_at
json.url compliance_check_url(compliance_check, format: :json)
