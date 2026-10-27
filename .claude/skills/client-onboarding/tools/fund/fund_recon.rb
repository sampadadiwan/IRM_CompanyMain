# Fund reconciliation: the client's drawdown sheet vs what CapHive holds, read through the JSON API only.
# INDEPENDENT of the transform: it reads the raw rows itself (its own small reader below), sharing only the column map
# and folio-id rule of mappings/drawdowns.yml — never read_drawdowns.rb or folios.json — so a reader bug cannot pass
# both the upload and the check. The yml assumptions (commitment date, due-date fix, undated drawdowns …) are applied to
# work out what the app SHOULD hold.
#   ① source → app   every folio, drawdown and payment is in the app with the same amount, date, class and custom fields
#   ② app → source   nothing is left over in the app (commitments, remittances, payments)
#   ③ per folio      committed, called, received, outstanding and # payments agree
#   ④ per call       call = Σ its remittances = Σ source; collected = Σ its payments; approved
#   ⑤ client totals  the client's own figures (per-folio total columns, total cells) = the app
#   ⑥ distributions  every entry ↔ one payment (income / face value, TDS, net, type); headers = Σ payments = Σ source; approved
#   ⑦ units          per folio: issued = called ÷ price, redeemed = face value ÷ price, balance = the client's balance units
#   ⑧ provenance     no generated values (payment references must come from a source column)
# ④ and ⑥ check what the PLATFORM computes and shows (call chronology, one event per call; net_payable, gross − net) —
# never values we wrote ourselves (fund-ops review, 2026-10-19).
# Writes out/fund_recon.md (for the report's appendix) and out/fund_recon.json (read by gate.rb for go-live).
# Exits non-zero on any failed check.
#
# Usage: ruby fund_recon.rb [--workspace DIR] [--fund-id ID]       (default: the fund named in drawdowns.yml)
require "optparse"
require "roo"
require "yaml"
require "json"
require "date"
require_relative "../api"

api = Onboarding::Api.new(Onboarding::Api.workspace_from!(ARGV))
opts = {}
OptionParser.new { |o| o.on("--fund-id ID", Integer) { opts[:fund_id] = _1 } }.parse!(ARGV)
config = YAML.safe_load_file(File.join(api.workspace, "mappings", "drawdowns.yml"), permitted_classes: [Date])
assume = config.fetch("assumptions", {})
settings = config.fetch("settings")
TOL = 0.01

# ── Own raw reader (deliberately separate from read_drawdowns.rb) ────────────────────────────────────────────────────
clean = ->(v) { v.is_a?(String) ? v.delete("﻿").gsub(/[[:space:]]+/, " ").strip : v }
num = ->(v) { v.is_a?(Numeric) ? v.to_f : nil }
src = config.fetch("source")
sheet = Roo::Spreadsheet.open(File.join(api.workspace, src.fetch("file"))).sheet(src.fetch("sheet"))
header_row = src.fetch("header_row", 1)
headers = header_row.positive? ? sheet.row(header_row).map { clean.(_1.to_s) } : []
col_of = lambda do |spec|
  # A Hash is ONE spec ({col: E} or {header: …}); Array(hash) would split it into key/value pairs
  specs = spec.is_a?(Hash) ? [spec.key?("col") ? spec : spec.fetch("header")] : Array(spec)
  specs.map do |s|
    if s.is_a?(Hash) then s["col"].upcase.chars.reduce(0) { |a, ch| (a * 26) + ch.ord - 64 }
    else (headers.index { _1.casecmp?(clean.(s.to_s)) } or raise("recon: column #{s.inspect} not in the header row")) + 1
    end
  end
end
cell = ->(row, cols) { cols.map { row[_1 - 1] }.find { |v| !(v.nil? || (v.is_a?(String) && clean.(v).empty?)) } }
fmt = config["folio_format"]
folio_id = lambda do |raw|
  next clean.(raw.to_s) unless fmt

  base = raw.is_a?(Float) ? raw.to_i.to_s : clean.(raw.to_s)
  base = base.split(fmt["strip_after"]).first.to_s if fmt["strip_after"]
  d, s = base.match(/\A(\d+)([A-Za-z]*)\z/)&.captures || [base, ""]
  fmt["pad_digits"] ? "#{d.rjust(fmt['pad_digits'], '0')}#{s}" : base
end
cols = config.fetch("columns")
c = ->(name) { cols[name] && col_of.(cols[name]) }
extras = config.fetch("extras", {})
ex_cols = extras.transform_values { col_of.(_1) }
first_row = src.fetch("first_row", header_row + 1)
last_row = src.fetch("last_row", sheet.last_row)

