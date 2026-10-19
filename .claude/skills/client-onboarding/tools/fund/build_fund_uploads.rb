# Builds the CapHive fund upload files from out/folios.json (read_drawdowns.rb) and the rules in mappings/drawdowns.yml.
# No client logic lives here — every client choice is a yml rule. Writes to <workspace>/out/fund/:
#   01_fund.json (POST /funds.json) · 01b_unit_settings.xlsx · 02_form_types/*.json (POST /form_types.json, typed custom
#   fields, created BEFORE the imports) · 03_investors.xlsx · 04_commitments.xlsx · 05a_calls.xlsx · 05b_remittances.xlsx
#   · 05c_payments.xlsx · 06a_distributions.xlsx · 06b_dist_payments.xlsx · 07_account_entries.xlsx (TDS) · 07b_distribution_fees.json
#   ("Tax" fees) · 07c_expected_net.json (client net per payment, for checking) — when the yml has `distributions:`
# Every template column is written, dates as real Excel date cells.
#
# Refuses to build (SKILL.md hard rules 8–9) when:
#   - the must-have gate (gate.rb) blocks fund / commitments / drawdowns,
#   - <workspace>/<client>_client_questions.md is missing,
#   - an entry under `assumptions:` has no `q:`, or any `q:` in the yml is not a question id in that file.
# Stops when the money does not add up: a folio's payments ≠ its client "received" total, or called ≠ received + not received.
#
# Usage: ruby build_fund_uploads.rb [--workspace DIR]
require "yaml"
require "json"
require "date"
require "fileutils"
require "caxlsx"
require_relative "../api"
require_relative "../gate"

workspace = Onboarding::Api.workspace_from!(ARGV)
config = YAML.safe_load_file(File.join(workspace, "mappings", "drawdowns.yml"), permitted_classes: [Date])
client = config.fetch("client")
fund = config.fetch("fund")
settings = config.fetch("settings")
assume = config.fetch("assumptions", {})
TOL = 0.01

