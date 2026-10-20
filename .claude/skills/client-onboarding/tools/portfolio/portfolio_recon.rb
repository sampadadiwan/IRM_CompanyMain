# Portfolio reconciliation: the client's portfolio company / investment / valuation sheets vs what CapHive holds, read through
# the JSON API only. Independent of the builder: it opens the raw sheets with its own reader and shares only the yml's
# column map; each source entry is taken out of a pool of app records, so nothing counts twice and leftovers are visible.
#   ① companies: each exists as a Portfolio Company, every mapped field (custom fields included) equals the source, logo present
#   ② investments: each source row ↔ one app investment (company, date, instrument, quantity, amount), custom fields equal
#   ③ valuations: each source valuation ↔ one app valuation per instrument (or per instrument held), per-share value and
#      company valuation equal, custom fields equal
#   ④ the client's own per-company figures (valuations.client_totals): shares = Σ net quantity, stake value = Σ FMV
#   ⑤ nothing left over: no app company or investment without a source row
# Writes out/portfolio_recon.md and out/portfolio_recon.json (passed, checks, ok, generated_at) — gate.rb's go-live reads it.
#
# Usage: ruby portfolio_recon.rb [--workspace DIR]
require "time"
require_relative "../api"
require_relative "common"

P = Onboarding::Portfolio
api = Onboarding::Api.new(Onboarding::Api.workspace_from!(ARGV))
WS = api.workspace
cfg = P.config(WS)
TOL = 0.01

# ── Own reader: the raw sheet as {header => value}, headers without "*" and blanks ──────────────────────────────────
clean = ->(v) { v.is_a?(String) ? v.delete("﻿").gsub(/[[:space:]]+/, " ").strip : v }
read = lambda do |src|
  sh = Roo::Spreadsheet.open(File.join(WS, "source", src.fetch("file"))).sheet(src.fetch("sheet", 0))
  heads = sh.row(sh.first_row).map { clean.(_1.to_s.delete("*")) }
  ((sh.first_row + 1)..sh.last_row).map { |r| [r, heads.zip(sh.row(r).map { clean.(_1) }).to_h] }.reject { |_, h| h.values.all? { _1.to_s.empty? } }
end
blanks = Array(cfg.dig("blank_values", "value")).map { _1.to_s.downcase }
num = ->(v) { v.is_a?(Numeric) ? v.to_f : (v.to_s.strip.empty? || blanks.include?(v.to_s.strip.downcase) ? nil : v.to_s.delete(",").to_f) }
eq = ->(a, b) { (a.nil? && b.nil?) || (!a.nil? && !b.nil? && (a.to_f - b.to_f).abs < TOL) }
text_eq = ->(a, b) { clean.(a.is_a?(Float) && a == a.floor ? a.to_i.to_s : a.to_s) == clean.(b.to_s) }
iso = ->(v) { v.is_a?(Date) ? v.iso8601 : (v.to_s.empty? ? nil : Date.parse(v.to_s).iso8601) }
src_of = ->(rule) { rule.is_a?(Hash) ? rule["from"] : rule }
# Expected value of a rule (emails first/all, typed) — the same meaning the yml gives it, worked out independently
expect = lambda do |row, rule|
  rule = { "from" => rule } unless rule.is_a?(Hash)
  return rule["value"] if rule.key?("value")

  v = row[rule["from"]]
  mails = v.to_s.split(/[,;\s]+/).reject(&:empty?)
  return mails.first if rule["emails"] == "first"
  return mails.join(", ") if rule["emails"] == "all"

  case rule["type"]
  when "date", "DateField" then iso.(v)
  when "number", "NumberField" then num.(v)
  else v
  end
end
same = ->(rule, want, got) { %w[number NumberField].include?(rule.is_a?(Hash) && rule["type"]) ? eq.(want, num.(got)) : (want.nil? && got.to_s.empty?) || text_eq.(want, got) }

results = Hash.new { |h, k| h[k] = { checked: 0, ok: 0 } }
issues = []
check = lambda do |test, area, ok, where, msg|
  results[[test, area]][:checked] += 1
  ok ? results[[test, area]][:ok] += 1 : issues << "| #{test} | #{area} | #{where} | #{msg} |"
end
take = ->(pool, key, &pred) { (i = (pool[key] || []).index(&pred)) && pool[key].delete_at(i) }

