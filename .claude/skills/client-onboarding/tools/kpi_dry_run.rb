# Dry run of KpiWorkbookReader through the API: POST /kpi_reports/validate_upload.json for one MIS workbook. Writes
# nothing in the app. Saves the verdict to <workspace>/out/kpi_dryrun/<file name>.json and prints a summary: errors,
# warnings, cells read per sheet, and any cell read from a sheet other than its mapping's Source Sheet.
#
# Usage: ruby kpi_dry_run.rb [--workspace DIR] --company ID --file X.xlsx [--as-of 2026-08-31] [--period Month]
require "optparse"
require "fileutils"
require_relative "api"

api = Onboarding::Api.new(Onboarding::Api.workspace_from!(ARGV))
opts = { as_of: nil, period: "Month" }
OptionParser.new do |o|
  o.on("--company ID", Integer) { opts[:company] = _1 }
  o.on("--file PATH") { opts[:file] = _1 }
  o.on("--as-of DATE") { opts[:as_of] = _1 }
  o.on("--period PERIOD") { opts[:period] = _1 }
end.parse!(ARGV)
abort File.read(__FILE__).lines.grep(/^# Usage/).join unless opts[:company] && opts[:file]
abort "no such file: #{opts[:file]}" unless File.exist?(opts[:file])
as_of = opts[:as_of] || Date.today.prev_month.then { Date.new(_1.year, _1.month, -1) }.iso8601 # last month-end by default

# ① The reader's verdict on the workbook, in the context of a report for this company + period
status, verdict = api.call("post", "/kpi_reports/validate_upload.json", multipart: {
  "kpi_report[portfolio_company_id]" => opts[:company], "kpi_report[as_of]" => as_of, "kpi_report[period]" => opts[:period],
  "file" => File.open(opts[:file], "rb")
})
abort "validate_upload → HTTP #{status} #{verdict.to_s[0, 300]}" unless status == 200 && verdict.is_a?(Hash)

out_dir = File.join(api.workspace, "out", "kpi_dryrun")
FileUtils.mkdir_p(out_dir)
out = File.join(out_dir, "#{File.basename(opts[:file], '.*')}.json")
File.write(out, JSON.pretty_generate(verdict))

# ② Summary, and every ok cell checked against its mapping's Source Sheet (a scoped mapping must read only its sheet)
ok = verdict["cells"].select { _1["status"] == "ok" }
sheet_of = api.list("/investor_kpi_mappings.json?investor_id=#{opts[:company]}").to_h { [_1["id"], _1["source_sheet"]] }
off_sheet = ok.select { |c| (s = sheet_of[c["mapping_id"]]) && s.casecmp?(c["ref"].split("!").first).!  }
puts "#{File.basename(opts[:file])} (company #{opts[:company]}, #{opts[:period]} #{as_of}): ok=#{verdict['ok']}"
puts "  errors:   #{verdict['errors'].map { _1['code'] }.tally}"
verdict["errors"].first(5).each { puts "    ✖ #{_1['message'][0, 180]}" }
puts "  warnings: #{verdict['warnings'].map { _1['code'] }.tally}"
puts "  ok cells: #{ok.size} — by sheet #{ok.map { _1['sheet'] }.tally}"
puts "  ok cells read from a sheet other than their mapping's Source Sheet: #{off_sheet.size}"
off_sheet.first(5).each { puts "    ✖ #{_1['ref']} #{_1['standard_kpi']} (mapping sheet #{sheet_of[_1['mapping_id']]})" }
puts "  verdict → #{out}"
exit(verdict["ok"] && off_sheet.empty? ? 0 : 1)
