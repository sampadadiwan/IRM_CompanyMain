# Steps for features/compliance/*.feature — openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md
# Most steps drive the services directly (runs, register, duties); screen and direct-request steps
# use rack_test in compliance_ui_steps.rb.

# ── Setup ───────────────────────────────────────────────────────────────────────────────────
Given('the Horizon compliance setup') do
  cmp_build_horizon!
end

Given('the compliance date is {string}') do |date|
  travel_to(ActiveSupport::TimeZone[ComplianceWorld::IST].parse("#{date} 10:00"))
end

Given('{string} also carries the fund agreement pack') do |fund_name|
  cmp_attach!(cmp_fund(fund_name), cmp[:fa], "All funds")
end

Given('the estimated expenses of {string} are ₹{float} cr') do |fund_name, value|
  setup = cmp_setup
  setup.set_fund_figure("est_expenses", cmp_fund(fund_name), cr(value))
  setup.save!
end

Given('the estimated expenses of {string} are blank') do |fund_name|
  setup = cmp_setup
  setup.set_fund_figure("est_expenses", cmp_fund(fund_name), nil)
  setup.save!
end

Given('{string} costs ₹{float} cr') do |company, value|
  cmp[:investments].fetch(company).update_columns(amount_cents: cr(value) * 100)
end

Given('{string} has an investment in {string} of ₹{float} cr on {string}') do |fund_name, company, value, date|
  cmp_invest!(cmp_fund(fund_name), company, cr(value), cmp_date(date))
end

Given('{string} sells part of {string} on {string}') do |fund_name, company, date|
  fund = cmp_fund(fund_name)
  investee = cmp_investor!(fund.entity, company, category: "Portfolio Company")
  now = Time.current
  PortfolioInvestment.insert!({ entity_id: fund.entity_id, fund_id: fund.id, portfolio_company_id: investee.id, portfolio_company_name: company,
                                investment_date: cmp_date(date), amount_cents: -cr(1) * 100, quantity: -10, sector: "Food",
                                aggregate_portfolio_investment_id: 0, ref_id: 0, excused_folio_ids: [], proforma: false,
                                unrealized_price_effect_cents: 0, realized_price_effect_cents: 0, created_at: now, updated_at: now })
end

# Investable funds = corpus − estimated expenses: set expenses so investable is the given figure
Given('the investable funds of {string} are ₹{float} cr') do |fund_name, value|
  fund = cmp_fund(fund_name)
  corpus = CapitalCommitment.where(fund_id: fund.id).sum(:committed_amount_cents) / 100
  setup = cmp_setup
  setup.set_fund_figure("est_expenses", fund, corpus - cr(value))
  setup.save!
end

Given('the sponsor\/manager input is unmapped') do
  setup = cmp_setup
  setup.set_mapping("sponsor", { "categories" => [] })
  setup.save!
end

Given('the sponsor pays a further ₹{float} cr on {string}') do |value, date|
  cmp_pay!(cmp_fund("Horizon Growth Fund I"), cmp[:sponsor], cr(value), cmp_date(date))
end

Given('a payment of ₹{float} cr dated {string} is recorded on {string}') do |value, date, recorded_on|
  travel_to(ActiveSupport::TimeZone[ComplianceWorld::IST].parse("#{recorded_on} 12:00")) do
    cmp_pay!(cmp_fund("Horizon Growth Fund I"), cmp[:sponsor], cr(value), cmp_date(date))
  end
end

Given('{string} is a fund with no investments, category {string}') do |name, category|
  fund = cmp_fund!(horizon, name, category:, start_date: Date.new(2025, 1, 1))
  inv = cmp_investor!(horizon, "#{name} LP", category: "LP")
  cmp_commit!(fund, inv, cr(100))
  cmp_attach!(fund, cmp[:sebi].compliance_pack, category)
  setup = cmp_setup
  setup.set_fund_figure("est_expenses", fund, cr(10))
  setup.save!
end

# A wound-up fund is soft-deleted; its history stays readable (E19)
Given('{string} is wound up') do |fund_name|
  cmp_fund(fund_name).update_column(:deleted_at, Time.current)