# ── Read the app (API only; every row's fund re-checked) ────────────────────────────────────────────────────────────
fund = api.list("/funds.json").find { _1["name"] == cfg.fetch("fund") } or abort "✖ no fund named #{cfg['fund'].inspect}"
investors = api.list("/investors.json?all=true")
pis = api.list("/portfolio_investments.json?fund_id=#{fund['id']}&all=true").select { _1["fund_id"] == fund["id"] }
valuations = api.list("/valuations.json?all=true")
co_name = ->(p) { clean.(p["portfolio_company_name"].to_s.gsub(/<[^>]+>/, "")) }

# ── ① Companies ─────────────────────────────────────────────────────────────────────────────────────────────────────
ccfg = cfg.fetch("companies")
companies = investors.select { _1["category"] == "Portfolio Company" }.to_h { [clean.(_1["investor_name"]), _1] }
by_name = companies.dup
logos = ccfg.dig("logos", "files") || {}
read.(ccfg.fetch("source")).each do |n, r|
  name = expect.(r, ccfg.dig("columns", "Name"))
  inv = companies.delete(name)
  check.("①", "Company exists (Portfolio Company)", !inv.nil?, "companies r#{n}", "#{name} missing")
  next unless inv

  ccfg.fetch("extras", {}).each do |label, rule|
    got = (inv["custom_fields"] || {})[P.to_name(label)]
    want = expect.(r, rule)
    check.("①", "Company field: #{label}", same.(rule, want, got), "companies r#{n}", "#{name}: #{want.inspect} vs #{got.inspect}")
  end
  next unless logos.key?(name)

  docs = api.list("/documents.json?owner_type=Investor&owner_id=#{inv['id']}")
  check.("①", "Logo attached", docs.any? { _1["name"] == "Logo" }, "logos", "#{name}: no \"Logo\" document")
end
check.("⑤", "Companies with no source row", companies.empty?, "—", companies.keys.inspect)

# ── ② Investments ───────────────────────────────────────────────────────────────────────────────────────────────────
icfg = cfg.fetch("investments")
icol = icfg.fetch("columns")
pool = pis.group_by { co_name.(_1) }
src_by_co = Hash.new { |h, k| h[k] = { qty: 0.0, cost: 0.0, instruments: [] } }
read.(icfg.fetch("source")).each do |n, r|
  co = expect.(r, icol["Portfolio Company Name"])
  date, inst = expect.(r, icol["Investment Date"]), expect.(r, icol["Instrument"])
  qty, amt = expect.(r, icol["Quantity"]), expect.(r, icol["Amount (Excluding Expenses)"])
  src_by_co[co][:qty] += qty.to_f
  src_by_co[co][:cost] += amt.to_f
  src_by_co[co][:instruments] |= [inst]
  x = take.(pool, co) { |p| p["investment_date"] == date && p["investment_instrument_name"] == inst && eq.(p["quantity"], qty) && eq.(p["amount"], amt) }
  check.("②", "Investment (company, date, instrument, qty, amount)", !x.nil?, "investments r#{n}", "#{co} #{date} #{inst} #{qty} #{amt} not found")
  next unless x

  icfg.fetch("extras", {}).each do |label, rule|
    got = (x["custom_fields"] || {})[P.to_name(label)]
    want = expect.(r, rule)
    check.("②", "Investment field: #{label}", same.(rule, want, got), "investments r#{n}", "#{co} #{date}: #{want.inspect} vs #{got.inspect}")
  end
end
check.("⑤", "Investments with no source row", pool.values.flatten.empty?, "—", pool.values.flatten.map { _1["id"] }.inspect)

