# Changes-over-time steps — business-rules.md (group 11)

Given('the dated IC members list') do
  setup = cmp_setup
  setup.set_reference_list("ic_members", quorum: 3, entries: [
    { "name" => "A. Rao" }, { "name" => "K. Shah" }, { "name" => "M. Iyer" },
    { "name" => "R. Mehta", "valid_from" => "2025-04-01", "valid_to" => "2026-10-15" },
    { "name" => "S. Nair", "valid_from" => "2026-10-05" }
  ])
  setup.save!
end

Then('on {string} the IC members among {string} are {int} against quorum {int}') do |date, names, count, quorum|
  setup = cmp_setup
  members = setup.reference_list("ic_members", on: cmp_date(date))
  signed = names.split(",").map(&:strip)
  expect((signed & members).size).to eq(count)
  expect(setup.quorum).to eq(quorum)
end

When('{string} requests to classify {string} as {string} under SEBI') do |user, fund_name, classification|
  @submit = ComplianceRequestSubmit.call(user: cmp_user(user), kind: "classification", target: cmp_fund_pack(fund_name),
                                         reason: "Fund became a Large Value Fund", payload: { "classification" => classification })
  expect(@submit.error).to be_nil
end

Then('the classification change is {string}') do |status|
  expect(@submit.request.reload.status).to eq(status)
end

When('{string} remaps the sponsor\/manager input to {string} on {string}') do |user, category, date|
  travel_to(ActiveSupport::TimeZone[ComplianceWorld::IST].parse("#{date} 12:00")) do
    params = ActionController::Parameters.new(mappings: { "sponsor" => category }).permit!
    expect(ComplianceSetupUpdate.call(setup: cmp_setup, params:, user: cmp_user(user)).error).to be_nil
  end
end

Then('the setup history records the sponsor\/manager mapping change') do
  audits = cmp_setup.audits.select { |a| a.audited_changes.key?("input_mappings") }
  expect(audits.map { |a| a.audited_changes["input_mappings"].to_s }.join).to include("Promoter")
end

Given('SEBI v2 with a wrong investor limit of {int} is published on {string} effective {string}') do |limit, published, effective|
  defn = cmp[:sebi].definition_hash
  defn["checks"].each { |c| c["limit"]["value"] = limit if c["key"] == "sebi_investor_count" }
  cmp_publish_sebi_version(published, effective, "all", definition: defn)
end

Given('SEBI v2.1 correcting the investor limit to {int} is published on {string} effective {string}') do |limit, published, effective|
  defn = cmp[:v2].definition_hash
  defn["checks"].each { |c| c["limit"]["value"] = limit if c["key"] == "sebi_investor_count" }
  @correction = cmp_publish_sebi_version(published, effective, "all", definition: defn, corrects: cmp[:v2])
end

Then('the v2 results of {string} are marked {string}') do |fund_name, _label|
  results = ComplianceResult.where(fund_compliance_pack_id: cmp_fund_pack(fund_name).id, compliance_pack_version_id: cmp[:v2].id)
  expect(results).to exist
  expect(results.all?(&:superseded?)).to be true
end

Then('the v2 results of {string} are still stored and marked {string}') do |fund_name, label|
  step %(the v2 results of "#{fund_name}" are marked "#{label}")
  expect(@correction.label).to eq("v2.1")
end

Then('the override request is {string}') do |status|
  expect(ComplianceRequest.order(:id).last.status).to eq(status)
end

When('{string} saves the IC member {string} from {string} to {string}') do |user, name, from, to|
  params = ActionController::Parameters.new(reference_lists: { "ic_members" => { "entries" => [{ "name" => name, "valid_from" => from, "valid_to" => to }] } }).permit!
  @setup_result = ComplianceSetupUpdate.call(setup: cmp_setup, params:, user: cmp_user(user))
end

Then('the IC member {string} is stored from {string} to {string}') do |name, from, to|
  entry = Array(cmp_setup.reload.reference_lists_hash.dig("ic_members", "entries")).detect { |e| e["name"] == name }
  expect([entry["valid_from"], entry["valid_to"]]).to eq([from, to])
end

Then('on the {string} basis {string} is in quarter {string} ending {string}') do |basis, date, key, ending|
  expect(CompliancePeriod.quarter(cmp_date(date), basis)).to eq([key, cmp_date(ending)])
end

Then('on the {string} basis {string} is in year {string} ending {string}') do |basis, date, key, ending|
  expect(CompliancePeriod.year(cmp_date(date), basis)).to eq([key, cmp_date(ending)])
end

Given('{int} investors committing on {string} and {int} on {string} are imported into {string}') do |a, d1, b, d2, fund_name|
  fund = cmp_fund(fund_name)
  first = a.positive? ? cmp_investors_bulk!(horizon, "Import A", a) : []
  second = cmp_investors_bulk!(horizon, "Import B", b)
  cmp_commit_bulk!(fund, first.map { |i| [i.id, cr(1), cmp_date(d1)] } + second.map { |i| [i.id, cr(1), cmp_date(d2)] })
end

Then('the digest lines include {string}') do |text|
  digest = cmp_digests(cmp_user("Meera")).last
  expect(Array(digest&.params&.dig(:lines)).join("\n")).to include(text)
end