end

# ── Runs ────────────────────────────────────────────────────────────────────────────────────
When('the nightly compliance run happens on {string}') do |date|
  cmp_run!("Horizon Growth Fund I", date)
end

When('the nightly compliance run happens on {string} for {string}') do |date, fund_name|
  cmp_run!(fund_name, date)
end

When('Run now is pressed twice on {string} for {string}') do |date, fund_name|
  fund = cmp_fund(fund_name)
  at = ActiveSupport::TimeZone[ComplianceWorld::IST].parse("#{date} 11:00")
  travel_to(at) do
    # The first press is still running when the second arrives (E18)
    ComplianceRun.create!(entity_id: fund.entity_id, fund:, run_date: at.to_date, trigger: "run_now", status: "running")
    ComplianceRunOperation.call_safely(fund_id: fund.id, run_date: at.to_date, trigger: "run_now", run_at: at)
  end
end

Then('{string} has {int} compliance run(s) on {string}') do |fund_name, count, date|
  expect(ComplianceRun.where(fund_id: Fund.with_deleted.find_by!(name: fund_name).id, run_date: cmp_date(date)).count).to eq(count)
end

Then('the {string} check on {string} is {string}') do |check, fund_name, outcome|
  @result = cmp_latest(fund_name, cmp_check_key(check, fund_name))
  expect(@result).to be_present
  expect(@result.outcome).to eq(outcome), cmp_text(@result)
end

Then('the {string} check of the {string} pack on {string} is {string}') do |check, pack, fund_name, outcome|
  @result = cmp_latest(fund_name, cmp_check_key(check, fund_name), pack)
  expect(@result.outcome).to eq(outcome), cmp_text(@result)
end

Then('the working shows {string}') do |text|
  expect(cmp_text(@result)).to include(text)
end

Then('the working does not show {string}') do |text|
  expect(cmp_text(@result)).not_to include(text)
end

Then('the result records version {string}') do |label|
  expect(@result.working_hash["version"]).to eq(label)
end

Then('the {string} result of {string} on {string} is still {string} with {string}') do |check, fund_name, date, outcome, text|
  fp_ids = FundCompliancePack.where(fund_id: cmp_fund(fund_name).id).select(:id)
  result = ComplianceResult.joins(:compliance_run).where(fund_compliance_pack_id: fp_ids, check_key: cmp_check_key(check, fund_name),
                                                         compliance_runs: { run_date: cmp_date(date) }).order(:id).last
  expect(result.outcome).to eq(outcome)
  expect(cmp_text(result)).to include(text)
end

Then('{string} has no {string} results') do |fund_name, pack_name|
  fp = cmp_fund_pack(fund_name, pack_name)
  expect(ComplianceResult.where(fund_compliance_pack_id: fp.id)).to be_none
end

Then('the dashboard of {string} says {string}') do |fund_name, text|
  dashboard = ComplianceDashboard.new(cmp_fund(fund_name), cmp_user("Meera"))
  messages = dashboard.unclassified.map { |fp| "#{fp.pack_name}: no classification — no checks run" }
  messages << (dashboard.stale? ? "may be out of date" : "current")
  expect(messages.join("\n")).to include(text)
end

Given('the last successful run of {string} finished {int} hours and {int} minutes ago') do |fund_name, h, m|
  fund = cmp_fund(fund_name)
  ComplianceRun.where(fund_id: fund.id).delete_all
  ComplianceRun.create!(entity_id: fund.entity_id, fund:, run_date: Time.zone.today, trigger: "nightly", status: "succeeded",
                        finished_at: Time.current - h.hours - m.minutes)
end

Then('the results of {string} are {word}') do |fund_name, state|
  expect(ComplianceRun.stale?(cmp_fund(fund_name))).to eq(state == "stale")
end

# ── Documents ───────────────────────────────────────────────────────────────────────────────
Given('{string} invested in {string} on {string} with an IC note e-signed on {string}') do |fund_name, company, date, signed|
  pi = cmp_invest!(cmp_fund(fund_name), company, cr(5), cmp_date(date))
  cmp_doc!(pi, esign_completed_on: cmp_date(signed))
