json.extract! kpi, :id, :entity_id, :name, :value, :display_value, :notes, :kpi_report_id, :created_at, :updated_at
# G31 (client onboarding): enough to check an extraction before approving it — which report, company
# and mapping a value belongs to, whether it is approved, and the value as read before conversion
json.extract! kpi, :portfolio_company_id, :investor_kpi_mapping_id, :import_upload_id, :status, :original_value, :source
json.url kpi_url(kpi, format: :json)
