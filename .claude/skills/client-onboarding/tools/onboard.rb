# One command that knows the onboarding order. Run it from the client workspace.
#   ruby onboard.rb status       where the onboarding stands and what is next (read-only)
#   ruby onboard.rb next         the next step's plan (▶) — writes nothing
#   ruby onboard.rb next --run   run that ONE step, then confirm it (✔ / ✖) from read-backs
#   add --portfolio to follow only the portfolio track (workspace, sandbox, fund, then the portfolio + KPI steps) — it does
#   not wait on the fund data steps, so a fund held back by client questions does not hold back the portfolio
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
require_relative "portfolio/common"

TOOLS = __dir__
api = Onboarding::Api.new(Onboarding::Api.workspace_from!(ARGV))
WS = api.workspace
cmd = ARGV.shift || "status"
run = ARGV.delete("--run")
portfolio_track = ARGV.delete("--portfolio")
abort "usage: ruby onboard.rb status | next [--run] [--portfolio]" unless %w[status next].include?(cmd)

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
# Upload through api.rb and insist on a full success (status "Completed" alone is not success); a bare file name is in out/fund
upload = lambda do |type, file, step = nil|
  path = file.include?("/") ? file : built.(file)
  stdout, stderr, = Open3.capture3("ruby", File.join(TOOLS, "api.rb"), "--workspace", WS, "upload", type, path, *step)
  (stdout + stderr).each_line { |l| puts "    #{l}" unless l.include?("CHECK-DATA MODE") }
  stdout.match?(/outcome="succeeded".*failed=0/)
end

dists_on = !config["distributions"].nil?
units_on = !config["units"].nil?
recon_path = File.join(WS, "out", "fund_recon.json")
newest_fund_upload = lambda do
  # Fund imports only: not the portfolio's (its companies are an Investor import too — told apart by the file name)
  types = Onboarding::Gate::IMPORT_STEP.reject { |_, step| %i[portfolio kpis].include?(step) }.keys
  types.flat_map { uploads_of.(_1) }.reject { _1["name"].to_s.include?("portfolio_companies") }.map { Time.parse(_1["created_at"]) }.max
end

# ── Portfolio + KPIs (only with mappings/portfolio.yml) ─────────────────────────────────────────────────────────────
P = Onboarding::Portfolio
port_on = File.exist?(P.yml_path(WS))
pcfg = port_on ? YAML.safe_load_file(P.yml_path(WS), permitted_classes: [Date]) : {}
pout = P.out_dir(WS)
pbuilt = ->(file) { File.join(pout, file) }
sheet_rows = lambda do |path|
  return [] unless File.exist?(path)

  s = Roo::Spreadsheet.open(path).sheet(0)
  heads = s.row(1)
  (2..s.last_row.to_i).map { |r| heads.zip(s.row(r)).to_h }
end
companies_in_app = -> { fetch.(:pcos) { api.list("/investors.json?all=true").select { _1["category"] == "Portfolio Company" }.to_h { [P.clean(_1["investor_name"]), _1] } } }
pis_in_app = -> { fetch.(:pis) { in_fund.(api.list("/portfolio_investments.json?fund_id=#{fid.()}&all=true")) } }
kpi_books = -> { File.exist?(pbuilt.("kpi_workbooks.json")) ? JSON.parse(File.read(pbuilt.("kpi_workbooks.json"))) : [] }
live_books = -> { kpi_books.().reject { _1["hold"] } }
company_id = ->(name) { companies_in_app.().dig(name, "id") or raise "no portfolio company #{name}" }
kpis_of = ->(cid) { fetch.(:"kpis_#{cid}") { api.list("/kpis.json?q[portfolio_company_id_eq]=#{cid}&all=true").select { _1["portfolio_company_id"] == cid } } }
mappings_of = ->(cid) { fetch.(:"maps_#{cid}") { api.list("/investor_kpi_mappings.json?investor_id=#{cid}").select { _1["investor_id"] == cid } } }
verdict_path = ->(b) { File.join(WS, "out", "kpi_dryrun", "#{b['name']}.json") }
recon_file = ->(b, phase) { File.join(WS, "out", "kpi_recon", "#{b['name']}.#{phase}.json") }
read_json = ->(path) { File.exist?(path) ? JSON.parse(File.read(path)) : {} }
# KPIs stored from this workbook: their notes name one of its sheets (KpiWorkbookReader writes "Sheet: …, Period: …")
from_book = lambda do |b|
  sheets = Roo::Spreadsheet.open(b["path"]).sheets
  kpis_of.(company_id.(b["company"])).select { |k| (sh = k["notes"].to_s[/Sheet: (.+?), Period:/m, 1]) && sheets.include?(sh) }