end

Given('{string} invested in {string} on {string} with a wet-ink IC note signed on {string} and uploaded on {string}') do |fund_name, company, date, signed, uploaded|
  pi = cmp_invest!(cmp_fund(fund_name), company, cr(5), cmp_date(date))
  cmp_doc!(pi, signed_on: cmp_date(signed), uploaded_on: cmp_date(uploaded))
end

Given('{string} invested in {string} on {string} with an IC note scan not marked signed') do |fund_name, company, date|
  pi = cmp_invest!(cmp_fund(fund_name), company, cr(5), cmp_date(date))
  cmp_doc!(pi)
end

Given('{string} invested in {string} on {string} with no IC note') do |fund_name, company, date|
  cmp_invest!(cmp_fund(fund_name), company, cr(5), cmp_date(date))
end

Given('{string} has {int} investments with signed IC notes from {string}') do |fund_name, count, date|
  count.times do |i|
    pi = cmp_invest!(cmp_fund(fund_name), "Signed Co #{i + 1}", cr(1), cmp_date(date) + i.days)
    cmp_doc!(pi, esign_completed_on: cmp_date(date) + i.days)
  end
end

Given('{string} has {int} investments before {string} with no IC note') do |fund_name, count, date|
  count.times { |i| cmp_invest!(cmp_fund(fund_name), "Old Co #{i + 1}", cr(1), cmp_date(date) - (i + 1).days) }
end

Given('a newer IC note for {string} is uploaded and e-signed on {string}') do |company, date|
  cmp_doc!(cmp[:investments].fetch(company), esign_completed_on: cmp_date(date))
end

def cmp_ic_result
  @result = cmp_latest(@ic_fund || "Horizon Growth Fund I", "fa_ic_note")
end

Then('the IC note list shows {string}') do |text|
  cmp_ic_result if @result.nil? || @result.check_key != "fa_ic_note"
  expect(cmp_text(@result)).to include(text)
end

Then('the IC note list includes {string} as {string}') do |company, problem|
  cmp_ic_result
  rows = Array(@result.working_hash["failing_records"])
  row = rows.detect { |r| r["label"] == company }
  expect(row).to be_present, cmp_text(@result)
  expect(row["problem"]).to include(problem)
end

Then('the IC note list does not include {string}') do |company|
  cmp_ic_result
  expect(Array(@result.working_hash["failing_records"]).pluck("label")).not_to include(company)
end

# ── SEBI pack variants ──────────────────────────────────────────────────────────────────────
Given('{string} is classified {string} under SEBI') do |fund_name, classification|
  fp = FundCompliancePack.joins(:compliance_pack).find_by(fund_id: cmp_fund(fund_name).id, compliance_packs: { name: "SEBI — AIF" })
  fp ? fp.update!(classification:) : cmp_attach!(cmp_fund(fund_name), cmp[:sebi].compliance_pack, classification)
end

Given('{string} has a corpus of ₹{float} cr with a sponsor commitment of ₹{float} cr') do |fund_name, corpus, sponsor|
  fund = cmp_fund!(horizon, fund_name, category: "Category II", start_date: Date.new(2025, 1, 1))
  sp = cmp_investor!(horizon, "#{fund_name} Sponsor", category: "Sponsor")
  other = cmp_investor!(horizon, "#{fund_name} LP", category: "LP")
  cmp_commit!(fund, sp, cr(sponsor))
  cmp_commit!(fund, other, cr(corpus) - cr(sponsor))
  cmp_attach!(fund, cmp[:sebi].compliance_pack, "Category II")
  setup = cmp_setup
  setup.set_fund_figure("est_expenses", fund, cr(1))
  setup.save!
end

Given('{string} has investors committing {string}') do |fund_name, amounts|
  fund = cmp_fund(fund_name)
  amounts.split(",").each_with_index do |amt, i|
    inv = cmp_investor!(horizon, "Small LP #{i + 1}", category: "LP")
    cmp_commit!(fund, inv, amt.delete("₹, ").to_i)
  end
