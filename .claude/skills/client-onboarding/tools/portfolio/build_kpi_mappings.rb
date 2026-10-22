# Builds the KPI mappings (InvestorKpiMapping import) from each company's KPI Info sheet and the `kpis:` rules in
# mappings/portfolio.yml, and lists the MIS workbooks to load. Every KPI value later comes from KpiWorkbookReader (via the
# KPI report API); a mapping tells it which MIS row label (Reported Kpi Name) feeds which standard KPI.
#   - one MIS line        → one mapping (Show In Report Yes)
#   - several MIS lines   → one mapping per line (plain standard name, Show In Report No) + a parent with Auto Fill
#                           "compute" summing the components' standard names
#   - "Not in MIS" etc.   → one mapping, reported = standard name; no values until the company reports it — or, with
#                           `skip_without_mis_line: { value: true, q: … }`, no mapping at all (also for an override of [])
#   - one MIS label per company: a second KPI on the same label becomes a compute copy of the first (the reader skips a
#     label with two mappings as ambiguous)
#   - Source Sheet (per company `source_sheet:` by label, then by category) only on mappings whose label is in a workbook
#     that will be loaded; the label must be on that sheet
#
# Labels are checked the way the reader matches them (lowercase, all whitespace removed, exact) against the row labels in
# the first 4 columns of every sheet of the company's workbooks (and `label_files`). It STOPS on any KPI Info line with no
# such label, listing near matches: add it to the company's `overrides:` (with a client question) and rebuild. A label
# the client still has to settle goes under `pending_labels: { q:, labels: [...] }`: kept as given (it fills in once the
# MIS has that line) and reported as a warning instead of stopping.
#
# Workbooks with `merge:` are merged first (merge_mis.rb → out/kpi/<name>.xlsx), one sheet per statement.
# Writes out/portfolio/09_kpi_mappings.xlsx and out/portfolio/kpi_workbooks.json [{company, name, path, as_of, period, hold}].
#
# Usage: ruby build_kpi_mappings.rb [--workspace DIR]
require "open3"
require "fileutils"
require_relative "../api"
require_relative "../gate"
require_relative "common"

P = Onboarding::Portfolio
workspace = Onboarding::Api.workspace_from!(ARGV)
cfg = P.config(workspace)
kcfg = cfg.fetch("kpis")
out = P.out_dir(workspace)
FileUtils.mkdir_p([out, File.join(workspace, "out", "kpi")])

# ── Gates: question ids, then the must-have answers (M16–M17) ───────────────────────────────────────────────────────
P.check_questions!(workspace, cfg)
Onboarding::Gate.check!(workspace, :kpis)
puts "✔ must-have gate: kpis may be built"

norm = ->(s) { s.to_s.downcase.gsub(/[[:space:]]+/, "") }
col = ->(letters) { letters.chars.reduce(0) { |a, ch| (a * 26) + ch.ord - 64 } }
kpi_col, mis_col = col.(kcfg.dig("info_columns", "kpi") || "A"), col.(kcfg.dig("info_columns", "mis") || "C")
categories = kcfg.fetch("categories")
not_in_mis = Regexp.new(kcfg.fetch("not_in_mis"), Regexp::IGNORECASE)
percent = Regexp.new(kcfg.dig("data_types", "percentage") || "\\(%\\)", Regexp::IGNORECASE)
numeric = Regexp.new(kcfg.dig("data_types", "numeric") || "\\A\\z", Regexp::IGNORECASE)
whole = kcfg.fetch("whole_labels", [])
skip_unlined = kcfg.dig("skip_without_mis_line", "value") == true

# Split a KPI Info cell into MIS labels: commas / newlines / " and ", keeping whole_labels intact
split_labels = lambda do |text|
  keep = {}
  whole.each_with_index do |w, i|
    next unless text.include?(w)

    keep["@@#{i}@@"] = w
    text = text.sub(w, "@@#{i}@@")
  end
  text.split(/,|\n| and /).map(&:strip).reject(&:empty?).map { keep.fetch(_1, _1) }
