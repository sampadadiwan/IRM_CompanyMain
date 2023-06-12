json.extract! kpi_report, :id, :entity_id, :as_of, :notes, :user_id, :created_at, :updated_at
json.url kpi_report_url(kpi_report, format: :json)
