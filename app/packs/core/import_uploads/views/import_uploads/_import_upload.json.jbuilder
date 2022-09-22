json.extract! import_upload, :id, :name, :entity_id, :owner_id, :owner_type, :user_id, :import_type, :status, :error_text, :created_at, :updated_at
json.url import_upload_url(import_upload, format: :json)