# Distribution column groups and the balance-units column (own reading of the yml, like the columns above).
# A group value is a column spec, a constant ({value: …}) or a sum of columns ({sum: [...]}, blank = 0).
side = config.dig("distributions", "source") # distributions (and balance units) on a second sheet, joined by folio
side_sheet = side && Roo::Spreadsheet.open(File.join(api.workspace, side.fetch("file"))).sheet(side.fetch("sheet"))
side_headers = side ? side_sheet.row(side.fetch("header_row", 1)).map { clean.(_1.to_s) } : nil
with_headers = ->(hs, &blk) { saved = headers; headers = hs || headers; blk.call.tap { headers = saved } }
val_of = lambda do |spec|
  if spec.is_a?(Hash) && spec.key?("value") then ->(_r) { spec["value"] }
  elsif spec.is_a?(Hash) && spec.key?("sum")
    parts = spec["sum"].map { col_of.(_1) }
    ->(r) { vs = parts.map { num.(cell.(r, _1)) }; vs.all?(&:nil?) ? nil : vs.sum(&:to_f) }
  else cs = col_of.(spec); ->(r) { cell.(r, cs) }
  end
end
dgroups = with_headers.(side_headers) do
  Array(config.dig("distributions", "groups")).map do |g|
    { as: g.fetch("as"), skip_zero: g["skip_when_zero"], replace: g.dig("title", "replace"), title: val_of.(g["title"]), date: val_of.(g["date"]),
      amount: val_of.(g["amount"]), tds: g["tds"] && val_of.(g["tds"]), net: g["net"] && val_of.(g["net"]), type: g["payment_type"] && val_of.(g["payment_type"]) }
  end
end
dist_entries = lambda do |r|
  dgroups.filter_map do |g|
    amt = num.(g[:amount].(r))
    next if amt.nil? || (g[:skip_zero] && amt.zero?)

    t = clean.(g[:title].(r).to_s)
    { as: g[:as], title: g[:replace] ? t.sub(*g[:replace]) : t, date: g[:date].(r), amount: amt,
      tds: g[:tds] ? num.(g[:tds].(r)).to_f : 0.0, net: g[:net] && num.(g[:net].(r)), type: g[:type] && clean.(g[:type].(r)) }
  end
end
bal_spec = config.dig("units", "balance_units")
bal_on_side = bal_spec.is_a?(Hash) && bal_spec["source"] == "distributions"
bal_col = bal_spec && with_headers.(bal_on_side ? side_headers : nil) { col_of.(bal_spec.reject { |k, _| k == "source" }) }

source = {} # folio → {row, committed, unit_class, extras, totals, draws: [{called, notice, due, payments, row}], dists, balance, undated}
case src.fetch("layout")
when "row_per_folio"
  pairs = Array(cols["payments"]).map { |d, a| [col_of.(d), col_of.(a)] }
  totals = (cols["client_totals"] || {}).transform_values { col_of.(_1) }
  (first_row..last_row).each do |n|
    r = sheet.row(n)
    raw = cell.(r, c.("folio"))
    next if raw.nil?

    pays = pairs.filter_map { |d, a| (amt = num.(cell.(r, a)))&.positive? ? { date: cell.(r, d), amount: amt } : nil }
    source[folio_id.(raw)] = { row: n, committed: num.(cell.(r, c.("committed"))), unit_class: clean.(cell.(r, c.("unit_class"))),
                               extras: ex_cols.transform_values { clean.(cell.(r, _1)) }, totals: totals.transform_values { num.(cell.(r, _1)).to_f },
                               draws: [{ row: n, called: num.(cell.(r, c.("called"))), notice: cell.(r, c.("notice_date")),
                                         due: c.("due_date") && cell.(r, c.("due_date")), call_id: c.("call_id") && clean.(cell.(r, c.("call_id")).to_s),
                                         payments: pays }], undated: false,
                               dists: dist_entries.(r), balance: bal_col && num.(cell.(r, bal_col)) }
  end
when "folio_blocks"
  current = nil
  (first_row..last_row).each do |n|
    r = sheet.row(n)
    raw = cell.(r, c.("folio"))
    next if raw.nil?

    id = folio_id.(raw)
    if num.(cell.(r, c.("opens_when") || c.("committed")))
      current = source[id] = { row: n, committed: num.(cell.(r, c.("committed"))), unit_class: clean.(cell.(r, c.("unit_class"))),
                               extras: ex_cols.transform_values { clean.(cell.(r, _1)) }, totals: {}, draws: [], undated: false,
                               dists: [], balance: bal_col && num.(cell.(r, bal_col)) }
    end
    next unless current && source[id].equal?(current)

    date, amt = cell.(r, c.("drawdown_date")), num.(cell.(r, c.("drawdown_amount")))
    current[:draws] << { row: n, called: amt, notice: date, due: nil, call_id: c.("call_id") && clean.(cell.(r, c.("call_id")).to_s),
                         payments: [{ date:, amount: amt }] } if amt && date.is_a?(Date)
    current[:undated] = true if cols["undated_marker"] && clean.(date.to_s) == cols["undated_marker"]
    current[:dists].concat(dist_entries.(r))
  end
