json.extract! kpi, :id, :entity_id, :name, :value, :display_value, :notes, :kpi_report_id, :created_at, :updated_at
json.url kpi_url(kpi, format: :json)
