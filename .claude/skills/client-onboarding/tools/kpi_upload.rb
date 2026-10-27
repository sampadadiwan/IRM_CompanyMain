# Loads one MIS workbook through KpiWorkbookReader: POST /kpi_reports.json for the month's report with the workbook as
# its "KPIs" document and upload_new_kpis=true, which queues ImportKpiWorkbookJob. The job stages UNAPPROVED KPIs on one
# report per period found in the file. This tool waits until the company's KPI count stops changing, then prints it.
# Run kpi_dry_run.rb + check_dryrun_cells.rb first, and kpi_recon.rb after, before approving.
# One workbook per month: merge a client's several files first (merge_mis.rb) — never put a file on another period's report.
#
# Usage: ruby kpi_upload.rb [--workspace DIR] --company ID --file X.xlsx [--as-of 2026-08-31] [--period Month]
require "optparse"
require_relative "api"

api = Onboarding::Api.new(Onboarding::Api.workspace_from!(ARGV))
opts = { period: "Month" }
OptionParser.new do |o|
  o.on("--company ID", Integer) { opts[:company] = _1 }
  o.on("--file PATH") { opts[:file] = _1 }
  o.on("--as-of DATE") { opts[:as_of] = _1 }
  o.on("--period PERIOD") { opts[:period] = _1 }
end.parse!(ARGV)
abort File.read(__FILE__).lines.grep(/^# Usage/).join unless opts[:company] && opts[:file] && opts[:as_of]
abort "no such file: #{opts[:file]}" unless File.exist?(opts[:file])

kpi_count = -> { api.list("/kpis.json?q[portfolio_company_id_eq]=#{opts[:company]}&all=true").size }
before = kpi_count.()

# ① The month's report, with the workbook as its "KPIs" document (a plain multipart file)
status, body = api.call("post", "/kpi_reports.json", multipart: {
  "kpi_report[portfolio_company_id]" => opts[:company], "kpi_report[entity_id]" => api.entity_id,
  "kpi_report[as_of]" => opts[:as_of], "kpi_report[period]" => opts[:period], "kpi_report[tag_list]" => "Actual",
  "kpi_report[upload_new_kpis]" => "true", "kpi_report[update_existing_kpis]" => "true",
  "kpi_report[documents_attributes][0][name]" => "KPIs", "kpi_report[documents_attributes][0][file]" => File.open(opts[:file], "rb")
})
abort "POST /kpi_reports.json → HTTP #{status} #{body.to_s.gsub(/\s+/, ' ')[0, 300]}" unless status == 201
puts "report #{body['id']} (#{body['period']} #{body['as_of']}) created; waiting for the reader job…"

# ② Wait for the job: the company's KPI count settles
after = api.wait_until_stable(label: "Reading KPIs", unit: "KPIs") { n = kpi_count.(); n > before ? n : nil }
puts "KPIs for company #{opts[:company]}: #{before} → #{after.inspect} (#{after.to_i - before} staged, unapproved)"