when "call_columns"
  # One amount column per call (same order as calls.schedule); the folio's total received spread by the yml rule
  sched_rows = Array(config.dig("calls", "schedule"))
  call_cs = Array(cols["call_columns"]).map { col_of.(_1) }
  abort "✖ recon: #{call_cs.size} call columns vs #{sched_rows.size} scheduled calls" unless call_cs.size == sched_rows.size
  alloc = assume.fetch("payment_allocation")
  totals = (cols["client_totals"] || {}).transform_values { col_of.(_1) }
  (first_row..last_row).each do |n|
    r = sheet.row(n)
    raw = cell.(r, c.("folio"))
    next if raw.nil?

    t = totals.transform_values { num.(cell.(r, _1)).to_f }
    draws = call_cs.each_with_index.filter_map do |cs, i|
      amt = num.(cell.(r, cs))&.round(2)
      next unless amt&.positive?

      sc = sched_rows[i]
      { row: n, called: amt, notice: Date.parse(sc["notice_date"].to_s), due: sc["due_date"] && Date.parse(sc["due_date"].to_s),
        call_id: sc["name"], payments: [] }
    end
    left = t.fetch("received")
    draws.each do |d|
      pay = [left, d[:called]].min.round(2)
      next unless pay.positive?

      d[:payments] << { date: alloc["date"] == "due_date" ? d[:due] : d[:notice], amount: pay }
      left = (left - pay).round(2)
    end
    if left.abs >= 0.005 && alloc["excess"] == "last_call" && draws.any?
      draws.last[:payments] << { date: draws.last[:due], amount: 0 } if draws.last[:payments].empty?
      draws.last[:payments].last[:amount] = (draws.last[:payments].last[:amount] + left).round(2)
    end
    source[folio_id.(raw)] = { row: n, committed: num.(cell.(r, c.("committed"))), unit_class: clean.(cell.(r, c.("unit_class"))),
                               extras: ex_cols.transform_values { clean.(cell.(r, _1)) }, totals: t, draws:, undated: false,
                               dists: [], balance: bal_col && !bal_on_side ? num.(cell.(r, bal_col)) : nil }
  end
end

# Distributions (and balance units) from the second sheet, joined by folio
if side
  folio_c = with_headers.(side_headers) { col_of.(side.fetch("folio")) }
  (side.fetch("first_row", 2)..side.fetch("last_row", side_sheet.last_row)).each do |n|
    r = side_sheet.row(n)
    raw = cell.(r, folio_c)
    next if raw.nil?

    f = source[folio_id.(raw)] or abort("✖ recon: #{side['sheet']} r#{n} folio #{raw} is not on the main sheet")
    f[:dists] = dist_entries.(r)
    f[:balance] = num.(cell.(r, bal_col)) if bal_on_side
  end
end

# ── What the app should hold: the source plus the yml assumptions ───────────────────────────────────────────────────
value_of = ->(n) { n.is_a?(Hash) ? n["value"] : n }
fb = assume["due_date_fallback"]
# Which call a source drawdown belongs to: the client's call id, the client's schedule, or the single call (calls: in the yml)
calls_cfg = config["calls"] or abort("✖ recon: mappings/drawdowns.yml has no calls: section — calls must come from the client")
sched = Array(calls_cfg["schedule"]).map { [_1.fetch("name"), Date.parse(_1.fetch("notice_date").to_s)] }.sort_by(&:last)
recon_call_of = lambda do |d|
  if calls_cfg["id_column"] then d[:call_id]
  elsif sched.any? then sched.reverse.find { _2 <= d[:notice] }&.first
  else calls_cfg["single_call"]
  end
