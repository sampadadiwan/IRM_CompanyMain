# Ties the KPIs the app stored from ONE MIS workbook to that workbook, through the API only. Run it after kpi_upload.rb
# (before approving) and again after approving (for the computed KPIs). Exits non-zero on any failed check.
#   ① every stored KPI's value equals the source cell its notes name ("Sheet: …, Row: r, Col: c", c 0-based)
#   ② it sits on the period/date the dry run read from that column's header, one-to-one with the dry run's ok cells
#   ③ nothing stored from this workbook without a dry-run cell
#   ④ every computed KPI (compute mapping) equals the sum of its approved components in the same report
# A company can hold KPIs from several workbooks; only those whose notes name this workbook's document are checked
# (the document most KPIs pointing at this workbook's sheets came from).
#
# Usage: ruby kpi_recon.rb [--workspace DIR] --company ID --file X.xlsx --verdict out/kpi_dryrun/X.json
require "optparse"
require "roo"
require_relative "api"

api = Onboarding::Api.new(Onboarding::Api.workspace_from!(ARGV))
opts = {}
OptionParser.new do |o|
  o.on("--company ID", Integer) { opts[:company] = _1 }
  o.on("--file PATH") { opts[:file] = _1 }
  o.on("--verdict PATH") { opts[:verdict] = _1 }
end.parse!(ARGV)
abort File.read(__FILE__).lines.grep(/^# Usage/).join unless opts[:company] && opts[:file] && opts[:verdict]
company = opts[:company]
book = Roo::Spreadsheet.open(opts[:file])
TOL = 0.01

# ── Read the app ─────────────────────────────────────────────────────────────────────────────────────────────────────
# Filter KPIs with ransack and re-check the company on every row (a bare portfolio_company_id was once ignored)
kpis = api.list("/kpis.json?q[portfolio_company_id_eq]=#{company}&all=true").select { _1["portfolio_company_id"] == company }
reports = api.list("/kpi_reports.json?portfolio_company_id=#{company}&all=true").to_h { [_1["id"], _1] }
mappings = api.list("/investor_kpi_mappings.json?investor_id=#{company}").to_h { [_1["id"], _1] }
dry = JSON.parse(File.read(opts[:verdict]))["cells"].select { _1["status"] == "ok" }

doc_of = ->(k) { k["notes"].to_s[/\AImported from Document (\d+)/, 1] }
sheet_of = ->(k) { k["notes"].to_s[/Sheet: (.+?), Period:/m, 1] }
this_doc = kpis.select { doc_of.(_1) && book.sheets.include?(sheet_of.(_1)) }.map(&doc_of).tally.max_by(&:last)&.first
abort "no KPIs from #{File.basename(opts[:file])} yet (extraction still running, or nothing stored) — #{kpis.size} KPIs for the company" if this_doc.nil?
extracted = kpis.select { doc_of.(_1) == this_doc }

issues = []
checks = Hash.new(0)
check = ->(name, ok, msg) { checks[name] += 1; issues << [name, msg] unless ok }

# ── ① value = the source cell the KPI's notes name ───────────────────────────────────────────────────────────────────
extracted.each do |k|
  m = k["notes"].match(/Sheet: (.+?), Period: .*Row: (\d+), Col: (\d+)/m)
  check.("① notes name a cell", !m.nil?, "kpi #{k['id']} notes #{k['notes'].inspect}")
  next unless m

  src = book.sheet(m[1]).cell(m[2].to_i, m[3].to_i + 1) # notes columns are 0-based, Roo's 1-based
  check.("① value = source cell", src.is_a?(Numeric) && (src - k["value"].to_f).abs < TOL,
         "kpi #{k['id']} #{k['name']} #{m[1]}!r#{m[2]}c#{m[3].to_i + 1}: source #{src.inspect} vs stored #{k['value']}")
end

# ── ②③ one-to-one with the dry run (mapping + period type + as_of), values equal ────────────────────────────────────
pool = extracted.map { |k| r = reports[k["kpi_report_id"]] || {}; [k["investor_kpi_mapping_id"], r["period"], r["as_of"], k] }
dry.each do |c|
  i = pool.index { |mid, period, as_of, _| mid == c["mapping_id"] && period == c["period_type"] && as_of == c["parsed_period"] }
  check.("② dry-run cell stored (mapping, period, date)", !i.nil?, "#{c['standard_kpi']} #{c['period_type']} #{c['parsed_period']} (#{c['ref']}) not stored")
  next unless i

  k = pool.delete_at(i).last
  check.("② stored value = dry-run value", (k["value"].to_f - c["stored"].to_f).abs < TOL, "#{c['standard_kpi']} #{c['parsed_period']}: dry #{c['stored']} vs #{k['value']}")
end
check.("③ nothing stored without a dry-run cell", pool.empty?, "#{pool.size} extra: #{pool.first(5).map { _1.last.slice('id', 'name') }}")

# ── ④ computed KPIs = Σ approved components in the same report (present only after approval) ────────────────────────
mappings.values.select { _1["autofill"] == "compute" }.each do |cm|
  terms = cm["compute_formula"].to_s.split("+").map(&:strip)
  reports.each_value do |r|
    stored = kpis.find { _1["kpi_report_id"] == r["id"] && _1["name"] == cm["standard_kpi_name"] }
    parts = terms.map { |t| kpis.find { _1["kpi_report_id"] == r["id"] && _1["name"] == t && _1["status"] == "approved" } }
    next unless parts.all?

    want = parts.sum { _1["value"].to_f }
    check.("④ computed = Σ components", stored && (stored["value"].to_f - want).abs < TOL,
           "#{cm['standard_kpi_name']} #{r['period']} #{r['as_of']}: Σ #{want.round(2)} vs #{stored&.dig('value').inspect}")
  end
end

# ── Report ───────────────────────────────────────────────────────────────────────────────────────────────────────────
puts "#{File.basename(opts[:file])} (company #{company}, document #{this_doc}): #{extracted.size} KPIs from this file, " \
     "#{kpis.size} for the company, status #{kpis.map { _1['status'] }.tally}, on #{reports.size} reports"
checks.each do |name, n|
  failed = issues.count { _1.first == name }
  puts format("  %-48s %5d checked  %s", name, n, failed.zero? ? "✅" : "❌ #{failed}")
end
issues.first(15).each { |name, msg| puts "    ✖ #{name}: #{msg}" }
exit(issues.empty? ? 0 : 1)
