json.extract! investor, :id, :investor_name, :tag_list, :investor_entity_id, :entity_id, :category, :created_at, :updated_at
json.url investor_url(investor, format: :json)
json.value investor.investor_name

json.custom_fields investor.json_fields