Given('Solo Capital with one user {string} and a SEBI fund {string}') do |name, fund_name|
  solo = cmp_entity!("Solo Capital")
  cmp_user!(solo, name, admin: true)
  fund = cmp_fund!(solo, fund_name, category: "Category II", start_date: Date.new(2025, 1, 1))
  sp = cmp_investor!(solo, "Solo Sponsor", category: "Sponsor")
  lp = cmp_investor!(solo, "Solo LP", category: "LP")
  cmp_commit!(fund, sp, cr(5))
  cmp_commit!(fund, lp, cr(95))
  cmp_invest!(fund, "Solo Investee", cr(40))
  cmp_attach!(fund, cmp[:sebi].compliance_pack, "Category II")
  setup = ComplianceEntitySetup.for(solo)
  setup.set_mapping("sponsor", { "categories" => ["Sponsor"] })
  setup.set_fund_figure("est_expenses", fund, cr(5))
  setup.save!
end

When('{string} explains and self-approves the {string} item on {string}') do |user, check, fund_name|
  item = cmp_item(check, fund_name)
  submit = ComplianceRequestSubmit.call(user: cmp_user(user), kind: "explanation", target: item, reason: "Single approver explains", payload: {})
  expect(submit.error).to be_nil
  decision = ComplianceRequestDecide.call(request: submit.request, decider: cmp_user(user), decision: "approve")
  expect(decision.success?).to be(true), decision[:error].to_s
end

When('{string} is deactivated') do |name|
  cmp_user(name).update_columns(active: false)
end

When('the morning reassignment happens on {string} and {string}') do |d1, d2|
  [d1, d2].each do |d|
    travel_to(ActiveSupport::TimeZone[ComplianceWorld::IST].parse("#{d} 08:05")) do
      ComplianceMaintenance.reassign_deactivated(cmp_setup.reload)
      @notes_seen = (@notes_seen || []) + Array(cmp_setup.reload.digest_notes)
      cmp_setup.update!(digest_notes: [])
    end
  end
end

Then('the digest notes mention {string} once') do |text|
  notes = (@notes_seen || []) + Array(cmp_setup.reload.digest_notes)
  expect(notes.count { |n| n.include?(text) }).to eq(1), notes.inspect
end

Then('the digest notes do not mention {string}') do |text|
  expect(Array(cmp_setup.reload.digest_notes).join("\n")).not_to include(text)
end

Then('both items are assigned to {string}') do |name|
  expect(ComplianceRegisterItem.open_items.where(entity_id: horizon.id, assignee_id: cmp_user(name).id).count).to be >= 2
end

Given('SEBI v2 is published at {string} effective {string} for {string} funds') do |at, effective, applicability|
  date, time = at.split(" ")
  cmp_publish_sebi_version(date, effective, applicability, published_at_time: time)
end

Then('{string} has no compliance run on {string}') do |fund_name, date|
  expect(ComplianceRun.where(fund_id: cmp_fund(fund_name).id, run_date: cmp_date(date))).to be_none
end

When('the nightly compliance run happens at {string} Eastern time') do |at|
  date, time = at.split(" ")
  cmp_run!("Horizon Growth Fund I", date, time:, zone: "Eastern Time (US & Canada)")
  @result = cmp_latest("Horizon Growth Fund I", "sebi_concentration_cat12")
end

Given('{string} carries SEBI as {string} attached on {string}') do |fund_name, classification, date|
  FundCompliancePack.create!(entity_id: horizon.id, fund: cmp_fund(fund_name), compliance_pack: cmp[:sebi].compliance_pack,
                             classification:, attached_on: cmp_date(date))
  setup = cmp_setup
  setup.set_fund_figure("est_expenses", cmp_fund(fund_name), cr(1))
  setup.save!
end

Then('{string} has quarterly SEBI duties only for {string}') do |fund_name, period|
  fp = cmp_fund_pack(fund_name)
  expect(ComplianceDuty.where(fund_compliance_pack_id: fp.id, duty_key: "sebi_quarterly_report").pluck(:period_key)).to eq([period])
end

Then('the due-diligence duty for {string} is owned by {string}') do |investor, owner|
  inv = Investor.find_by!(entity_id: horizon.id, investor_name: investor)
  expect(ComplianceDuty.find_by!(subject_type: "Investor", subject_id: inv.id).owner).to eq(cmp_user(owner))
end

Given("the sponsor's commitment is deleted") do
  CapitalCommitment.where(investor_id: cmp[:sponsor].id).update_all(deleted_at: Time.current)
end

Given('the commitment of {string} is deleted') do |investor|
  inv = Investor.find_by!(entity_id: horizon.id, investor_name: investor)
  CapitalCommitment.where(investor_id: inv.id).update_all(deleted_at: Time.current)
end

When('the {string} investment is deleted') do |company|
  cmp[:investments].fetch(company).update_columns(deleted_at: Time.current)
end

When('the IC note of {string} is moved to {string}') do |from, to|
  Document.where(owner_type: "PortfolioInvestment", owner_id: cmp[:investments].fetch(from).id)
          .update_all(owner_id: cmp[:investments].fetch(to).id)
end

Then('the run history of {string} shows a gap on {string}') do |fund_name, date|
  expect(ComplianceDashboard.new(cmp_fund(fund_name), cmp_user("Meera")).run_gaps).to include(cmp_date(date))
end

Given('monitoring is on for Horizon') do
  cmp_setup.update!(monitoring_enabled: true)
end

Then('a compliance run reads one snapshot per fund') do
  expect(ComplianceRunOperation.snapshot_isolation("Mysql2")).to eq(:repeatable_read)
  expect(ComplianceRunOperation.snapshot_isolation("Trilogy")).to eq(:repeatable_read)
end

When('Priya adds a new-investor duty without a from date') do
  edit_draft { |d| d["duties"] << { "key" => "dd", "name" => "DD", "trigger" => { "event" => "new_investor" }, "due" => { "days_after" => "event", "n" => 15 } } }
end