end

Given('employees and directors are mapped to the category {string}') do |category|
  setup = cmp_setup
  setup.set_mapping("employees", { "categories" => [category] })
  setup.save!
end

Given('{string} has an employee committing ₹{int}') do |fund_name, amount|
  cmp[:emp_seq] = (cmp[:emp_seq] || 0) + 1
  inv = cmp_investor!(horizon, "Employee #{cmp[:emp_seq]}", category: "Directors/ Partners/ Employees of Sponsor")
  cmp_commit!(cmp_fund(fund_name), inv, amount)
end

Given('{string} has exactly {int} investors') do |fund_name, count|
  fund = cmp_fund!(horizon, fund_name, category: "Category II", start_date: Date.new(2025, 1, 1))
  investors = cmp_investors_bulk!(horizon, "#{fund_name} LP", count)
  cmp_commit_bulk!(fund, investors.map { |inv| [inv.id, cr("1.5"), Date.new(2025, 6, 1)] })
  cmp_attach!(fund, cmp[:sebi].compliance_pack, "Category II")
  setup = cmp_setup
  setup.set_fund_figure("est_expenses", fund, cr(1))
  setup.set_mapping("sponsor", { "categories" => ["Sponsor"] })
  setup.save!
end

Given('{string} also has {int} investors with zero commitments and {int} fully transferred out') do |fund_name, zero, transferred|
  fund = cmp_fund(fund_name)
  investors = cmp_investors_bulk!(horizon, "#{fund_name} Zero", zero + transferred)
  cmp_commit_bulk!(fund, investors.map { |inv| [inv.id, 0, Date.new(2025, 6, 1)] })
end

Then('the investor count working shows {string}') do |text|
  expect(cmp_text(@result)).to include(text)
end

Given('a {string} fund {string} with no NAV') do |category, name|
  fund = cmp_fund!(horizon, name, category:, start_date: Date.new(2025, 1, 1))
  inv = cmp_investor!(horizon, "#{name} LP", category: "LP")
  cmp_commit!(fund, inv, cr(50))
  cmp_attach!(fund, cmp[:sebi].compliance_pack, category)
end

Then('the SEBI pack offers the classifications {string}') do |list|
  expect(cmp[:sebi].classifications).to eq(list.split(";").map(&:strip))
end

# ── Record-time check (E21) ─────────────────────────────────────────────────────────────────
Given('the fund agreement concentration check is tested when a record is made') do
  v = cmp[:fa].latest_published_version
  defn = v.definition_hash
  defn["checks"].each { |c| (c["tested"] = "on_record") && (c["record_source"] = "portfolio_investments") if c["key"] == "fa_concentration" }
  v.update_column(:definition, defn)
end

Then('the fund agreement concentration has {int} record results') do |count|
  fp = cmp_fund_pack("Horizon Growth Fund I", "Horizon — fund agreement limits")
  expect(ComplianceResult.where(fund_compliance_pack_id: fp.id, check_key: "fa_concentration").where.not(subject_id: nil).count).to eq(count)
end

Then('no fund agreement concentration result is a breach after {string}') do |date|
  fp = cmp_fund_pack("Horizon Growth Fund I", "Horizon — fund agreement limits")
  rows = ComplianceResult.joins(:compliance_run).where(fund_compliance_pack_id: fp.id, check_key: "fa_concentration")
                         .where(compliance_runs: { run_date: cmp_date(date).. })
  expect(rows.where(outcome: "breach")).to be_none
end

Then('{string} has {int} open register item(s)') do |fund_name, count|
  expect(ComplianceRegisterItem.open_items.where(fund_id: cmp_fund(fund_name).id).count).to eq(count)
end

Given("Horizon's compliance time zone is {string}") do |zone|
  cmp_setup.update!(time_zone: zone)
end

When('the hourly compliance tick happens at {string} {string}') do |time, zone|
  at = ActiveSupport::TimeZone[zone].parse(time)
  travel_to(at) { ComplianceScheduleJob.perform_now(now: at) }
