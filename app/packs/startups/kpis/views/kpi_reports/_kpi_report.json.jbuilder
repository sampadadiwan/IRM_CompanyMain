json.extract! kpi_report, :id, :entity_id, :as_of, :notes, :user_id, :created_at, :updated_at
# G32 (client onboarding): which company and period the report is, and where its import and check
# stand — two reports as of the same date (a Month and a Quarter) are told apart by period
json.extract! kpi_report, :portfolio_company_id, :period, :tag_list, :status, :import_status, :validated_at
json.portfolio_company_name kpi_report.portfolio_company&.investor_name
json.validation_ok kpi_report.validation_result.is_a?(Hash) ? kpi_report.validation_result['ok'] : nil
json.url kpi_report_url(kpi_report, format: :json)