end
# The client's own drawdown dates per call, taken before same-call drawdowns merge: what "one drawdown event" is judged
# on. (The app cannot show it: the builder gives every remittance its call's date, so their spread is always 0.)
src_notices = Hash.new { |h, k| h[k] = [] }
source.each_value do |f|
  if f[:undated] && f[:draws].empty? && (u = assume["undated_drawdown"])
    d = Date.parse(u["date"].to_s)
    # assumed: the date is the yml's placeholder, not the client's, so it says nothing about the call's spread
    f[:draws] << { row: f[:row], called: f[:committed], notice: d, due: nil, payments: [{ date: d, amount: f[:committed] }], assumed: true }
  end
  f[:draws].sort_by! { _1[:notice] }
  f[:draws].each_with_index do |d, _i|
    d[:call] = recon_call_of.(d)
    bad = fb && d[:notice].is_a?(Date) && ((Array(fb["when"]).include?("blank") && !d[:due].is_a?(Date)) ||
                                           (Array(fb["when"]).include?("before_notice") && d[:due].is_a?(Date) && d[:due] < d[:notice]))
    d[:due] = d[:notice] + fb["days"] if bad
    src_notices[d[:call]] << d[:notice] if d[:notice].is_a?(Date) && !d[:assumed]
  end
  suffix = value_of.(config.dig("distributions", "repeat_title_suffix"))
  seen = Hash.new(0)
  f[:dists].each { |e| e[:title] = "#{e[:title]}#{suffix}" if (seen[e[:title]] += 1) > 1 && suffix }
  # One remittance per folio per call: merge this folio's drawdowns that fall in the same call (called = sum, payments kept)
  f[:draws] = f[:draws].group_by { _1[:call] }.map do |call, ds|
    ds.size == 1 ? ds.first : { row: ds.first[:row], call:, called: ds.sum { _1[:called].to_f }, notice: ds.map { _1[:notice] }.grep(Date).min,
                                due: ds.map { _1[:due] }.grep(Date).min, payments: ds.flat_map { _1[:payments] } }
  end
  rule = value_of.(assume["commitment_date"])
  f[:commitment_date] = rule == "first_notice_date" ? (f[:draws].map { _1[:notice] }.grep(Date).min || (x = assume.dig("commitment_date", "fallback")) && Date.parse(x.to_s)) : (rule && Date.parse(rule.to_s))
end

# ── Read the app ────────────────────────────────────────────────────────────────────────────────────────────────────
fund_id = opts[:fund_id] || api.list("/funds.json").find { _1["name"] == config.dig("fund", "name") }&.dig("id") or abort "✖ fund #{config.dig('fund', 'name').inspect} not found — pass --fund-id"
in_fund = ->(rows) { rows.select { _1["fund_id"] == fund_id } } # re-check the fund on every row, never trust a filter alone
commitments = in_fund.(api.list("/capital_commitments.json?fund_id=#{fund_id}&all=true"))
remittances = in_fund.(api.list("/capital_remittances.json?fund_id=#{fund_id}&all=true"))
payments = in_fund.(api.list("/capital_remittance_payments.json?fund_id=#{fund_id}&all=true"))
calls = in_fund.(api.list("/capital_calls.json?fund_id=#{fund_id}&all=true"))
summary = api.call("get", "/funds/#{fund_id}/summary.json")[1]
rem_by_id = remittances.to_h { [_1["id"], _1] }
dists_app = dgroups.any? ? in_fund.(api.list("/capital_distributions.json?fund_id=#{fund_id}&all=true")) : []
dpays = dgroups.any? || bal_col ? in_fund.(api.list("/capital_distribution_payments.json?fund_id=#{fund_id}&all=true")) : []

results = Hash.new { |h, k| h[k] = { checked: 0, ok: 0 } }
issues = []
check = lambda do |test, what, ok, where, msg|
  results[[test, what]][:checked] += 1
  ok ? results[[test, what]][:ok] += 1 : issues << "| #{test} | #{what} | #{where} | #{msg} |"
end
eq = ->(a, b) { (a.nil? && b.nil?) || (!a.nil? && !b.nil? && (a.to_f - b.to_f).abs < TOL) }
same = ->(a, b) { a.is_a?(Numeric) || b.is_a?(Numeric) || a.to_s.match?(/\A-?\d+(\.\d+)?\z/) ? eq.(a, b) : clean.(a.to_s) == clean.(b.to_s) }
iso = ->(d) { d.is_a?(Date) ? d.iso8601 : d }

