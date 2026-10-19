# One command that knows the onboarding order. Run it from the client workspace.
#   ruby onboard.rb status       where the onboarding stands and what is next (read-only)
#   ruby onboard.rb next         the next step's plan (▶) — writes nothing
#   ruby onboard.rb next --run   run that ONE step, then confirm it (✔ / ✖) from read-backs
# Each step's "done" is read from the app (JSON API) and the workspace — never remembered — so re-running after a crash or
# a fix picks up where it is and never uploads twice. It stops on any failure (an upload that did not fully succeed, a count
# that does not match) and never runs investor access: that step only shows the gate.
# It calls the existing tools (api.rb, fund/*, gate.rb); it adds no API of its own.
require "open3"
require "roo"
require "yaml"
require "json"
require "time"
require_relative "api"
require_relative "gate"

TOOLS = __dir__
api = Onboarding::Api.new(Onboarding::Api.workspace_from!(ARGV))
WS = api.workspace
cmd = ARGV.shift || "status"
run = ARGV.delete("--run")
abort "usage: ruby onboard.rb status | next [--run]" unless %w[status next].include?(cmd)

yml_path = File.join(WS, "mappings", "drawdowns.yml")
config = File.exist?(yml_path) ? YAML.safe_load_file(yml_path, permitted_classes: [Date]) : {}
fund_name = config.dig("fund", "name")
out = File.join(WS, "out", "fund")
built = ->(file) { File.join(out, file) }
rows_in = ->(file) { File.exist?(built.(file)) ? Roo::Spreadsheet.open(built.(file)).sheet(0).last_row.to_i - 1 : 0 }
col_values = lambda do |file, header|
  return [] unless File.exist?(built.(file)) # not built yet: nothing to compare
  s = Roo::Spreadsheet.open(built.(file)).sheet(0)
  i = s.row(1).index(header) or return []
  (2..s.last_row).map { s.cell(_1, i + 1) }
end

# ── App reads (memoised per run) ────────────────────────────────────────────────────────────────────────────────────
memo = {}
fetch = ->(key, &blk) { memo.key?(key) ? memo[key] : (memo[key] = blk.call) }
fund = -> { fetch.(:fund) { fund_name && api.list("/funds.json").find { _1["name"] == fund_name } } }
fid = -> { fund.()&.dig("id") }
in_fund = ->(rows) { rows.select { _1["fund_id"] == fid.() } }
app = lambda do |what|
  fetch.(what) do
    case what
    when :investors then api.list("/investors.json?all=true")
    when :commitments then in_fund.(api.list("/capital_commitments.json?fund_id=#{fid.()}&all=true"))
    when :calls then in_fund.(api.list("/capital_calls.json?fund_id=#{fid.()}&all=true"))
    when :remittances then in_fund.(api.list("/capital_remittances.json?fund_id=#{fid.()}&all=true"))
    when :payments then in_fund.(api.list("/capital_remittance_payments.json?fund_id=#{fid.()}&all=true"))
    when :distributions then in_fund.(api.list("/capital_distributions.json?fund_id=#{fid.()}&all=true"))
    when :dist_payments then in_fund.(api.list("/capital_distribution_payments.json?fund_id=#{fid.()}&all=true"))
    when :form_types then api.list("/form_types.json")
    when :uploads then api.list("/import_uploads.json")
    end
  end
end
# The uploads index always paginates (no all=true, G41) — ask per import type, newest first, so older uploads are not missed
uploads_of = ->(type) { fetch.(:"uploads_#{type}") { api.list("/import_uploads.json?q[import_type_eq]=#{type}") } }
uploaded_ok = ->(type) { uploads_of.(type).any? { _1["import_type"] == type && _1["failed_row_count"].to_i.zero? && _1["processed_row_count"].to_i.positive? } }

# Runs a tool, echoes its output, returns success
tool = lambda do |*args|
  stdout, stderr, status = Open3.capture3("ruby", *args.map(&:to_s), "--workspace", WS)
  (stdout + stderr).each_line { |l| puts "    #{l}" unless l.include?("CHECK-DATA MODE") }
  status.success?
end
# Upload through api.rb and insist on a full success (status "Completed" alone is not success)
upload = lambda do |type, file|
  stdout, stderr, = Open3.capture3("ruby", File.join(TOOLS, "api.rb"), "--workspace", WS, "upload", type, built.(file))
  (stdout + stderr).each_line { |l| puts "    #{l}" unless l.include?("CHECK-DATA MODE") }
  stdout.match?(/outcome="succeeded".*failed=0/)