end
# A component's standard name: letters, digits and spaces only (the formula substitution matches names with \b)
plain = ->(name) { name.gsub(/[^0-9A-Za-z ]+/, " ").squeeze(" ").strip }

# ── Workbooks: merge where asked; list what each company will load ──────────────────────────────────────────────────
workbooks = []
kcfg.fetch("companies").each do |company, c|
  c.fetch("workbooks", []).each do |w|
    if w["merge"]
      path = File.join(workspace, "out", "kpi", "#{w.fetch('name')}.xlsx")
      specs = w["merge"].map { |sheet, (file, src_sheet)| "#{sheet}=#{File.join(workspace, 'source', file)}|#{src_sheet}" }
      o, s = Open3.capture2e(RbConfig.ruby, File.join(__dir__, "..", "merge_mis.rb"), path, *specs)
      o.each_line { puts "    #{_1}" }
      abort "✖ merging #{w['name']} failed" unless s.success?
    else
      path = File.join(workspace, "source", w.fetch("file"))
      abort "✖ no workbook #{path}" unless File.exist?(path)
    end
    workbooks << { company:, name: w["name"] || File.basename(w["file"], ".*"), path:, as_of: w.fetch("as_of").to_s,
                   period: w.fetch("period"), hold: w["hold"] }
  end
end

# Row labels per company: { normalised => [[sheet, workbook path], …] } from the first 4 columns, first 2000 rows
labels_in = lambda do |paths|
  index = Hash.new { |h, k| h[k] = [] }
  paths.each do |path|
    book = Roo::Spreadsheet.open(path)
    book.sheets.each do |s|
      sh = book.sheet(s)
      next unless sh.last_row

      (1..[sh.last_row, 2000].min).each do |r|
        (1..[sh.last_column.to_i, 4].min).each do |cc|
          v = sh.cell(r, cc)
          index[norm.(v)] << [s, path] if v.is_a?(String) && v.strip.size > 1
        end
      end
    end
  end
  index
end