# ── ① source → app, taking each match out of a pool so nothing counts twice ─────────────────────────────────────────
com_pool = commitments.group_by { _1["folio_id"] }
rem_pool = remittances.group_by { [_1["folio_id"], _1["capital_call_name"]] }
pay_pool = payments.group_by { [_1["folio_id"], rem_by_id[_1["capital_remittance_id"]]&.dig("capital_call_name")] }
per_folio = []
source.each do |folio, f|
  where = "#{src['sheet']} r#{f[:row]} #{folio}"
  cm = com_pool[folio]&.shift
  check.("①", "Commitment exists", !cm.nil?, where, "no commitment")
  next unless cm

  check.("①", "Committed amount", eq.(cm["committed_amount"], f[:committed]), where, "#{f[:committed]} vs #{cm['committed_amount']}")
  check.("①", "Unit class", cm["unit_type"] == f[:unit_class], where, "#{f[:unit_class]} vs #{cm['unit_type']}")
  check.("①", "Commitment date (rule)", cm["commitment_date"] == iso.(f[:commitment_date]), where, "#{f[:commitment_date]} vs #{cm['commitment_date']}")
  extras.select { |_, e| e["target"] == "commitment" }.each_key do |k|
    check.("①", "Commitment field #{k}", same.(cm.dig("custom_fields", k), f[:extras][k]), where, "#{f[:extras][k].inspect} vs #{cm.dig('custom_fields', k).inspect}")
  end
  f[:draws].each do |d|
    rm = rem_pool[[folio, d[:call]]]&.shift
    check.("①", "Remittance exists (folio + call)", !rm.nil?, "#{where} #{d[:call]}", "no remittance")
    next unless rm

    paid = d[:payments].sum { _1[:amount] }
    check.("①", "Called", eq.(rm["call_amount"], d[:called]), "#{where} #{d[:call]}", "#{d[:called]} vs #{rm['call_amount']}")
    check.("①", "Collected = Σ source payments", eq.(rm["collected_amount"], paid), "#{where} #{d[:call]}", "#{paid} vs #{rm['collected_amount']}")
    check.("①", "Verified iff paid", rm["verified"] == paid.positive?, "#{where} #{d[:call]}", "verified=#{rm['verified']}, paid #{paid}")
    if settings["remittance_dates_as_fields"]
      check.("①", "Notice date field", rm.dig("custom_fields", "notice_date") == iso.(d[:notice]), "#{where} #{d[:call]}", "#{d[:notice]} vs #{rm.dig('custom_fields', 'notice_date').inspect}")
      check.("①", "Due date field (rule)", rm.dig("custom_fields", "due_date") == iso.(d[:due]), "#{where} #{d[:call]}", "#{d[:due]} vs #{rm.dig('custom_fields', 'due_date').inspect}")
    end
    extras.select { |_, e| e["target"] == "remittance" }.each_key do |k|
      check.("①", "Remittance field #{k}", same.(rm.dig("custom_fields", k), f[:extras][k]), "#{where} #{d[:call]}", "#{f[:extras][k].inspect} vs #{rm.dig('custom_fields', k).inspect}")
    end
    d[:payments].each do |p|
      pool = pay_pool[[folio, d[:call]]] || []
      i = pool.index { _1["payment_date"] == iso.(p[:date]) && eq.(_1["amount"], p[:amount]) }
      check.("①", "Payment (date + amount)", !i.nil?, "#{where} #{d[:call]}", "#{p[:date]} #{p[:amount]} not found")
      pool.delete_at(i) if i
    end
  end
  called = f[:draws].sum { _1[:called].to_f }
  received = f[:draws].sum { |d| d[:payments].sum { _1[:amount] } }
  per_folio << { folio:, src: [f[:committed].to_f, called, received, called - received, f[:draws].sum { _1[:payments].size }],
                 app: [cm["committed_amount"].to_f, cm["call_amount"].to_f, cm["collected_amount"].to_f, cm["due_amount"].to_f,
                       payments.count { _1["folio_id"] == folio }], totals: f[:totals] }
end

# ── ② app → source: whatever is left in the pools has no source row ─────────────────────────────────────────────────
{ "Commitments" => com_pool, "Remittances" => rem_pool, "Payments" => pay_pool }.each do |what, pool|
  left = pool.values.flatten
  check.("②", "#{what} with no source row", left.empty?, "—", "#{left.size} left: #{left.map { _1['folio_id'] }.uniq.first(8)}")
end

# ── ③ per folio ─────────────────────────────────────────────────────────────────────────────────────────────────────
per_folio.each do |r|
  check.("③", "Folio figures (committed, called, received, outstanding, # payments)", r[:src].zip(r[:app]).all? { |a, b| eq.(a, b) }, r[:folio], "src #{r[:src]} vs app #{r[:app]}")
end