end

Then('marking a document signed on {string} is refused with {string}') do |date, message|
  fund = cmp_fund("Horizon Growth Fund I")
  doc = cmp_doc!(cmp_invest!(fund, "Future Co", cr(1), Date.new(2026, 10, 1)))
  signoff = DocumentSignoff.new(entity_id: fund.entity_id, document: doc, signed_on: cmp_date(date), marked_by: cmp_user("Meera"))
  expect(signoff.save).to be false
  expect(signoff.errors.full_messages).to include(message)
end

When('the nightly compliance run on {string} fails') do |date|
  allow(ComplianceVersionMover).to receive(:call).and_raise(ActiveRecord::StatementInvalid, "database unavailable")
  cmp_run!("Horizon Growth Fund I", date)
  RSpec::Mocks.space.proxy_for(ComplianceVersionMover).reset
end

Then('the latest run of {string} is {string}') do |fund_name, status|
  expect(ComplianceRun.where(fund_id: cmp_fund(fund_name).id).order(:id).last.status).to eq(status)
end

Then('{string} got the compliance notice {string}') do |name, text|
  user = cmp_user(name)
  messages = Noticed::Event.where(type: "ComplianceNotifier").joins(:notifications)
                           .where(noticed_notifications: { recipient_type: "User", recipient_id: user.id }).map { |e| e.params[:message].to_s }
  expect(messages.join("\n")).to include(text)
end

Then('{string} did not get the compliance notice {string}') do |name, text|
  user = cmp_user(name)
  messages = Noticed::Event.where(type: "ComplianceNotifier").joins(:notifications)
                           .where(noticed_notifications: { recipient_type: "User", recipient_id: user.id }).map { |e| e.params[:message].to_s }
  expect(messages.join("\n")).not_to include(text)
end

Given('{int} hours pass after the last successful run') do |hours|
  last = ComplianceRun.last_success_for(cmp_fund("Horizon Growth Fund I"))
  travel_to(last.finished_at + hours.hours + 1.minute)
end

# ── Register ────────────────────────────────────────────────────────────────────────────────
def cmp_item(check, fund_name = "Horizon Growth Fund I")
  ComplianceRegisterItem.where(fund_id: cmp_fund(fund_name).id, check_key: cmp_check_key(check, fund_name)).order(:id).last
end

Then('the {string} item on {string} is {string}') do |check, fund_name, status|
  item = cmp_item(check, fund_name)
  expect(item).to be_present
  expect(item.status).to eq(status)
end

Then('the {string} item on {string} is closed as {string}') do |check, fund_name, label|
  item = cmp_item(check, fund_name)
  expect(item.closed?).to be true
  expect(item.closed_label).to eq(label)
end

Then('the item keeps its failing working {string} and its clearing working {string}') do |failing, clearing|
  ComplianceRegisterItem.order(:id).last
  item = ComplianceRegisterItem.where.not(closed_on: nil).order(:id).last
  expect(cmp_text(item.first_result)).to include(failing)
  expect(cmp_text(item.last_result)).to include(clearing)
end

When('{string} assigns the {string} item to {string}') do |_by, check, to|
  item = cmp_item(check)
  item.update!(assignee: cmp_user(to), status: "in_progress")
  ComplianceNotices.assignment(item, cmp_user(to))
end

When('{string} explains the {string} item with {string}') do |by, check, text|
  @submit = ComplianceRequestSubmit.call(user: cmp_user(by), kind: "explanation", target: cmp_item(check), reason: text, payload: { "text" => text })
  expect(@submit.error).to be_nil
end

When('{string} approves the explanation of the {string} item') do |by, check|
  req = ComplianceRequest.where(target_type: "ComplianceRegisterItem", target_id: cmp_item(check).id, kind: "explanation").order(:id).last
  @decision = ComplianceRequestDecide.call(request: req, decider: cmp_user(by), decision: "approve")
  expect(@decision.success?).to be(true), @decision[:error].to_s
end

