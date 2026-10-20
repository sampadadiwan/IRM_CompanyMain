# Builds the portfolio upload files from the client's portfolio company / investment / valuation sheets and the rules in
# mappings/portfolio.yml. Writes to <workspace>/out/portfolio/:
#   02_form_types/*.json (POST /form_types.json — typed custom fields, created BEFORE the imports; field names are
#   FormCustomField.to_name of the column header, so the importer keys values to them) · 06_portfolio_companies.xlsx
#   (Investor import, category Portfolio Company) · 07_portfolio_investments.xlsx · 08_valuations.xlsx · logos.json
# Every template column is written, dates as real Excel date cells.
#
# Refuses to build when <client>_client_questions.md is missing, a `q:` is not a question id in it, or the must-have gate
# blocks the portfolio step (M15). Stops when a source header named in the yml is not in the sheet, an investment names a
# company not in the company sheet, or a valuation names a company with no investments.
#
# Usage: ruby build_portfolio_uploads.rb [--workspace DIR]
require "fileutils"
require_relative "../api"
require_relative "../gate"
require_relative "common"

P = Onboarding::Portfolio
workspace = Onboarding::Api.workspace_from!(ARGV)
cfg = P.config(workspace)
out = P.out_dir(workspace)
FileUtils.mkdir_p(File.join(out, "02_form_types"))

# ── Gates: question ids, then the must-have answers (M15) ───────────────────────────────────────────────────────────
P.check_questions!(workspace, cfg)
Onboarding::Gate.check!(workspace, :portfolio)
puts "✔ must-have gate: portfolio may be built"

fund = cfg.fetch("fund")
blanks = Array(cfg.dig("blank_values", "value")).map { _1.to_s.downcase }
date = ->(v) { v.is_a?(Date) ? v : (v.to_s.strip.empty? ? nil : Date.parse(v.to_s)) }
num = ->(v) { v.is_a?(Numeric) ? v.to_f : (v.to_s.strip.empty? || blanks.include?(v.to_s.strip.downcase) ? nil : Float(v.to_s.delete(","))) }
# Text: whole numbers without ".0" (a Ref Id of 1 stays "1")
text = ->(v) { v.is_a?(Float) && v == v.floor ? v.to_i.to_s : v&.to_s }
emails = ->(v) { v.to_s.split(/[,;\s]+/).reject(&:empty?) }

# One cell from a rule: a header name, or { from:, type:, emails:, value: }
cell = lambda do |row, rule, where|
  rule = { "from" => rule } unless rule.is_a?(Hash)
  return rule["value"] if rule.key?("value")

  header = rule.fetch("from")
  abort "✖ #{where}: no column #{header.inspect} in the source (has: #{row.keys.compact.join(', ')})" unless row.key?(header)
  v = row[header]
  case rule["emails"]
  when "first" then return emails.(v).first
  when "all" then return emails.(v).join(", ")
  end
  case rule["type"]
  when "date", "DateField" then date.(v)
  when "number", "NumberField" then num.(v)
  else text.(v)
  end
end

# Builds one upload: template columns, then each extra (custom field) by its label
build = lambda do |section, rows, fixed = {}|
  sec = cfg.fetch(section)
  cols = sec.fetch("columns")
  extras = sec.fetch("extras", {})
  headers = fixed.keys + cols.keys + extras.keys
  data = rows.each_with_index.map do |r, i|
    fixed.values + cols.map { |h, rule| cell.(r, rule, "#{section} row #{i + 2} #{h}") } +
      extras.map { |label, rule| cell.(r, rule, "#{section} row #{i + 2} #{label}") }
  end
  [headers, data]
end

# Form type with typed custom fields for one model, named the way the importer keys them
form_type = lambda do |model, section|
  extras = cfg.dig(section, "extras") || {}
  return if extras.empty?

  fields = extras.each_with_index.map { |(label, rule), i| { name: P.to_name(label), label:, field_type: rule.fetch("type"), position: i + 1 } }
  File.write(File.join(out, "02_form_types", "#{P.to_name(model)}.json"), JSON.pretty_generate(form_type: { name: model, form_custom_fields_attributes: fields }))
end
form_type.("Investor", "companies")
form_type.("PortfolioInvestment", "investments")
form_type.("Valuation", "valuations")

# ── 06 Portfolio companies (Investor import) ────────────────────────────────────────────────────────────────────────
companies = P.table(workspace, cfg.dig("companies", "source"))
headers, rows = build.("companies", companies)
P.write_xlsx(File.join(out, "06_portfolio_companies.xlsx"), "Investors", headers, rows)
names = rows.map { _1[headers.index("Name")] }

# ── 07 Portfolio investments ────────────────────────────────────────────────────────────────────────────────────────
investments = P.table(workspace, cfg.dig("investments", "source"))
headers, rows = build.("investments", investments, { "Fund" => fund })
co_col, inst_col = headers.index("Portfolio Company Name"), headers.index("Instrument")
unknown = rows.map { _1[co_col] }.uniq - names
abort "✖ investments name companies not in the company sheet: #{unknown.join(', ')}" if unknown.any?
P.write_xlsx(File.join(out, "07_portfolio_investments.xlsx"), "Sheet1", headers, rows)
# Instruments held per company, in the order first bought
held = rows.group_by { _1[co_col] }.transform_values { |rs| rs.map { _1[inst_col] }.uniq }

# ── 08 Valuations (per_instrument_held: the per-share value applies to every instrument the fund holds) ─────────────
valuations = P.table(workspace, cfg.dig("valuations", "source"))
headers, rows = build.("valuations", valuations)
vco, vinst = headers.index("Portfolio Company"), headers.index("Instrument")
if cfg.dig("valuations", "per_instrument_held", "value")
  rows = rows.flat_map do |r|
    instruments = held.fetch(r[vco]) { abort "✖ valuation for #{r[vco]}, which has no investments" }
    instruments.map { |inst| r.dup.tap { _1[vinst] = inst } }
  end
end
P.write_xlsx(File.join(out, "08_valuations.xlsx"), "Sheet1", headers, rows)

# ── Logos: company → image file ─────────────────────────────────────────────────────────────────────────────────────
logos = (cfg.dig("companies", "logos", "files") || {}).to_h do |company, file|
  path = File.join(workspace, "source", file)
  abort "✖ logo for #{company}: no file #{path}" unless File.exist?(path)
  abort "✖ logo for #{company}: not a company in the company sheet" unless names.include?(company)
  [company, path]
end
File.write(File.join(out, "logos.json"), JSON.pretty_generate(logos))
puts "logos.json                          #{logos.size.to_s.rjust(4)} logos"
puts "→ #{out}"