# ── ④ per call ──────────────────────────────────────────────────────────────────────────────────────────────────────
src_by_call = source.values.flat_map { _1[:draws] }.group_by { _1[:call] }
calls.each do |cl|
  rs = remittances.select { _1["capital_call_id"] == cl["id"] }
  ps = payments.select { |p| rs.any? { _1["id"] == p["capital_remittance_id"] } }
  s_called = src_by_call.fetch(cl["name"], []).sum { _1[:called].to_f }
  check.("④", "Call = Σ remittances", eq.(cl["call_amount"], rs.sum { _1["call_amount"].to_f }), cl["name"], "#{cl['call_amount']} vs #{rs.sum { _1['call_amount'].to_f }}")
  check.("④", "Call = Σ source", eq.(cl["call_amount"], s_called), cl["name"], "#{cl['call_amount']} vs #{s_called}")
  check.("④", "Collected = Σ payments", eq.(cl["collected_amount"], ps.sum { _1["amount"].to_f }), cl["name"], "#{cl['collected_amount']} vs #{ps.sum { _1['amount'].to_f }}")
  check.("④", "Call approved", cl["approved"] == true, cl["name"], "approved=#{cl['approved'].inspect}")
end
check.("④", "Every source call exists", (src_by_call.keys - calls.map { _1["name"] }).empty?, "—", "missing #{src_by_call.keys - calls.map { _1['name'] }}")
# Business logic, from the fund-ops review: a call is ONE fund drawdown event, and calls run in date order
window = settings.fetch("call_window_days", 31)
seq_of = ->(name) { name[/\d+/].to_i }
calls.each do |cl|
  check.("④", "Due date on or after call date", cl["due_date"].to_s >= cl["call_date"].to_s, cl["name"], "call #{cl['call_date']}, due #{cl['due_date']}")
  # Judged on the client's drawdown dates in the source (src_notices), not the app's remittance dates
  notices = src_notices[cl["name"]]
  span = notices.empty? ? 0 : (notices.max - notices.min).to_i
  check.("④", "One drawdown event (the client's drawdown dates within #{window} days)", span <= window, cl["name"],
         "the client's drawdown dates span #{span} days (#{notices.min} → #{notices.max}, #{notices.uniq.size} dates, #{notices.size} drawdowns) — not one fund event; the source must say which drawdowns form a call")
end
calls.sort_by { seq_of.(_1["name"]) }.each_cons(2) do |a, b|
  check.("④", "Calls in date order (call and due dates rise with the sequence)", b["call_date"].to_s >= a["call_date"].to_s && b["due_date"].to_s >= a["due_date"].to_s,
         "#{a['name']} → #{b['name']}", "#{a['name']} call #{a['call_date']} due #{a['due_date']}; #{b['name']} call #{b['call_date']} due #{b['due_date']}")
end

# ── ⑥ distributions: every source entry ↔ one payment (folio + title + date + amount), headers = Σ payments ──────────
if dgroups.any?
  dpool = dpays.group_by { [_1["folio_id"], _1["capital_distribution_title"]] }
  amount_in = ->(rec, as) { as == "income" ? rec["income"].to_f : rec["face_value_for_redemption"].to_f }
  source.each do |folio, f|
    f[:dists].each do |e|
      where = "#{folio} #{e[:title]} #{iso.(e[:date])}"
      pool = dpool[[folio, e[:title]]] || []
      i = pool.index { _1["payment_date"] == iso.(e[:date]) && eq.(amount_in.(_1, e[:as]), e[:amount]) }
      check.("⑥", "Distribution payment exists (folio, title, date, amount)", !i.nil?, where, "#{e[:as]} #{e[:amount]} not found")
      next unless i

      dp = pool.delete_at(i)
      # What the platform computes and investors see — never the TDS / net we stored ourselves as custom fields
      check.("⑥", "Platform net payable = client net", eq.(dp["net_payable"], e[:net]), where, "client net #{e[:net]} vs platform net_payable #{dp['net_payable']}") if e[:net]
      check.("⑥", "Platform gross − net = client TDS", eq.(dp["gross_payable"].to_f - dp["net_payable"].to_f, e[:tds]), where,
             "client TDS #{e[:tds]} vs platform #{(dp['gross_payable'].to_f - dp['net_payable'].to_f).round(2)}")
      check.("⑥", "Payment type", clean.(dp.dig("custom_fields", "payment_type").to_s) == e[:type].to_s, where, "#{e[:type].inspect} vs #{dp.dig('custom_fields', 'payment_type').inspect}") if e[:type]
    end
    app_f = dpays.select { _1["folio_id"] == folio }
    s_f = [f[:dists].select { _1[:as] == "income" }.sum { _1[:amount] }, f[:dists].select { _1[:as] == "face_value" }.sum { _1[:amount] },
           f[:dists].sum { _1[:tds] }, f[:dists].sum { _1[:net].to_f }, f[:dists].size]
    a_f = [app_f.sum { _1["income"].to_f }, app_f.sum { _1["face_value_for_redemption"].to_f },
           app_f.sum { _1["gross_payable"].to_f - _1["net_payable"].to_f }, app_f.sum { _1["net_payable"].to_f }, app_f.size]
    check.("⑥", "Folio distributions (income, face value, TDS, net, #)", s_f.zip(a_f).all? { |x, y| eq.(x, y) }, folio, "src #{s_f} vs app #{a_f}")
  end
  left = dpool.values.flatten
  check.("②", "Distribution payments with no source row", left.empty?, "—", "#{left.size} left: #{left.first(5).map { _1.values_at('folio_id', 'capital_distribution_title') }}")
  src_by_title = source.values.flat_map { _1[:dists] }.group_by { _1[:title] }
  dists_app.each do |d|
    ps = dpays.select { _1["capital_distribution_id"] == d["id"] }
    se = src_by_title.fetch(d["title"], [])
    check.("⑥", "Header income = Σ payments = Σ source", eq.(d["income"], ps.sum { _1["income"].to_f }) && eq.(d["income"], se.select { _1[:as] == "income" }.sum { _1[:amount] }), d["title"],
           "#{d['income']} vs Σ payments #{ps.sum { _1['income'].to_f }} vs Σ source #{se.select { _1[:as] == 'income' }.sum { _1[:amount] }}")
    check.("⑥", "Header face value = Σ payments = Σ source", eq.(d["face_value_for_redemption"], ps.sum { _1["face_value_for_redemption"].to_f }) &&
           eq.(d["face_value_for_redemption"], se.select { _1[:as] == "face_value" }.sum { _1[:amount] }), d["title"],
           "#{d['face_value_for_redemption']} vs Σ payments #{ps.sum { _1['face_value_for_redemption'].to_f }} vs Σ source #{se.select { _1[:as] == 'face_value' }.sum { _1[:amount] }}")
    check.("⑥", "Distribution approved", d["approved"] == true, d["title"], "approved=#{d['approved'].inspect}")
  end
  check.("⑥", "Every source distribution exists", (src_by_title.keys - dists_app.map { _1["title"] }).empty?, "—", "missing #{src_by_title.keys - dists_app.map { _1['title'] }}")
