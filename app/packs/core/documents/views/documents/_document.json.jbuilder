json.extract! document, :id, :name, :entity_id, :created_at, :updated_at
json.url document_url(document, format: :json)
json.s3_url document.file.url(expires_in: 60 * 60 * 24 * 7)