end
kpi_tool = ->(script, b, *extra) { tool.(File.join(TOOLS, script), "--company", company_id.(b["company"]), "--file", b["path"], *extra) }

# Form types: each built one exists and holds every field (name + type); creates missing types, adds missing fields
form_fields = ->(ft_id) { api.list("/form_custom_fields.json?form_type_id=#{ft_id}") }
form_types_ok = lambda do |fix|
  Dir[pbuilt.("02_form_types/*.json")].all? do |f|
    payload = JSON.parse(File.read(f))
    want = payload.dig("form_type", "form_custom_fields_attributes")
    ft = api.list("/form_types.json").find { _1["name"] == payload.dig("form_type", "name") }
    if ft.nil?
      next false unless fix

      st, body = api.call("post", "/form_types.json", body: payload)
      puts "    form type #{payload.dig('form_type', 'name')}: HTTP #{st} #{body.is_a?(Hash) ? body.slice('id') : body.to_s[0, 120]}"
      next st == 201
    end
    have = form_fields.(ft["id"]).to_h { [_1["name"], _1["field_type"]] }
    wrong = want.select { have.key?(_1["name"]) && have[_1["name"]] != _1["field_type"] }
    wrong.each { puts "    ✖ #{ft['name']}.#{_1['name']} is #{have[_1['name']]}, expected #{_1['field_type']} — fix it in the UI (PATCH /form_custom_fields/:id.json)" } if fix
    add = want.reject { have.key?(_1["name"]) }
    if fix && add.any?
      st, = api.call("patch", "/form_types/#{ft['id']}.json", body: { form_type: { form_custom_fields_attributes: add } })
      puts "    form type #{ft['name']}: +#{add.size} fields (#{add.map { _1['name'] }.join(', ')}) HTTP #{st}"
      next false unless st.between?(200, 299)
    end
    wrong.empty? && (fix || add.empty?)
  end
end
built_mappings = -> { sheet_rows.(pbuilt.("09_kpi_mappings.xlsx")) }
# A built mapping's app twin (same company, reported and standard name) and whether it agrees
# (names compared with blanks collapsed: the import squeezes a label's double spaces, and the reader ignores whitespace)
squash = ->(v) { v.to_s.gsub(/[[:space:]]+/, " ").strip }
mapping_twin = lambda do |m|
  mappings_of.(company_id.(m["Stakeholder"])).find { squash.(_1["reported_kpi_name"]) == squash.(m["Reported Kpi Name"]) && squash.(_1["standard_kpi_name"]) == squash.(m["Standard Kpi Name"]) }
end
mapping_ok = lambda do |m, a|
  a && a["source_sheet"].to_s == m["Source Sheet"].to_s && a["compute_formula"].to_s == m["Compute Formula"].to_s &&
    (a["autofill"] == "compute") == (m["Auto Fill"] == "compute") && a["category"] == m["Category"] && a["data_type"] == m["Data Type"]
