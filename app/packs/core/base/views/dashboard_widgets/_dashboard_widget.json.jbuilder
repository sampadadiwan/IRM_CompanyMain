json.extract! dashboard_widget, :id, :name, :entity_id, :owner_id, :owner_type, :template, :position, :metadata, :enabled, :created_at, :updated_at
json.url dashboard_widget_url(dashboard_widget, format: :json)