When('{string} rejects the explanation of the {string} item') do |by, check|
  req = ComplianceRequest.where(target_type: "ComplianceRegisterItem", target_id: cmp_item(check).id, kind: "explanation").order(:id).last
  @decision = ComplianceRequestDecide.call(request: req, decider: cmp_user(by), decision: "reject")
  expect(@decision.success?).to be true
end

When('{string} approves the explanation request again') do |by|
  req = ComplianceRequest.where(kind: "explanation").order(:id).last
  @decision = ComplianceRequestDecide.call(request: req, decider: cmp_user(by), decision: "approve")
end

Then('the request decision fails with {string}') do |error|
  expect(@decision.success?).to be false
  expect(@decision[:error]).to eq(error)
end

Then('{string} got the compliance notice {string} exactly once') do |name, text|
  user = cmp_user(name)
  messages = Noticed::Event.where(type: "ComplianceNotifier").joins(:notifications)
                           .where(noticed_notifications: { recipient_type: "User", recipient_id: user.id }).map { |e| e.params[:message].to_s }
  expect(messages.count { |m| m.include?(text) }).to eq(1)
end

Given('the {string} item was explained and approved after the {string} run') do |check, date|
  cmp_run!("Horizon Growth Fund I", date)
  item = cmp_item(check)
  submit = ComplianceRequestSubmit.call(user: cmp_user("Meera"), kind: "explanation", target: item, reason: "Exit of Acme agreed for Q4", payload: {})
  expect(submit.error).to be_nil
  ComplianceRequestDecide.call(request: submit.request, decider: cmp_user("Rahul"), decision: "approve")
  expect(item.reload.status).to eq("explained")
end

Then('the item is marked {string}') do |_label|
  expect(ComplianceRegisterItem.order(:id).last.reopened_worse || cmp_item("Single-investee concentration").reopened_worse).to be true
end

Then('{string} has {int} register item(s) for {string} opened on {string}') do |fund_name, count, check, date|
  items = ComplianceRegisterItem.where(fund_id: cmp_fund(fund_name).id, check_key: cmp_check_key(check, fund_name))
  expect(items.count).to eq(count)
  expect(items.first.opened_on).to eq(cmp_date(date))
end

Then('{string} has {int} register items for {string}') do |fund_name, count, check|
  expect(ComplianceRegisterItem.where(fund_id: cmp_fund(fund_name).id, check_key: cmp_check_key(check, fund_name)).count).to eq(count)
end

Then('the newest {string} item was opened on {string}') do |check, date|
  expect(cmp_item(check).opened_on).to eq(cmp_date(date))
end

Then('the {string} item has fix-by {string}') do |check, date|
  @item = cmp_item(check)
  expect(@item.fix_by).to eq(cmp_date(date))
end

Then('on {string} the item is not overdue') do |date|
  expect((@item || ComplianceRegisterItem.order(:id).last).overdue?(cmp_date(date))).to be false
end

Then('on {string} the item is overdue') do |date|
  item = @item || cmp_item("Single-investee concentration")
  expect(item.reload.overdue?(cmp_date(date))).to be true
end

When('the morning compliance housekeeping happens on {string}') do |date|
  travel_to(ActiveSupport::TimeZone[ComplianceWorld::IST].parse("#{date} 08:05")) do
    ComplianceMaintenance.escalate_overdue(horizon, cmp_date(date))
  end
end

Given('the {string} check has {int} days to fix') do |check, days|
  v = cmp[:sebi]
  defn = v.definition_hash
  key = cmp_check_key(check)
  defn["checks"].each { |c| c["time_to_fix_days"] = days if c["key"] == key }
  v.update_column(:definition, defn)
end

Then('explaining the closed {string} item is refused with {string}') do |check, message|
  result = ComplianceRequestSubmit.call(user: cmp_user("Meera"), kind: "explanation", target: cmp_item(check), reason: "Explaining a closed item", payload: {})
  expect(result.error).to include(message)
end