end

# ── ⑦ units: issued = called ÷ price, redeemed = face value ÷ price, balance = the client's balance units ────────────
prices = value_of.(config.dig("units", "price_per_class"))
if prices
  source.each do |folio, f|
    price = prices.fetch(f[:unit_class]).to_f
    rs = remittances.select { _1["folio_id"] == folio }
    ps = dpays.select { _1["folio_id"] == folio }
    issued, redeemed = rs.sum { _1["units_quantity"].to_f }, -ps.sum { _1["units_quantity"].to_f }
    # The platform issues units on min(called, collected) per remittance (CapitalRemittance#pending_amount_for_units_allocation)
    want_issued = f[:draws].sum { |d| [d[:called].to_f, d[:payments].sum { _1[:amount] }].min } / price
    want_redeemed = f[:dists].select { _1[:as] == "face_value" }.sum { _1[:amount] } / price
    check.("⑦", "Units issued = min(called, received) ÷ price", (issued - want_issued).abs < 0.0001, folio, "#{want_issued.round(4)} vs #{issued.round(4)}")
    check.("⑦", "Units redeemed = face value ÷ price", (redeemed - want_redeemed).abs < 0.0001, folio, "#{want_redeemed.round(4)} vs #{redeemed.round(4)}")
    check.("⑦", "Balance units = client balance units", (issued - redeemed - f[:balance].to_f).abs < 0.0001, folio, "#{f[:balance].inspect} vs #{(issued - redeemed).round(4)}") if bal_col
  end
end

# ── ⑧ provenance: values in the app must come from the client's data, not be generated by us ───────────────────────
ref_col = cols["payment_reference"] && col_of.(cols["payment_reference"])
payments.each do |p|
  ref = p["reference_no"].to_s.strip
  check.("⑧", "Payment reference from the source (or blank)", ref.empty? || ref_col, "#{p['folio_id']} #{p['payment_date']}",
         "reference #{ref.inspect} is not in the client's data (generated)")
end

# ── ⑤ client totals: per-folio total columns, total cells, fund summary ─────────────────────────────────────────────
per_folio.each do |r|
  next if r[:totals].empty?

  check.("⑤", "Folio received column = app collected", eq.(r[:totals]["received"], r[:app][2]), r[:folio], "#{r[:totals]['received']} vs #{r[:app][2]}") if r[:totals].key?("received")
  check.("⑤", "Folio not-received column = app due", eq.(r[:totals]["not_received"], r[:app][3]), r[:folio], "#{r[:totals]['not_received']} vs #{r[:app][3]}") if r[:totals].key?("not_received")
