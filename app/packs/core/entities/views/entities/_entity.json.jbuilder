json.extract! entity, :id, :name, :url, :category, :founded, :entity_type, :logo_url,
              :created_at, :updated_at
# Tax id only for users related to this company (B1, EntityPolicy#full_details?).
json.pan entity.pan if respond_to?(:policy) && policy(entity).full_details?
json.url entity_url(entity, format: :json)
json.value entity.name