end

dists_on = !config["distributions"].nil?
units_on = !config["units"].nil?
recon_path = File.join(WS, "out", "fund_recon.json")
newest_fund_upload = lambda do
  types = Onboarding::Gate::IMPORT_STEP.keys
  types.flat_map { uploads_of.(_1) }.map { Time.parse(_1["created_at"]) }.max
end

# ── The steps: [name, done?, plan, run] ─────────────────────────────────────────────────────────────────────────────
steps = [
  ["Workspace ready",
   -> { %w[onboarding.yml state/token mappings/drawdowns.yml].all? { File.exist?(File.join(WS, _1)) } && File.exist?(File.join(WS, "#{config['client']}_client_questions.md")) },
   -> { "create the missing files: onboarding.yml, state/token (api.rb sign_in), mappings/drawdowns.yml, <client>_client_questions.md" },
   -> { false }],
  ["Sandbox on",
   -> { api.call("get", "/entities/#{api.entity_id}.json")[1].dig("entity_setting", "sandbox") == true },
   -> { "PATCH /entities/#{api.entity_id}.json sandbox: true, sandbox_emails: #{api.ops_email}" },
   -> { tool.(File.join(TOOLS, "api.rb"), "sandbox_on") }],
  ["Build upload files",
   lambda {
     calls = built.("05a_calls.xlsx")
     sources = [yml_path, File.join(WS, config.dig("source", "file").to_s), File.join(WS, "#{config['client']}_client_questions.md")]
     File.exist?(calls) && sources.all? { File.exist?(_1) && File.mtime(_1) <= File.mtime(calls) }
   },
   -> { "read_drawdowns.rb → out/folios.json, then build_fund_uploads.rb → out/fund/ (question ids, gate, money checks)" },
   -> { tool.(File.join(TOOLS, "fund", "read_drawdowns.rb")) && tool.(File.join(TOOLS, "fund", "build_fund_uploads.rb")) }],
  ["Fund",
   -> { !fund.().nil? },
   -> { "POST /funds.json with out/fund/01_fund.json (#{fund_name})" },
   lambda {
     status, body = api.call("post", "/funds.json", body: JSON.parse(File.read(built.("01_fund.json"))))
     puts "    HTTP #{status} #{body.is_a?(Hash) ? body.slice('id', 'name') : body.to_s[0, 200]}"
     status == 201
   }],
  ["Unit settings",
   -> { uploaded_ok.("FundUnitSetting") },
   -> { "upload FundUnitSetting out/fund/01b_unit_settings.xlsx (#{rows_in.('01b_unit_settings.xlsx')} classes)" },
   -> { upload.("FundUnitSetting", "01b_unit_settings.xlsx") }],
  ["Form types",
   lambda {
     names = app.(:form_types).map { _1["name"] }
     Dir[File.join(out, "02_form_types", "*.json")].all? { names.include?(JSON.parse(File.read(_1)).dig("form_type", "name")) }
   },
   -> { "POST /form_types.json for #{Dir[File.join(out, '02_form_types', '*.json')].map { File.basename(_1, '.json') }.join(', ')} (missing ones only)" },
   lambda {
     names = app.(:form_types).map { _1["name"] }
     Dir[File.join(out, "02_form_types", "*.json")].all? do |f|
       payload = JSON.parse(File.read(f))
       next true if names.include?(payload.dig("form_type", "name"))

       status, body = api.call("post", "/form_types.json", body: payload)
       puts "    #{File.basename(f)}: HTTP #{status} #{body.is_a?(Hash) ? body.slice('id', 'name') : body.to_s[0, 120]}"
       status == 201
     end
   }],
  ["Investors",
   -> { (col_values.("03_investors.xlsx", "Name").compact - app.(:investors).map { _1["investor_name"] }).empty? },
   -> { "upload Investor out/fund/03_investors.xlsx (#{rows_in.('03_investors.xlsx')})" },
   -> { upload.("Investor", "03_investors.xlsx") }],
  ["Commitments",
   -> { app.(:commitments).size >= rows_in.("04_commitments.xlsx") },
   -> { "upload CapitalCommitment out/fund/04_commitments.xlsx (#{rows_in.('04_commitments.xlsx')})" },
   -> { upload.("CapitalCommitment", "04_commitments.xlsx") }],
  ["Calls",
   -> { (col_values.("05a_calls.xlsx", "Name") - app.(:calls).map { _1["name"] }).empty? },
   -> { "upload CapitalCall out/fund/05a_calls.xlsx (#{rows_in.('05a_calls.xlsx')})" },
   -> { upload.("CapitalCall", "05a_calls.xlsx") }],
  ["Remittances",
   -> { app.(:remittances).size >= rows_in.("05b_remittances.xlsx") },
   -> { "upload CapitalRemittance out/fund/05b_remittances.xlsx (#{rows_in.('05b_remittances.xlsx')})" },
   -> { upload.("CapitalRemittance", "05b_remittances.xlsx") }],
  ["Payments",
   -> { app.(:payments).size >= rows_in.("05c_payments.xlsx") },
   -> { "upload CapitalRemittancePayment out/fund/05c_payments.xlsx (#{rows_in.('05c_payments.xlsx')})" },
   -> { upload.("CapitalRemittancePayment", "05c_payments.xlsx") }],
  ["Approve calls + verify",
   -> { app.(:calls).all? { _1["approved"] } && app.(:remittances).reject { _1["collected_amount"].to_f.zero? }.all? { _1["verified"] } },
   -> { "approve every unapproved call, then bulk Verify each call's paid remittances; wait until verified counts settle" },
   lambda {
     app.(:calls).each do |c|
       unless c["approved"]
         s, = api.call("post", "/capital_calls/#{c['id']}/approve.json")
         puts "    approve #{c['name']}: HTTP #{s}"
       end
       s, b = api.call("post", "/capital_remittances/bulk_actions.json?bulk_action=Verify&capital_call_id=#{c['id']}&verified=false&collected_amount_positive=true")
       puts "    verify #{c['name']}: HTTP #{s} #{b.is_a?(Hash) ? b.slice('count') : ''}"
     end
     paid = -> { in_fund.(api.list("/capital_remittances.json?fund_id=#{fid.()}&all=true")).reject { _1["collected_amount"].to_f.zero? } }
     api.wait_until_stable { paid.().count { _1["verified"] } }
     paid.().all? { _1["verified"] }
   }],
  ["Distributions",
   -> { !dists_on || app.(:distributions).size >= rows_in.("06a_distributions.xlsx") },
   -> { "upload CapitalDistribution out/fund/06a_distributions.xlsx (#{rows_in.('06a_distributions.xlsx')})" },
   -> { upload.("CapitalDistribution", "06a_distributions.xlsx") }],
  ["Distribution payments",
   -> { !dists_on || app.(:dist_payments).size >= rows_in.("06b_dist_payments.xlsx") },
   -> { "upload CapitalDistributionPayment out/fund/06b_dist_payments.xlsx (#{rows_in.('06b_dist_payments.xlsx')})" },
   -> { upload.("CapitalDistributionPayment", "06b_dist_payments.xlsx") }],
  ["TDS account entries",
   -> { !dists_on || rows_in.("07_account_entries.xlsx").zero? || uploaded_ok.("AccountEntry") },
   -> { "upload AccountEntry out/fund/07_account_entries.xlsx (#{rows_in.('07_account_entries.xlsx')} TDS entries)" },
   -> { upload.("AccountEntry", "07_account_entries.xlsx") }],
  ["TDS fees + recompute",
   lambda {
     next true unless dists_on && File.exist?(built.("07c_expected_net.json"))

     # Done when the PLATFORM shows every payment's net = the client's net (never our own copies)
     expected = JSON.parse(File.read(built.("07c_expected_net.json")))
     app.(:dist_payments).all? do |p|
       e = expected["#{p['folio_id']}|#{p['capital_distribution_title']}"]
       e.nil? || e["net"].nil? || (p["net_payable"].to_f - e["net"].to_f).abs < 0.01
     end
   },
   -> { "PATCH each distribution with its \"Tax\" fee (out/fund/07b_distribution_fees.json), then recompute_fees; wait until net payable = the client's net" },
   lambda {
     fees = JSON.parse(File.read(built.("07b_distribution_fees.json")))
     by_title = app.(:distributions).to_h { [_1["title"], _1] }
     pays = -> { in_fund.(api.list("/capital_distribution_payments.json?fund_id=#{fid.()}&all=true")) }
     taxed = ->(ps) { ps.count { (_1["gross_payable"].to_f - _1["net_payable"].to_f).abs >= 0.01 } }
     fees.all? do |f|
       d = by_title[f["title"]]
       unless d
         puts "    ✖ no distribution #{f['title']}"
         next false
       end
       ps = pays.().select { _1["capital_distribution_id"] == d["id"] }
       # The fee cannot be read back (no fees in the distribution JSON), so add it only while NO tax is applied yet;
       # a partly-taxed distribution is ambiguous — stop rather than risk a second fee
       if taxed.(ps).zero?
         s, = api.call("patch", "/capital_distributions/#{d['id']}.json", body: { capital_distribution: { distribution_fees_attributes: [f["fee"]] } })
         puts "    fee #{f['fee']['name']}: HTTP #{s}"
         next false unless s.between?(200, 299)
       end
       s, = api.call("patch", "/capital_distributions/#{d['id']}/recompute_fees.json")
       puts "    recompute #{f['title']}: HTTP #{s}"
       true
     end && (api.wait_until_stable { taxed.(pays.()) }; true)
   }],
  ["Approve distributions",
   -> { !dists_on || app.(:distributions).all? { _1["approved"] } },
   -> { "approve every unapproved distribution" },
   lambda {
     app.(:distributions).reject { _1["approved"] }.all? do |d|
       s, = api.call("post", "/capital_distributions/#{d['id']}/approve.json")
       puts "    approve #{d['title']}: HTTP #{s}"
       s.between?(200, 299)
     end
   }],
  ["Units",
   lambda {
     next true unless units_on

     o, = Open3.capture3("ruby", File.join(TOOLS, "fund", "apply_units.rb"), "--workspace", WS)
     o.include?("nothing to do")
   },
   -> { "apply_units.rb --execute: allocate on calls, price + redeem redemptions" },
   -> { tool.(File.join(TOOLS, "fund", "apply_units.rb"), "--execute") }],
  ["Fund recon",
   lambda {
     next false unless File.exist?(recon_path)

     r = JSON.parse(File.read(recon_path))
     r["passed"] == true && (newest_fund_upload.().nil? || Time.parse(r["generated_at"]) > newest_fund_upload.())
   },
   -> { "fund_recon.rb → out/fund_recon.md / .json (must pass, and be newer than the last fund import)" },
   -> { tool.(File.join(TOOLS, "fund", "fund_recon.rb")) }],
  ["Investor access",
   -> { false },
   -> { "never run by this tool — explicit approval + every M item answered. Gate now: #{Onboarding::Gate.evaluate(WS, :investor_access).then { |ok, need, _| ok ? 'open' : "blocked (#{need.join(' ')})" }}" },
   -> { false }]
]

# ── status / next ───────────────────────────────────────────────────────────────────────────────────────────────────
# The token first: an expired one would otherwise surface as a 401 deep inside a tool (tokens from sign_in last an hour)
token_status, = api.call("get", "/entities/#{api.entity_id}.json")
abort "✖ the API token in state/token is not accepted (HTTP #{token_status}) — sign in again: dev `OPS_PASSWORD=… ruby api.rb sign_in`, " \
      "otherwise paste a new token from Profile › API tokens into state/token; then rerun" unless token_status == 200
mode = Onboarding::Gate.config(WS)["mode"] || "production"
puts "#{fund_name} — entity #{api.entity_id}#{fid.() ? ", fund #{fid.()}" : ''} · mode #{mode}"
first_open = nil
steps.each_with_index do |(name, done, plan, _), i|
  ok = begin
    done.()
  rescue StandardError => e
    warn "    (#{name}: #{e.message[0, 120]})"
    false
  end
  first_open ||= i unless ok
  puts format("  %s %2d %-24s%s", ok ? "✔" : (i == first_open ? "▶" : "·"), i + 1, name, i == first_open ? "  ← next: #{plan.()}" : "") if cmd == "status" || i == first_open
  break if cmd == "next" && i == first_open
end
exit 0 if cmd == "status" || first_open.nil?

name, done, plan, action = steps[first_open]
unless run
  puts "(plan only — `ruby onboard.rb next --run` to run step #{first_open + 1})"
  exit 0
end
abort "✖ #{name}: not something this tool runs — #{plan.()}" if [0, steps.size - 1].include?(first_open)

puts "━━━━━━━━━━ #{Time.now.strftime('%H:%M:%S')} · STEP #{first_open + 1} / #{steps.size} · #{name} ━━━━━━━━━━", "▶ Plan: #{plan.()}"
started = Time.now
ok = action.()
memo.clear
confirmed = ok && done.()
if confirmed
  puts "✔ Done #{Time.now.strftime('%H:%M:%S')}: #{name} (#{(Time.now - started).round}s) — confirmed from read-back. Next: `ruby onboard.rb next`"
else
  abort "✖ #{name} did not complete (#{(Time.now - started).round}s) — see the output above; fix, then run `ruby onboard.rb next` again"
end
