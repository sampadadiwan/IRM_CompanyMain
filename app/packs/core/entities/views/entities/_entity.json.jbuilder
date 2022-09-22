json.extract! entity, :id, :name, :url, :category, :founded, :entity_type, :logo_url,
              :created_at, :updated_at
json.url entity_url(entity, format: :json)
json.value entity.name