# ── Mappings per company ────────────────────────────────────────────────────────────────────────────────────────────
rows = []
missing = []
warnings = []
kcfg.fetch("companies").each do |company, c|
  mine = workbooks.select { _1[:company] == company }
  loaded = labels_in.(mine.reject { _1[:hold] }.map { _1[:path] })
  all = labels_in.(mine.map { _1[:path] } + c.fetch("label_files", []).map { File.join(workspace, "source", _1) })
  overrides = c.dig("overrides", "map") || {}
  pending = Array(c.dig("pending_labels", "labels"))
  info = Roo::Spreadsheet.open(File.join(workspace, "source", c.dig("info", "file"))).sheet(c.dig("info", "sheet") || 0)
  company_rows = []
  block = 0
  previous_blank = false
  (info.first_row..info.last_row).each do |r|
    kpi, mis = info.cell(r, kpi_col).to_s.strip, info.cell(r, mis_col).to_s.strip
    if kpi.empty?
      previous_blank = true
      next
    end
    next if kpi == "KPI"

    # A blank row between KPIs starts the next block (Income Statement, Balance Sheet, …)
    block += 1 if previous_blank && company_rows.any?
    previous_blank = false
    category = categories.fetch(block, categories.last)
    data_type = kpi.match?(percent) ? "percentage" : (kpi.match?(numeric) ? "numeric" : "money")
    labels = overrides.fetch(kpi) { mis.empty? || mis.match?(not_in_mis) ? [] : split_labels.(mis) }
    labels.each do |l|
      next if all.key?(norm.(l))
      next warnings << "#{company} · #{kpi}: #{l.inspect} is not in the MIS — pending #{c.dig('pending_labels', 'q')}" if pending.include?(l)

      near = all.keys.select { |k| k.start_with?(norm.(l)[0, 10]) || (norm.(l).start_with?(k[0, 12].to_s) && k.size > 4) }.first(3)
      missing << "#{company} · #{kpi}: #{l.inspect} is not a row label in its MIS#{" (near: #{near.join(' | ')})" if near.any?}"
    end

    next if labels.empty? && skip_unlined # the client asked for no mapping until the MIS has the line

    if labels.size <= 1
      # One line (or none yet): the KPI reads its MIS label directly
      company_rows << { company:, reported: labels.first || kpi, standard: kpi, category:, data_type:, show: "Yes",
                        note: labels.empty? ? "no MIS line: #{mis}" : nil }
    else
      # Composite: components first (the compute formula names their standard names), then the parent
      parts = labels.map { [_1, plain.(_1)] }
      parts.each { |l, std| company_rows << { company:, reported: l, standard: std, category:, data_type:, show: "No", note: "component of #{kpi}" } }
      company_rows << { company:, reported: kpi, standard: kpi, category:, data_type:, show: "Yes", autofill: "compute",
                        formula: parts.map(&:last).join(" + "), note: "sum of #{parts.size} MIS lines" }
    end
  end

  # One mapping per MIS label: the label stays on one base row (a component if there is one, else the first), every
  # other KPI on that label becomes a compute copy of the base (e.g. Burn = Operating Cash Flow)
  base = company_rows.group_by { norm.(_1[:reported]) }.transform_values { |same| (same.find { _1[:note]&.start_with?("component") } || same.first)[:standard] }
  company_rows.map! do |m|
    b = base[norm.(m[:reported])]
    next m if m[:standard] == b || m[:autofill] == "compute"

    m.merge(reported: m[:standard], autofill: "compute", formula: b, note: "copy of #{b} (same MIS line)")
  end

  # Source Sheet: only where the label is in a workbook that will be loaded; by label first, then by category
  ss = c["source_sheet"] || {}
  company_rows.each do |m|
    next if m[:autofill] == "compute" || !loaded.key?(norm.(m[:reported]))

    sheet = ss.dig("by_label", m[:reported]) || ss.dig("by_category", m[:category])
    next unless sheet

    on = loaded[norm.(m[:reported])].map(&:first)
    unless on.include?(sheet)
      msg = "#{company} · #{m[:standard]}: source sheet #{sheet.inspect}, but #{m[:reported].inspect} is only on #{on.uniq.join(', ')}"
      pending.include?(m[:reported]) ? warnings << "#{msg} — pending #{c.dig('pending_labels', 'q')}, stays blank until answered" : missing << msg
    end
    m[:sheet] = sheet
  end
  rows.concat(company_rows)
end

warnings.each { warn "⚠ #{_1}" }
if missing.any?
  warn "✖ #{missing.size} KPI Info line(s) do not match the MIS — add each to the company's `overrides:` (with a client question) and rebuild:"
  missing.each { warn "    #{_1}" }
  exit 1
end

# ── Write the mapping upload and the workbook list ──────────────────────────────────────────────────────────────────
headers = ["Stakeholder", "Reported Kpi Name", "Standard Kpi Name", "Category", "Data Type", "Denomination", "Fx Conversion",
           "Parent Standard Kpi Name", "Position", "Show In Report", "Lower Threshold", "Upper Threshold", "Auto Fill", "Compute Formula",
           "Update Only", "Source Sheet"]
P.write_xlsx(File.join(out, "09_kpi_mappings.xlsx"), "Mappings", headers,
             rows.map { |m| [m[:company], m[:reported], m[:standard], m[:category], m[:data_type], "NA", "NA", nil, nil, m[:show], nil, nil,
                             m[:autofill] || "NA", m[:formula], "No", m[:sheet]] })
File.write(File.join(out, "kpi_workbooks.json"), JSON.pretty_generate(workbooks))
rows.group_by { _1[:company] }.each do |company, rs|
  puts "  #{company}: #{rs.size} mappings — #{rs.count { _1[:autofill] }} computed, #{rs.count { _1[:note]&.start_with?('component') }} components, " \
       "#{rs.count { _1[:sheet] }} with a source sheet, #{rs.count { _1[:note]&.start_with?('no MIS') }} with no MIS line yet"
end
workbooks.each { |w| puts "  workbook #{w[:name]} (#{w[:company]}, #{w[:period]} #{w[:as_of]})#{" — held: #{w[:hold]}" if w[:hold]}" }
