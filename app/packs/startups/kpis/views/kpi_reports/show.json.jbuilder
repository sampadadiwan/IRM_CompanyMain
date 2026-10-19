json.partial! "kpi_reports/kpi_report", kpi_report: @kpi_report
# G32: the full workbook check (errors, warnings, every cell read) and the report's KPIs — show only,
# both can be large
json.validation_result @kpi_report.validation_result
json.kpis @kpi_report.kpis, partial: "kpis/kpi", as: :kpi