# ── ③ Valuations, ④ client per-company figures ──────────────────────────────────────────────────────────────────────
vcfg = cfg.fetch("valuations")
vcol = vcfg.fetch("columns")
totals = vcfg.fetch("client_totals", {})
per_company = []
read.(vcfg.fetch("source")).each do |n, r|
  co, date = expect.(r, vcol["Portfolio Company"]), expect.(r, vcol["Valuation Date"])
  instruments = vcfg.dig("per_instrument_held", "value") ? src_by_co[co][:instruments] : [expect.(r, vcol["Instrument"])]
  instruments.each do |inst|
    v = valuations.find { clean.(_1["portfolio_company_name"]) == co && _1["valuation_date"] == date && _1["investment_instrument_name"] == inst }
    check.("③", "Valuation per instrument (date)", !v.nil?, "valuations r#{n}", "#{co} #{date} #{inst} missing")
    next unless v

    check.("③", "Per-share value", eq.(v["per_share_value"], expect.(r, vcol["Per Share Value"])), "valuations r#{n}", "#{co} #{inst}: #{r[src_of.(vcol['Per Share Value'])]} vs #{v['per_share_value']}")
    check.("③", "Company valuation", eq.(v["valuation"], expect.(r, vcol["Valuation"])), "valuations r#{n}", "#{co} #{inst}: #{r[src_of.(vcol['Valuation'])]} vs #{v['valuation']}")
    vcfg.fetch("extras", {}).each do |label, rule|
      got = (v["custom_fields"] || {})[P.to_name(label)]
      want = expect.(r, rule)
      check.("③", "Valuation field: #{label}", same.(rule, want, got), "valuations r#{n}", "#{co} #{inst}: #{want.inspect} vs #{got.inspect}")
    end
  end
  mine = pis.select { co_name.(_1) == co }
  qty, fmv, cost = mine.sum { _1["net_quantity"].to_f }, mine.sum { _1["fmv"].to_f }, mine.sum { _1["cost_of_remaining"].to_f }
  check.("④", "Client shares = Σ net quantity", eq.(qty, num.(r[totals["shares"]])), "valuations r#{n}", "#{co}: #{r[totals['shares']]} vs #{qty}") if totals["shares"]
  check.("④", "Client stake value = Σ FMV", eq.(fmv, num.(r[totals["stake_value"]])), "valuations r#{n}", "#{co}: #{r[totals['stake_value']]} vs #{fmv}") if totals["stake_value"]
  per_company << [co, num.(r[totals["shares"]]), qty, src_by_co[co][:cost], cost, num.(r[totals["stake_value"]]), fmv]
end

# ── Report ──────────────────────────────────────────────────────────────────────────────────────────────────────────
total = results.values.sum { _1[:checked] }
ok = results.values.sum { _1[:ok] }
inr = lambda do |x|
  return "—" if x.nil?

  whole, paise = format("%.2f", x.to_f.abs).split(".")
  head, tail = whole[0...-3], whole[-3..] || whole
  grouped = head.empty? ? tail : "#{head.reverse.scan(/\d{1,2}/).join(',').reverse},#{tail}"
  "#{'-' if x.to_f.negative?}#{grouped}#{".#{paise}" unless paise == '00'}"
end
md = ["# Portfolio reconciliation — #{cfg['client']} (fund #{fund['id']}) vs source sheets", "",
      "Generated #{Time.now.strftime('%Y-%m-%d %H:%M')} by `tools/portfolio/portfolio_recon.rb`, app read through the JSON API only.", "",
      "**Result: #{ok == total ? '✅' : '❌'} #{ok} / #{total} checks pass.**", "", "| Test | Check | Checked | Pass |", "|---|---|---:|---:|"]
results.each { |(t, a), v| md << "| #{t} | #{a} | #{v[:checked]} | #{v[:ok] == v[:checked] ? "✅ #{v[:ok]}" : "❌ #{v[:ok]}"} |" }
md += ["", "## Failures", "", issues.empty? ? "None." : ["| Test | Check | Where | Detail |", "|---|---|---|---|", *issues.first(50)].join("\n")]
md += ["", "## Per company", "", "| Company | Shares (client) | Shares (app) | Cost (source) | Cost (app) | Stake value (client) | FMV (app) |", "|---|---:|---:|---:|---:|---:|---:|"]
per_company.each { |co, q1, q2, c1, c2, v1, v2| md << "| #{co} | #{q1&.to_i} | #{q2.to_i} | #{inr.(c1)} | #{inr.(c2)} | #{inr.(v1)} | #{inr.(v2)} |" }
File.write(File.join(WS, "out", "portfolio_recon.md"), md.join("\n") + "\n")
File.write(File.join(WS, "out", "portfolio_recon.json"), JSON.pretty_generate(passed: ok == total && total.positive?, checks: total, ok:, generated_at: Time.now.iso8601))
puts md.first(6 + results.size + 2)
issues.first(10).each { puts "  #{_1}" }
puts "→ out/portfolio_recon.md, out/portfolio_recon.json"
exit(ok == total ? 0 : 1)