end
book = Roo::Spreadsheet.open(File.join(api.workspace, src["file"]))
Array(config["client_total_cells"]).each do |t|
  sh = book.sheet(t.fetch("sheet"))
  letters, row = t.fetch("cell").match(/\A([A-Z]+)(\d+)\z/).captures
  v = num.(sh.cell(row.to_i, letters.chars.reduce(0) { |a, ch| (a * 26) + ch.ord - 64 }))
  app_v = case t.fetch("compare")
          when "face_value" then dpays.sum { _1["face_value_for_redemption"].to_f }
          when "income" then dpays.sum { _1["income"].to_f }
          when "balance_units" then remittances.sum { _1["units_quantity"].to_f } + dpays.sum { _1["units_quantity"].to_f }
          else summary[{ "committed" => "committed_amount", "called" => "call_amount", "collected" => "collected_amount", "due" => "due_amount" }.fetch(t["compare"])]
          end
  v, app_v = v.to_f.round(4), app_v.to_f.round(4) if t["compare"] == "balance_units"
  check.("⑤", "#{t['label']} (#{t['sheet']}!#{t['cell']}) = fund #{t['compare']}", eq.(v, app_v), "summary", "#{v.inspect} vs #{app_v}")
end
{ "committed_amount" => source.values.sum { _1[:committed].to_f }, "call_amount" => source.values.sum { |f| f[:draws].sum { _1[:called].to_f } },
  "collected_amount" => source.values.sum { |f| f[:draws].sum { |d| d[:payments].sum { _1[:amount] } } } }.each do |k, v|
  check.("⑤", "Fund #{k} = Σ source", eq.(summary[k], v), "summary", "#{summary[k]} vs #{v.round(2)}")
end
check.("⑤", "Commitment count = folios", summary["capital_commitments_count"] == source.size, "summary", "#{summary['capital_commitments_count']} vs #{source.size}")

# ── Report ──────────────────────────────────────────────────────────────────────────────────────────────────────────
total = results.values.sum { _1[:checked] }
ok = results.values.sum { _1[:ok] }
passed = ok == total
inr = lambda do |x|
  w, p = format("%.2f", x.to_f.abs).split(".")
  h, t = w[0...-3], w[-3..] || w
  "#{'-' if x.to_f.negative?}#{h.empty? ? t : "#{h.reverse.scan(/\d{1,2}/).join(',').reverse},#{t}"}#{".#{p}" unless p == '00'}"
end
md = ["# Fund reconciliation — #{config.dig('fund', 'name')} (fund #{fund_id})", "",
      "Generated #{Time.now.strftime('%Y-%m-%d %H:%M')} by `tools/fund/fund_recon.rb` from `#{src['file']}`; app read through the JSON API only.", "",
      "**Result: #{passed ? '✅' : '❌'} #{ok} / #{total} checks pass.**", "", "| Test | Check | Checked | Pass |", "|---|---|---:|---:|"]
results.each { |(t, w), v| md << "| #{t} | #{w} | #{v[:checked]} | #{v[:ok] == v[:checked] ? "✅ #{v[:ok]}" : "❌ #{v[:ok]}"} |" }
md += ["", "## Failures", "", issues.empty? ? "None." : (["| Test | Check | Where | Detail |", "|---|---|---|---|"] + issues.first(50)).join("\n")]
md += ["", "## Per folio (source → app)", "", "| Folio | Committed | Called | Received | Outstanding | # pay | |", "|---|---:|---:|---:|---:|---:|---|"]
per_folio.each do |r|
  cells = r[:src].zip(r[:app]).each_with_index.map { |(a, b), i| v = i == 4 ? a.to_i.to_s : inr.(a); eq.(a, b) ? v : "#{v} → #{i == 4 ? b.to_i : inr.(b)}" }
  md << "| #{r[:folio]} | #{cells.join(' | ')} | #{r[:src].zip(r[:app]).all? { |a, b| eq.(a, b) } ? '✅' : '❌'} |"
end
out_dir = File.join(api.workspace, "out")
File.write(File.join(out_dir, "fund_recon.md"), md.join("\n") + "\n")
File.write(File.join(out_dir, "fund_recon.json"), JSON.pretty_generate(
  passed:, checks: total, ok:, fund_id:, fund: config.dig("fund", "name"), source: src["file"], generated_at: Time.now.iso8601,
  failures: issues.size
))
puts md.first(5 + results.size + 3).join("\n")
issues.first(10).each { puts _1 }
puts "→ #{File.join(out_dir, 'fund_recon.md')}, fund_recon.json (passed=#{passed})"
exit(passed ? 0 : 1)