# ── Gate 1: every assumption is a question in <client>_client_questions.md ──────────────────────────────────────────
questions_path = File.join(workspace, "#{client}_client_questions.md")
abort "✖ #{File.basename(questions_path)} is missing — create it from client-questions-template.md before building (hard rule 8)" unless File.exist?(questions_path)
questions = File.read(questions_path)
# Fund-ops review (2026-10-19): never generate values the client did not give — references come from a client column only
abort "✖ assumptions.payment_reference is not allowed: payment references must come from the client (columns.payment_reference) or stay blank" if assume.key?("payment_reference")
unasked = assume.reject { |_, v| v.is_a?(Hash) && v["q"] }.keys
abort "✖ assumptions without a question id (q:): #{unasked.join(', ')}" if unasked.any?
q_ids = []
walk = ->(node) { node.is_a?(Hash) ? (q_ids << node["q"] if node["q"]; node.each_value { walk.(_1) }) : (node.is_a?(Array) && node.each { walk.(_1) }) }
walk.(config)
missing_q = q_ids.uniq.reject { |q| questions.match?(/\*\*#{Regexp.escape(q)}\./) }
abort "✖ question ids used in drawdowns.yml but not in #{File.basename(questions_path)}: #{missing_q.join(', ')}" if missing_q.any?
puts "✔ #{q_ids.uniq.size} question ids, all in #{File.basename(questions_path)}: #{q_ids.uniq.sort.join(' ')}"

# ── Gate 1b: the must-have answers this build depends on (questions file, section M) ─────────────────────────────────
steps = %i[fund commitments drawdowns] + (config["distributions"] ? %i[distributions] : [])
steps.each { Onboarding::Gate.check!(workspace, _1) }
puts "✔ must-have gate: #{steps.join(', ')} may be built"

# ── Load the canonical folios (dates back to Date) and apply the drawdown rules ─────────────────────────────────────
to_date = ->(v) { v.is_a?(String) && v.match?(/\A\d{4}-\d{2}-\d{2}\z/) ? Date.parse(v) : v }
folios = JSON.parse(File.read(File.join(workspace, "out", "folios.json")))
folios.each do |f|
  f["drawdowns"].each do |d|
    d["notice_date"] = to_date.(d["notice_date"])
    d["due_date"] = to_date.(d["due_date"])
    d["payments"].each { _1["date"] = to_date.(_1["date"]) }
  end
  (f["distributions"] ||= []).each { _1["date"] = to_date.(_1["date"]) }
  # Undated drawdowns ("Various"): one drawdown of the full commitment on a fixed date (rule undated_drawdown)
  if f["undated"] && f["drawdowns"].empty? && (u = assume["undated_drawdown"])
    date = Date.parse(u.fetch("date").to_s)
    f["drawdowns"] << { "seq" => 1, "called" => f["committed"], "notice_date" => date, "due_date" => nil,
                        "payments" => [{ "date" => date, "amount" => f["committed"] }] }
  end
end

# Due date rule: blank or before the notice → notice + N days
fallback = assume["due_date_fallback"]
due_for = lambda do |d|
  due, notice = d["due_date"], d["notice_date"]
  return due unless fallback && notice.is_a?(Date)

  when_ = Array(fallback["when"])
  bad = (when_.include?("blank") && !due.is_a?(Date)) || (when_.include?("before_notice") && due.is_a?(Date) && due < notice)
  bad ? notice + fallback.fetch("days") : due
end

# ── Gate 2: the money adds up against the client's own totals ───────────────────────────────────────────────────────
money_issues = folios.flat_map do |f|
  paid = f["drawdowns"].sum { |d| d["payments"].sum { _1["amount"].to_f } }
  called = f["drawdowns"].sum { _1["called"].to_f }
  t = f["client_totals"] || {}
  [("#{f['folio']}: payments #{paid} ≠ client received #{t['received']}" if t["received"] && (paid - t["received"]).abs > TOL),
   ("#{f['folio']}: called #{called} ≠ received + not received #{t['received'].to_f + t['not_received'].to_f}" if t["received"] && t["not_received"] && (called - t["received"] - t["not_received"]).abs > TOL)].compact
end
abort "✖ money does not add up:\n  #{money_issues.first(10).join("\n  ")}" if money_issues.any?
puts "✔ money checks: payments = client received and called = received + not received on every folio that carries them"

# ── Helpers ─────────────────────────────────────────────────────────────────────────────────────────────────────────
OUT = File.join(workspace, "out", "fund")
FileUtils.mkdir_p(File.join(OUT, "02_form_types"))
fund_name = fund.fetch("name")
currency = fund.fetch("currency")
value_of = ->(node) { node.is_a?(Hash) ? node["value"] : node }
fill = lambda do |pattern, f, extra = {}|
  pattern.to_s.gsub("{folio}", f["folio"]).gsub("{folio_lower}", f["folio"].downcase)
         .then { |s| extra.reduce(s) { |acc, (k, v)| acc.gsub("{#{k}}", v.to_s) } }
end
# 1 → "1st", 2 → "2nd", 11 → "11th" (for call names like "Drawdown {ordinal}")
ordinal = lambda do |n|
  suffix = (11..13).cover?(n % 100) ? "th" : { 1 => "st", 2 => "nd", 3 => "rd" }.fetch(n % 10, "th")
  "#{n}#{suffix}"
end
call_name = ->(seq) { settings.fetch("call_name").gsub("{seq}", seq.to_s).gsub("{ordinal}", ordinal.(seq)) }
yes_no = ->(b) { b ? "Yes" : "No" }

# Writes one sheet; Date → date cell, Numeric → number, everything else (nil included) as text
def write_xlsx(path, sheet, headers, rows, extra_sheets: {})
  Axlsx::Package.new do |p|
    ds = p.workbook.styles.add_style(format_code: "dd-mmm-yyyy")
    p.workbook.add_worksheet(name: sheet) do |s|
      s.add_row headers
      rows.each do |row|
        s.add_row row, types: row.map { |v| v.is_a?(Date) ? :date : (v.is_a?(Numeric) ? :float : :string) },
                       style: row.map { |v| v.is_a?(Date) ? ds : nil }
      end
    end
    extra_sheets.each { |name, hs| p.workbook.add_worksheet(name:) { |s| s.add_row hs } }
    p.serialize(path)
  end
  puts format("  %-26s %4d rows", File.basename(path), rows.size)
end

def form_type(dir, file, name, fields, tag: nil)
  payload = { form_type: { name:, tag:, form_custom_fields_attributes: fields.each_with_index.map { |(n, label, type), i|
    { name: n, label:, field_type: type, position: i + 1 }
  } }.compact }
  File.write(File.join(dir, "02_form_types", file), JSON.pretty_generate(payload))
end

extras = config.fetch("extras", {})
# "target:" not "on:" — YAML reads a bare `on` key as the boolean true
extras_on = ->(target) { extras.select { |_, e| e["target"] == target } }
investor_name = ->(f) { (p = value_of.(assume["investor_name"])) ? fill.(p, f) : f["investor"] }
classes = folios.map { _1["unit_class"] }.uniq.sort
all_draws = folios.flat_map { |f| f["drawdowns"].map { |d| [f, d] } }
total_committed = folios.sum { _1["committed"].to_f }

# ── Calls come from the client (fund-ops review, 2026-10-19): a call is ONE fund drawdown event. Never group each
#    investor's n-th drawdown into "Drawdown n". Modes (calls: in the yml, each with a q:):
#      id_column    the client's call id on each drawdown row (columns.call_id)
#      schedule     the client's call list [{name, notice_date, due_date}]; a drawdown belongs to the latest call whose
#                   notice date is on or before its own date
#      single_call  one call — only if every drawdown's notice date is within call_window_days
calls_cfg = config["calls"]
window = settings.fetch("call_window_days", 31)
propose = lambda do |why|
  dates = all_draws.map { _2["notice_date"] }.grep(Date).sort
  clusters = []
  dates.uniq.each { |x| clusters.empty? || x - clusters.last.last > window ? clusters << [x] : clusters.last << x }
  rows = clusters.each_with_index.map do |c, i|
    members = all_draws.select { |_, d| c.include?(d["notice_date"]) }
    format("| %d | %s | %s | %d | %.2f |", i + 1, c.first, c.last, members.size, members.sum { _2["called"].to_f })
  end
  warn "✖ calls: #{why}"
  warn "  The source does not say which drawdowns form one capital call. Ask the client (add to the questions file):"
  warn "  **C<n>. Capital calls.** Please send your call schedule: for each call, its name, notice date and due date (or the"
  warn "  call each payment belongs to). Your drawdown dates group into these periods (a new period after a #{window}-day gap):"
  warn "  | # | First date | Last date | Drawdowns | Amount |", "  |---|---|---|---|---|", *rows.map { "  #{_1}" }
  warn "  Once answered, add to mappings/drawdowns.yml:  calls: { schedule: [ { name: …, notice_date: …, due_date: … }, … ], q: C<n> }"
  abort
end
propose.("no `calls:` section in mappings/drawdowns.yml") unless calls_cfg
abort "✖ calls: needs a q: (the client question it answers)" unless calls_cfg["q"]
schedule = Array(calls_cfg["schedule"]).map { |c| c.merge("notice_date" => Date.parse(c.fetch("notice_date").to_s), "due_date" => c["due_date"] && Date.parse(c["due_date"].to_s)) }
                                         .sort_by { _1["notice_date"] }
call_of = lambda do |d|
  if calls_cfg["id_column"] then d["call_id"].to_s.empty? ? abort("✖ calls: a drawdown has no call id (columns.call_id)") : d["call_id"]
  elsif schedule.any? then (schedule.reverse.find { _1["notice_date"] <= d["notice_date"] } || abort("✖ calls: a drawdown on #{d['notice_date']} is before the first scheduled call"))["name"]
  elsif calls_cfg["single_call"] then calls_cfg["single_call"]
  else abort "✖ calls: one of id_column, schedule or single_call is needed"
  end
end
# One remittance per folio per call (CapHive: "Folio has already been taken"): a folio's drawdowns that fall in the same
# call merge into ONE remittance — called = their sum, every payment kept, earliest notice and due date
raw_lines = all_draws.map { |f, d| { f:, d:, call: call_of.(d), due: due_for.(d) } }
lines = raw_lines.group_by { [_1[:f]["folio"], _1[:call]] }.map do |(_, _), ls|
  next ls.first if ls.size == 1

  d = { "called" => ls.sum { _1[:d]["called"].to_f }, "notice_date" => ls.map { _1[:d]["notice_date"] }.grep(Date).min,
        "due_date" => ls.map { _1[:d]["due_date"] }.grep(Date).min, "payments" => ls.flat_map { _1[:d]["payments"] }, "merged" => ls.size }
  { f: ls.first[:f], d:, call: ls.first[:call], due: ls.map { _1[:due] }.grep(Date).min }
end
merged = lines.count { _1[:d]["merged"] }
puts "✔ one remittance per folio per call (#{merged} folios had several drawdowns in one call → merged, payments kept)" if merged.positive?
calls = lines.group_by { _1[:call] }
# Scheduled calls carry the client's own dates; the remittance is dated with its call's notice date
sched_by_name = schedule.to_h { [_1["name"], _1] }
lines.each { |l| l[:remit_date] = sched_by_name[l[:call]] ? sched_by_name[l[:call]]["notice_date"] : l[:d]["notice_date"] }
# Business-logic checks before any upload: one event per call, calls in date order, due on or after the call date
call_date = ->(name, ls) { sched_by_name[name] ? sched_by_name[name]["notice_date"] : ls.map { _1[:d]["notice_date"] }.grep(Date).min }
calls.each do |name, ls|
  next if sched_by_name[name]

  span = (ls.map { _1[:d]["notice_date"] }.grep(Date).max - ls.map { _1[:d]["notice_date"] }.grep(Date).min).to_i
  propose.("#{name} spans #{span} days of notice dates — not one fund event") if span > window
end
puts "✔ calls: #{calls.size} from #{calls_cfg['id_column'] ? 'the client call ids' : (schedule.any? ? 'the client schedule' : 'a single call')}, each one event"

# ── 01 Fund + unit settings ─────────────────────────────────────────────────────────────────────────────────────────
first_close = case value_of.(fund["first_close_date"])
              when "earliest_notice_date" then all_draws.map { _2["notice_date"] }.grep(Date).min
              else Date.parse(value_of.(fund["first_close_date"]).to_s)
              end
File.write(File.join(OUT, "01_fund.json"), JSON.pretty_generate(fund: {
  name: fund_name, currency:, category: value_of.(fund["category"]), unit_types: classes.join(","),
  first_close_date: first_close.iso8601, details: fund["details"]
}.compact))
puts "  01_fund.json               #{fund_name}, classes #{classes.join(', ')}, first close #{first_close}"
fees = fund.fetch("fees", {})
gp = Array(value_of.(fund["gp_unit_classes"]))
write_xlsx(File.join(OUT, "01b_unit_settings.xlsx"), "Unit Settings",
           ["Fund", "Class/Series", "Management Fee %", "Setup Fee %", "Carry %", "Gp Units", "Update Only", "Isin"],
           classes.map { |c| [fund_name, c, fees.fetch("management", 0), fees.fetch("setup", 0), fees.fetch("carry", 0), yes_no.(gp.include?(c)), "No", nil] })

# ── 02 Form types: typed custom fields before the imports ───────────────────────────────────────────────────────────
form_type(OUT, "capital_commitment.json", "CapitalCommitment",
          extras_on.("commitment").map { |n, e| [n, e["label"], e["type"]] }, tag: settings.fetch("form_tag"))
remittance_fields = (settings["remittance_dates_as_fields"] ? [["notice_date", "Notice Date", "DateField"], ["due_date", "Due Date", "DateField"]] : []) +
                    extras_on.("remittance").map { |n, e| [n, e["label"], e["type"]] }
form_type(OUT, "capital_remittance.json", "CapitalRemittance", remittance_fields) if remittance_fields.any?
form_type(OUT, "investor.json", "Investor", extras_on.("investor").map { |n, e| [n, e["label"], e["type"]] }) if extras_on.("investor").any?

# ── 03 Investors ────────────────────────────────────────────────────────────────────────────────────────────────────
write_xlsx(File.join(OUT, "03_investors.xlsx"), "Investors",
           ["Name", "Primary Email", "Category", "Tags", "City", "Sector"] + extras_on.("investor").map { _2["label"] },
           folios.map { |f| [investor_name.(f), fill.(value_of.(assume.fetch("investor_email")), f), settings.fetch("investor_category"), nil, nil, nil] +
                            extras_on.("investor").keys.map { f["extras"][_1] } })

# ── 04 Commitments ──────────────────────────────────────────────────────────────────────────────────────────────────
commitment_date = lambda do |f|
  rule = value_of.(assume.fetch("commitment_date"))
  first = f["drawdowns"].map { _1["notice_date"] }.grep(Date).min
  case rule
  when "first_notice_date" then first || (d = assume.dig("commitment_date", "fallback")) && Date.parse(d.to_s)
  else Date.parse(rule.to_s)
  end
end
write_xlsx(File.join(OUT, "04_commitments.xlsx"), "Commitments",
           ["Fund", "Stakeholder", "Kyc Investing Entity", "Folio No", "Committed Amount (Folio Currency)", "Committed Amount (Fund Currency)",
            "Folio Currency", "Unit Type", "Fund Close", "Onboarding Completed", "Notes", "Commitment Date", "Investor Signatory Emails",
            "From Currency", "To Currency", "Exchange Rate", "As Of", "Update Only", "Form Tag"] + extras_on.("commitment").map { _2["label"] },
           folios.map do |f|
             [fund_name, investor_name.(f), nil, f["folio"], f["committed"], nil, currency, f["unit_class"], settings.fetch("fund_close"), "Yes",
              value_of.(assume["commitment_notes"]), commitment_date.(f), nil, nil, nil, nil, nil, "No", settings.fetch("form_tag")] +
               extras_on.("commitment").keys.map { f["extras"][_1] }
           end)

# ── 05 Calls (one per drawdown sequence), remittances (one per folio per call), payments ────────────────────────────
call_due = lambda do |ls|
  name = ls.first[:call]
  next sched_by_name[name]["due_date"] if sched_by_name[name]&.dig("due_date")

  case settings.fetch("call_due_date")
  when "earliest_due_date" then ls.map { _1[:due] }.grep(Date).min
  when "latest_notice_date" then ls.map { _1[:d]["notice_date"] }.grep(Date).max
  else raise "unknown call_due_date #{settings['call_due_date']}"
  end
end
# Unit price per class on every call ("A:100:0,B:100:0,…" = class:price:premium), from units.price_per_class
prices = value_of.(config.dig("units", "price_per_class"))
unit_price = prices ? classes.map { |k| "#{k}:#{prices.fetch(k) { abort "✖ units.price_per_class has no price for class #{k}" }}:0" }.join(",") : settings["unit_price"]
write_xlsx(File.join(OUT, "05a_calls.xlsx"), "Calls",
           ["Fund", "Name", "Percentage Called", "Call Date", "Due Date", "Generate Remittances", "Remittances Verified", "Fund Closes",
            "Call Basis", "Unit Price/Premium", "Send Call Notice", "Send Payment Notification"],
           calls.map do |name, ls|
             [fund_name, name, (ls.sum { _1[:d]["called"].to_f } * 100 / total_committed).round(4).to_s,
              call_date.(name, ls), call_due.(ls), "No", "No", "All", settings.fetch("call_basis"),
              unit_price, "No", "No"]
           end,
           extra_sheets: { "Exchange Rates" => ["From Currency", "To Currency", "Exchange Rate", "As Of"] })

order = calls.map { |name, ls| [name, call_date.(name, ls), call_due.(ls)] }.sort_by { _2 }
order.each_cons(2) do |(a, ad, au), (b, bd, bu)|
  abort "✖ calls out of order: #{a} (due #{au}) is due after #{b} (call #{bd}, due #{bu})" if au && bu && au > bu
end
order.each { |n, d, u| abort "✖ call #{n}: due #{u} is before its call date #{d}" if u && d && u < d }
verified = yes_no.(settings.fetch("verified_on_import"))
date_fields = settings["remittance_dates_as_fields"]
write_xlsx(File.join(OUT, "05b_remittances.xlsx"), "Remittances",
           ["Fund", "Capital Call", "Folio No", "Call Amount (Inclusive Of Capital Fees, Folio Currency)", "Capital Fees (Folio Currency)",
            "Other Fees (Folio Currency)", "Call Amount (Inclusive Of Capital Fees, Fund Currency)", "Capital Fees (Fund Currency)",
            "Other Fees (Fund Currency)", "Investment Amount (Fund Currency)", "Remittance Date", "Verified"] +
             (date_fields ? ["Notice Date", "Due Date"] : []) + extras_on.("remittance").map { _2["label"] },
           lines.map do |l|
             called = l[:d]["called"]
             [fund_name, l[:call], l[:f]["folio"], called, 0, 0, called, 0, 0, nil, l[:remit_date], verified] +
               (date_fields ? [l[:d]["notice_date"], l[:due]] : []) + extras_on.("remittance").keys.map { l[:f]["extras"][_1] }
           end)

payment_rows = lines.flat_map do |l|
  l[:d]["payments"].each_with_index.map do |p, i|
    ref = p["reference"] # only what the client gave (columns.payment_reference); otherwise blank
    [fund_name, l[:call], l[:f]["folio"], p["amount"], currency, p["amount"], verified, nil, ref, p["date"], nil, "No"]
  end
end
write_xlsx(File.join(OUT, "05c_payments.xlsx"), "Payments",
           ["Fund", "Capital Call", "Folio No", "Amount (Folio Currency)", "Currency", "Amount (Fund Currency)", "Verified",
            "Virtual Bank Account", "Reference No", "Payment Date", "Notes", "Update Only"], payment_rows)

# ── 06 Distributions: one per title, one payment per folio per title ─────────────────────────────────────────────────
dist_rows = []
if config["distributions"]
  suffix = value_of.(config.dig("distributions", "repeat_title_suffix"))
  folios.each do |f|
    seen = Hash.new(0)
    f["distributions"].each do |e|
      # A folio's 2nd entry under the same title becomes its own distribution (one payment per folio per distribution)
      title = (seen[e["title"]] += 1) > 1 && suffix ? "#{e['title']}#{suffix}" : e["title"]
      dist_rows << e.merge("title" => title, "folio" => f["folio"])
    end
  end
  # Payment Type is the client's own label → a custom field. TDS and net are NOT custom fields: TDS goes in as account
  # entries + a "Tax" distribution fee, and the platform computes net payable (fund-ops review, 2026-10-19)
  form_type(OUT, "capital_distribution_payment.json", "CapitalDistributionPayment", [["payment_type", "Payment Type", "TextField"]])
  amount_of = ->(e, as) { e["as"] == as ? e["amount"] : 0 }
  by_title = dist_rows.group_by { _1["title"] }
  write_xlsx(File.join(OUT, "06a_distributions.xlsx"), "Distributions",
             ["Fund", "Title", "Income", "Face Value For Redemption", "Reinvestment", "Date", "Generate Payments", "Send Notification",
              "Payments Paid", "Folio No", "Distribution Basis"],
             by_title.map do |title, es|
               [fund_name, title, es.sum { amount_of.(_1, "income") }, es.sum { amount_of.(_1, "face_value") }, 0,
                es.map { _1["date"] }.grep(Date).min, "No", "No", "No", nil, nil]
             end)
  write_xlsx(File.join(OUT, "06b_dist_payments.xlsx"), "Payments",
             ["Fund", "Capital Distribution", "Folio No", "Income", "Face Value For Redemption", "Reinvestment", "Payment Date",
              "Completed", "Payment Type"],
             dist_rows.map do |e|
               [fund_name, e["title"], e["folio"], amount_of.(e, "income"), amount_of.(e, "face_value"), 0, e["date"], "Yes", e["payment_type"]]
             end)

  # ── 07 TDS the platform's way: an account entry per payment with TDS, a "Tax" fee per distribution, then recompute ──
  # A fee is a filter: it sums the folio's account entries whose name matches and whose reporting date is in its range.
  # The name carries the distribution title so one distribution's fee never picks up another's entries.
  taxed = dist_rows.select { _1["tds"].to_f.positive? }
  write_xlsx(File.join(OUT, "07_account_entries.xlsx"), "AccountEntries",
             ["Fund", "Folio No", "Reporting Date", "Entry Type", "Name", "Amount (Folio Currency)", "Amount (Fund Currency)", "Notes",
              "Rule For", "Parent Type", "Parent Id"],
             taxed.map { |e| [fund_name, e["folio"], e["date"], "TDS", "TDS - #{e['title']}", e["tds"], e["tds"], "TDS on #{e['title']} (client data)", nil, nil, nil] })
  fees = taxed.group_by { _1["title"] }.map do |title, es|
    { title:, fee: { name: "TDS - #{title}", fee_type: "Tax", entry_type: "TDS",
                     start_date: es.map { _1["date"] }.grep(Date).min.iso8601, end_date: es.map { _1["date"] }.grep(Date).max.iso8601 } }
  end
  File.write(File.join(OUT, "07b_distribution_fees.json"), JSON.pretty_generate(fees))
  # What the platform must show after the recompute — onboard.rb waits for it; never imported
  File.write(File.join(OUT, "07c_expected_net.json"),
             JSON.pretty_generate(dist_rows.to_h { ["#{_1['folio']}|#{_1['title']}", { net: _1["net"], tds: _1["tds"].to_f }] }))
  puts format("  07b_distribution_fees.json %4d Tax fees · 07c_expected_net.json %d payments", fees.size, dist_rows.size)
end

# ── Totals to tick against the client's own figures ─────────────────────────────────────────────────────────────────
puts format("✔ %d folios · committed %.2f · %d calls · %d remittances called %.2f · %d payments %.2f → %s",
            folios.size, total_committed, calls.size, lines.size, lines.sum { _1[:d]["called"].to_f },
            payment_rows.size, payment_rows.sum { _1[3].to_f }, OUT)
puts format("✔ %d distributions · %d payments · income %.2f · face value %.2f · TDS %.2f · net %.2f", dist_rows.map { _1["title"] }.uniq.size,
            dist_rows.size, dist_rows.select { _1["as"] == "income" }.sum { _1["amount"] }, dist_rows.select { _1["as"] == "face_value" }.sum { _1["amount"] },
            dist_rows.sum { _1["tds"].to_f }, dist_rows.sum { _1["net"].to_f }) if dist_rows.any?