end
# App mappings of the KPI companies that no built mapping matches (e.g. the client asked for fewer)
extra_mappings = lambda do
  ms = built_mappings.()
  ms.map { _1["Stakeholder"] }.uniq.flat_map do |co|
    mappings_of.(company_id.(co)).reject { |a| ms.any? { |m| m["Stakeholder"] == co && squash.(m["Reported Kpi Name"]) == squash.(a["reported_kpi_name"]) && squash.(m["Standard Kpi Name"]) == squash.(a["standard_kpi_name"]) } }
  end
end
newest_upload_of = ->(*types) { types.flat_map { uploads_of.(_1) }.map { Time.parse(_1["created_at"]) }.max }

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
  ["Build portfolio files",
   lambda {
     next true unless port_on

     marker = pbuilt.("09_kpi_mappings.xlsx")
     srcs = [P.yml_path(WS), File.join(WS, "#{pcfg['client']}_client_questions.md")] +
            %w[companies investments valuations].map { File.join(WS, "source", pcfg.dig(_1, "source", "file").to_s) }
     File.exist?(marker) && File.exist?(pbuilt.("06_portfolio_companies.xlsx")) && srcs.all? { File.exist?(_1) && File.mtime(_1) <= File.mtime(marker) }
   },
   -> { "build_portfolio_uploads.rb → out/portfolio/ (form types, companies, investments, valuations, logos), then build_kpi_mappings.rb (label check, merges, mappings, workbook list)" },
   -> { tool.(File.join(TOOLS, "portfolio", "build_portfolio_uploads.rb")) && tool.(File.join(TOOLS, "portfolio", "build_kpi_mappings.rb")) }],
  ["Portfolio companies",
   lambda {
     next true unless port_on

     form_types_ok.(false) && (sheet_rows.(pbuilt.("06_portfolio_companies.xlsx")).map { P.clean(_1["Name"]) } - companies_in_app.().keys).empty?
   },
   -> { "form types out/portfolio/02_form_types (create / add missing fields), then upload Investor out/portfolio/06_portfolio_companies.xlsx (#{sheet_rows.(pbuilt.('06_portfolio_companies.xlsx')).size}) if any company is missing" },
   lambda {
     form_types_ok.(true) &&
       ((sheet_rows.(pbuilt.("06_portfolio_companies.xlsx")).map { P.clean(_1["Name"]) } - companies_in_app.().keys).empty? ||
        upload.("Investor", pbuilt.("06_portfolio_companies.xlsx"), "portfolio"))
   }],
  ["Logos",
   lambda {
     next true unless port_on

     read_json.(pbuilt.("logos.json")).keys.all? { |co| api.list("/documents.json?owner_type=Investor&owner_id=#{company_id.(co)}").any? { _1["name"] == "Logo" } }
   },
   -> { "attach each company's logo as its \"Logo\" document (#{read_json.(pbuilt.('logos.json')).size}, missing ones only)" },
   lambda {
     read_json.(pbuilt.("logos.json")).all? do |co, file|
       id = company_id.(co)
       next true if api.list("/documents.json?owner_type=Investor&owner_id=#{id}").any? { _1["name"] == "Logo" }

       tool.(File.join(TOOLS, "api.rb"), "attach", "Investor", id, "Logo", file)
     end
   }],
  ["Portfolio investments",
   -> { !port_on || pis_in_app.().size >= sheet_rows.(pbuilt.("07_portfolio_investments.xlsx")).size },
   -> { "upload PortfolioInvestment out/portfolio/07_portfolio_investments.xlsx (#{sheet_rows.(pbuilt.('07_portfolio_investments.xlsx')).size})" },
   -> { upload.("PortfolioInvestment", pbuilt.("07_portfolio_investments.xlsx")) }],
  ["Valuations",
   lambda {
     next true unless port_on

     app_vals = api.list("/valuations.json?all=true").map { [P.clean(_1["portfolio_company_name"]), _1["valuation_date"], _1["investment_instrument_name"]] }
     sheet_rows.(pbuilt.("08_valuations.xlsx")).all? do |v|
       d = v["Valuation Date"]
       app_vals.include?([P.clean(v["Portfolio Company"]), d.is_a?(Date) ? d.iso8601 : d.to_s, v["Instrument"]])
     end
   },
   -> { "upload Valuation out/portfolio/08_valuations.xlsx (#{sheet_rows.(pbuilt.('08_valuations.xlsx')).size})" },
   -> { upload.("Valuation", pbuilt.("08_valuations.xlsx")) }],
  ["Portfolio recon",
   lambda {
     next true unless port_on

     r = read_json.(File.join(WS, "out", "portfolio_recon.json"))
     last = newest_upload_of.("PortfolioInvestment", "Valuation")
     r["passed"] == true && (last.nil? || Time.parse(r["generated_at"]) > last)
   },
   -> { "portfolio_recon.rb → out/portfolio_recon.md / .json (must pass, and be newer than the last portfolio import)" },
   -> { tool.(File.join(TOOLS, "portfolio", "portfolio_recon.rb")) }],
  ["KPI mappings",
   -> { !port_on || (built_mappings.().all? { mapping_ok.(_1, mapping_twin.(_1)) } && extra_mappings.().empty?) },
   lambda {
     ms = built_mappings.()
     "#{ms.size} mappings: upload InvestorKpiMapping with the missing ones, PATCH source sheets that differ; anything else that differs is reported"
   },
   lambda {
     ms = built_mappings.()
     missing = ms.reject { mapping_twin.(_1) }
     if missing.any?
       path = pbuilt.("09_kpi_mappings_missing.xlsx")
       heads = Roo::Spreadsheet.open(pbuilt.("09_kpi_mappings.xlsx")).sheet(0).row(1)
       P.write_xlsx(path, "Mappings", heads, missing.map { |m| heads.map { m[_1] } })
       next false unless upload.("InvestorKpiMapping", path)

       memo.clear
     end
     # Mappings the build no longer has are never deleted here (an undo — needs ops' approval each time); list them
     extra_mappings.().each { puts "    ✖ in the app, not in the build: mapping #{_1['id']} #{_1['investor_name'].to_s[0, 20]} · #{_1['standard_kpi_name']} ← #{_1['reported_kpi_name']} — delete with approval: api.rb delete /investor_kpi_mappings/#{_1['id']}.json" }
     same = ms.all? do |m|
       a = mapping_twin.(m)
       next true if mapping_ok.(m, a)

       if a && a["source_sheet"].to_s != m["Source Sheet"].to_s
         st, = api.call("patch", "/investor_kpi_mappings/#{a['id']}.json", body: { investor_kpi_mapping: { source_sheet: m["Source Sheet"] } })
         puts "    #{m['Stakeholder'][0, 20]} · #{m['Standard Kpi Name']}: source sheet #{a['source_sheet'].inspect} → #{m['Source Sheet'].inspect} HTTP #{st}"
         next st.between?(200, 299) && mapping_ok.(m, a.merge("source_sheet" => m["Source Sheet"]))
       end
       puts "    ✖ #{m['Stakeholder'][0, 20]} · #{m['Standard Kpi Name']} differs in the app (#{a&.slice('category', 'data_type', 'autofill', 'compute_formula')}) — fix by hand"
       false
     end
     same && extra_mappings.().empty?
   }],
  ["KPI dry runs",
   lambda {
     next true unless port_on

     newest_map = live_books.().map { |b| mappings_of.(company_id.(b["company"])).map { Time.parse(_1["updated_at"]) }.max }.compact.max
     live_books.().all? do |b|
       v, c = verdict_path.(b), read_json.(verdict_path.(b).sub(/\.json\z/, ".check.json"))
       File.exist?(v) && c["passed"] == true && File.mtime(v) >= File.mtime(b["path"]) && (newest_map.nil? || File.mtime(v) > newest_map)
     end
   },
   -> { "for each workbook (#{live_books.().map { _1['name'] }.join(', ')}): kpi_dry_run.rb (validate_upload, no writes), then check_dryrun_cells.rb (every ok cell = its source cell)" },
   lambda {
     live_books.().all? do |b|
       puts "    ── #{b['name']}"
       kpi_tool.("kpi_dry_run.rb", b, "--as-of", b["as_of"], "--period", b["period"]) &&
         tool.(File.join(TOOLS, "check_dryrun_cells.rb"), "--verdict", verdict_path.(b), "--file", b["path"])
     end
   }],
  ["KPI uploads",
   -> { !port_on || live_books.().all? { from_book.(_1).any? } },
   -> { "for each workbook with no KPIs stored yet: kpi_upload.rb (KPI report #{live_books.().map { "#{_1['period']} #{_1['as_of']}" }.uniq.join(', ')}, workbook as its \"KPIs\" document; waits for the reader job)" },
   lambda {
     live_books.().all? do |b|
       next true if from_book.(b).any?

       puts "    ── #{b['name']}"
       ok = kpi_tool.("kpi_upload.rb", b, "--as-of", b["as_of"], "--period", b["period"])
       memo.clear
       ok
     end
   }],
  ["KPI recon (stored)",
   lambda {
     next true unless port_on

     live_books.().all? do |b|
       r = read_json.(recon_file.(b, "staged"))
       newest = from_book.(b).map { Time.parse(_1["created_at"]) }.max
       r["passed"] == true && newest && Time.parse(r["generated_at"]) > newest
     end
   },
   -> { "for each workbook: kpi_recon.rb ①②③ — every stored KPI = its source cell, on the dry run's period, one-to-one" },
   -> { live_books.().all? { |b| puts "    ── #{b['name']}"; kpi_tool.("kpi_recon.rb", b, "--verdict", verdict_path.(b), "--phase", "staged") } }],
  ["Approve KPIs",
   -> { !port_on || live_books.().map { _1["company"] }.uniq.all? { |co| kpis_of.(company_id.(co)).all? { _1["status"] == "approved" } } },
   -> { "PATCH /kpis/approve_all.json for #{live_books.().map { _1['company'] }.uniq.join(', ')}; wait until the computed KPIs settle" },
   lambda {
     live_books.().map { _1["company"] }.uniq.all? do |co|
       cid = company_id.(co)
       st, = api.call("patch", "/kpis/approve_all.json?portfolio_company_id=#{cid}", body: {})
       puts "    approve_all #{co}: HTTP #{st}"
       next false unless st.between?(200, 299)

       # Computed KPIs are created by a job after approval: wait until the company's KPI count settles
       n = api.wait_until_stable { api.list("/kpis.json?q[portfolio_company_id_eq]=#{cid}&all=true").size }
       puts "    #{co}: #{n} KPIs"
       true
     end
   }],
  ["KPI recon (computed)",
   lambda {
     next true unless port_on

     live_books.().all? do |b|
       r, staged = read_json.(recon_file.(b, "computed")), read_json.(recon_file.(b, "staged"))
       r["passed"] == true && staged["generated_at"] && Time.parse(r["generated_at"]) > Time.parse(staged["generated_at"])
     end
   },
   -> { "for each workbook: kpi_recon.rb --phase computed — all approved, every computed KPI = Σ its approved components" },
   -> { live_books.().all? { |b| puts "    ── #{b['name']}"; kpi_tool.("kpi_recon.rb", b, "--verdict", verdict_path.(b), "--phase", "computed") } }],
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
# The portfolio track: workspace, sandbox, fund, then the portfolio + KPI steps (and investor access, which only shows the gate)
track = portfolio_track ? [0, 1, 3] + steps.each_index.select { |i| i >= steps.index { _1.first == "Build portfolio files" } } : steps.each_index.to_a
steps.each_with_index do |(name, done, plan, _), i|
  next unless track.include?(i)

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
