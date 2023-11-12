json.extract! ci_widget, :id, :ci_profile_id, :entity_id, :title, :details, :url, :created_at, :updated_at
json.url ci_widget_url(ci_widget, format: :json)