# ── Duties ──────────────────────────────────────────────────────────────────────────────────
def cmp_duty(name, fund_name = "Horizon Growth Fund I", period: nil)
  fp_ids = FundCompliancePack.where(fund_id: cmp_fund(fund_name).id).select(:id)
  duties = ComplianceDuty.where(fund_compliance_pack_id: fp_ids).select { |d| d.name == name }
  duties = duties.select { |d| d.period_key == period } if period
  duties.max_by(&:id)
end

def cmp_evidence_file
  Rack::Test::UploadedFile.new(Rails.public_path.join('img/whatsappQR.png'), "image/png")
end

Then('{string} has a {string} duty for {string} due {string}') do |fund_name, name, period, due|
  duty = cmp_duty(name, fund_name, period:)
  expect(duty).to be_present
  expect(duty.due_on).to eq(cmp_date(due))
end

When('{string} marks the {string} duty of {string} done with evidence on {string}') do |by, name, fund_name, date|
  travel_to(ActiveSupport::TimeZone[ComplianceWorld::IST].parse("#{date} 12:00")) do
    result = ComplianceDutyComplete.call(duty: cmp_duty(name, fund_name), user: cmp_user(by), note: "Filed", evidence: cmp_evidence_file)
    expect(result.error).to be_nil
  end
end

Then('the {string} duty for {string} is done with an evidence document') do |name, period|
  duty = cmp_duty(name, period:)
  expect(duty.done?).to be true
  expect(Document.where(owner: duty)).to exist
end

Then('marking the {string} duty of {string} done without evidence is refused with {string}') do |name, fund_name, message|
  result = ComplianceDutyComplete.call(duty: cmp_duty(name, fund_name), user: cmp_user("Meera"), note: "Done")
  expect(result.error).to eq(message)
end

Given('a new investor {string} commits ₹{float} cr to {string} on {string}') do |name, value, fund_name, date|
  inv = cmp_investor!(horizon, name, category: "LP")
  cmp_commit!(cmp_fund(fund_name), inv, cr(value), cmp_date(date))
end

Then('{string} has a due-diligence duty for {string} due {string}') do |fund_name, investor, due|
  inv = Investor.find_by!(entity_id: horizon.id, investor_name: investor)
  fp_ids = FundCompliancePack.where(fund_id: cmp_fund(fund_name).id).select(:id)
  duty = ComplianceDuty.find_by(fund_compliance_pack_id: fp_ids, subject_type: "Investor", subject_id: inv.id)
  expect(duty).to be_present
  expect(duty.due_on).to eq(cmp_date(due))
end

Then('{string} has {int} due-diligence duties') do |fund_name, count|
  fp_ids = FundCompliancePack.where(fund_id: cmp_fund(fund_name).id).select(:id)
  expect(ComplianceDuty.where(fund_compliance_pack_id: fp_ids, subject_type: "Investor").count).to eq(count)
end

Given('a duty of {string} is due on {string}') do |fund_name, date|
  fp = cmp_fund_pack(fund_name)
  @duty = ComplianceDuty.create!(entity_id: fp.entity_id, fund_compliance_pack: fp, duty_key: "sebi_quarterly_report",
                                 period_key: "TEST", due_on: cmp_date(date), owner: cmp_user("Meera"))
end

Then('on {string} the duty is {string}') do |date, state|
  expect(@duty.reload.state(cmp_date(date))).to eq(state)
end

When('{string} marks that duty done with evidence on {string}') do |by, date|
  travel_to(ActiveSupport::TimeZone[ComplianceWorld::IST].parse("#{date} 12:00")) do
    expect(ComplianceDutyComplete.call(duty: @duty, user: cmp_user(by), note: "Late", evidence: cmp_evidence_file).error).to be_nil
  end
end

Then('that duty is done {string}') do |text|
  expect("late (#{@duty.reload.late_days} days)").to eq(text)
end

Then('{string} has open register items for {string} and {string}') do |fund_name, a, b|
  keys = ComplianceRegisterItem.open_items.where(fund_id: cmp_fund(fund_name).id).pluck(:check_key)
  expect(keys).to include(cmp_check_key(a, fund_name), cmp_check_key(b, fund_name))
end
