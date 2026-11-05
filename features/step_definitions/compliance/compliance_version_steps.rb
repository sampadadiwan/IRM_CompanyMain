# Pack versions and locking steps — business-rules.md (group 10)

Given('SEBI funds {string} started {string}, {string} started {string} and {string} with no start date') do |n1, d1, n0, d0, u|
  [[n1, cmp_date(d1)], [n0, cmp_date(d0)], [u, nil]].each do |name, start|
    fund = cmp_fund!(horizon, name, category: "Category II", start_date: start)
    inv = cmp_investor!(horizon, "#{name} LP", category: "LP")
    cmp_commit!(fund, inv, cr(100))
    cmp_attach!(fund, cmp[:sebi].compliance_pack, "Category II")
    setup = cmp_setup
    setup.set_fund_figure("est_expenses", fund, cr(5))
    setup.save!
  end
end

When('the nightly compliance runs happen on {string} for {string}') do |date, funds|
  funds.split(",").map(&:strip).each { |f| cmp_run!(f, date) }
end

Then('{string} are on SEBI {string}') do |funds, label|
  funds.split(",").map(&:strip).each do |f|
    expect(cmp_fund_pack(f).reload.compliance_pack_version.label).to eq(label), "#{f} is on #{cmp_fund_pack(f).compliance_pack_version.label}"
  end
end

Given('SEBI v2 allowing early adoption is published on {string} effective {string} for {string} funds') do |published, effective, applicability|
  cmp_publish_sebi_version(published, effective, applicability, early: true)
end

Given('SEBI v2 replacing the yearly duty with {string} is published on {string} effective {string} for {string} funds') do |duty, published, effective, applicability|
  defn = cmp[:sebi].definition_hash
  defn["duties"].reject! { |d| d["key"] == "sebi_ctr_ppm_audit" }
  defn["duties"] << { "key" => "new_v2_duty", "name" => duty, "trigger" => { "schedule" => "yearly" }, "due" => { "days_after" => "period_end", "n" => 30 }, "applies_to" => "all" }
  cmp_publish_sebi_version(published, effective, applicability, definition: defn)
end

# A new check every SEBI test fund fails: at most 1 investor
def cmp_v2_with_new_check
  defn = cmp[:sebi].definition_hash
  defn["checks"] << { "key" => "sebi_new_v2_cap", "name" => "New v2 investor cap", "kind" => "limit", "applies_to" => "all", "figure" => "investor_count",
                      "compare" => "lte", "limit" => { "value" => 0, "unit" => "count" }, "tested" => "continuous", "override" => "none",
                      "time_to_fix_days" => 30, "severity" => "breach", "citation" => "Test amendment" }
  defn
end

Given('SEBI v2 with a new failing check is published on {string} effective {string} with a transition until {string}') do |published, effective, until_date|
  cmp_publish_sebi_version(published, effective, "transition", transition_end: until_date, definition: cmp_v2_with_new_check)
end

Given('SEBI v2 without the concentration check is published on {string} effective {string} for {string} funds') do |published, effective, applicability|
  defn = cmp[:sebi].definition_hash
  defn["checks"].reject! { |c| c["key"] == "sebi_concentration_cat12" }
  cmp_publish_sebi_version(published, effective, applicability, definition: defn)
end

Then('{string} has a {string} duty') do |fund_name, name|
  expect(cmp_duty(name, fund_name)).to be_present
end

Then('{string} has no {string} duty') do |fund_name, name|
  expect(cmp_duty(name, fund_name)).to be_nil
end

Then('{string} has no register item for {string}') do |fund_name, check|
  expect(ComplianceRegisterItem.where(fund_id: cmp_fund(fund_name).id, check_key: cmp_check_key(check, fund_name))).to be_none
end

Then('every SEBI check of {string} says {string}') do |fund_name, text|
  fp = cmp_fund_pack(fund_name)
  results = ComplianceResult.where(fund_compliance_pack_id: fp.id)
  expect(results).to exist
  results.each do |r|
    expect(r.outcome).to eq("could_not_check")
    expect(cmp_text(r)).to include(text)
  end
end

When('the morning version reminders run on {string}, {string} and {string}') do |*dates|
  dates.each do |d|
    travel_to(ActiveSupport::TimeZone[ComplianceWorld::IST].parse("#{d} 08:05")) { ComplianceMaintenance.version_reminders(horizon, cmp_date(d)) }
  end
end

When('{string} previews SEBI v2 on {string}') do |_user, fund_name|
  @before_counts = [ComplianceResult.count, ComplianceRegisterItem.count, Array(cmp_setup.reload.digest_notes).size]
  @preview = CompliancePreview.call(version: cmp[:v2], fund: cmp_fund(fund_name), classification: cmp_fund_pack(fund_name).classification)
end

Then('the preview shows {string} as {string}') do |check, outcome|
  row = @preview.rows.detect { |r| r.name == check }
  expect(row&.outcome).to eq(outcome)
end

Then('the compliance preview says {string}') do |text|
  expect(@preview.not_applicable ? "This version will not apply to this fund" : "").to eq(text)
end

Then('nothing was logged by the preview') do
  expect([ComplianceResult.count, ComplianceRegisterItem.count, Array(cmp_setup.reload.digest_notes).size]).to eq(@before_counts)
end

When('{string} requests early adoption of SEBI v2 for {string} on {string}') do |user, fund_name, date|
  travel_to(ActiveSupport::TimeZone[ComplianceWorld::IST].parse("#{date} 12:00")) do
    @submit = ComplianceRequestSubmit.call(user: cmp_user(user), kind: "early_adoption", target: cmp_fund_pack(fund_name),
                                           reason: "Ready for the amendment early", payload: { "version_id" => cmp[:v2].id })
  end
end

When('{string} requests to move {string} back to SEBI v1') do |user, fund_name|
  @submit = ComplianceRequestSubmit.call(user: cmp_user(user), kind: "early_adoption", target: cmp_fund_pack(fund_name),
                                         reason: "Go back to the old rules", payload: { "version_id" => cmp[:sebi].id })
end

def cmp_publish_fa_v2(published_on, applies_from = nil, applicability: "all")
  pack = cmp[:fa]
  travel_to(ActiveSupport::TimeZone[ComplianceWorld::IST].parse("#{published_on} 10:00")) do
    @fa_v2 = pack.versions.create!(version_no: pack.versions.maximum(:version_no) + 1, definition: pack.latest_published_version.definition_hash)
    @fa_v2.mark_tested!(cmp_user("Meera"))
    @fa_published = @fa_v2.publish!(user: cmp_user("Meera"), attrs: { effective_from: cmp_date(applies_from || published_on), applicability: })
  end
end

Given('the fund agreement v2 is published on {string}') do |date|
  cmp_publish_fa_v2(date)
  expect(@fa_published).to be true
end

Given('the fund agreement v2 is published on {string} applying from {string}') do |date, from|
  cmp_publish_fa_v2(date, from)
  expect(@fa_published).to be true
end

When('{string} publishes the fund agreement v2 for {string} funds') do |_user, applicability|
  cmp_publish_fa_v2("2026-11-10", applicability:)
end

Then('the entity publish is refused with {string}') do |message|
  expect(@fa_published).to be false
  expect(@fa_v2.errors.full_messages.join("\n")).to include(message)
end

When('{string} maps the sponsor\/manager input to {string} and saves the IC members {string} with quorum {int}') do |user, category, names, quorum|
  params = ActionController::Parameters.new(mappings: { "sponsor" => category },
                                            reference_lists: { "ic_members" => { "quorum" => quorum.to_s, "entries" => names.split(",").map { |n| { "name" => n.strip } } } }).permit!
  @setup_result = ComplianceSetupUpdate.call(setup: cmp_setup, params:, user: cmp_user(user))
end

Then('the override is {string}') do |status|
  expect(@override_request.reload.status).to eq(status)
  @result = cmp_latest("Horizon Growth Fund I", @override_request.check_key)
end

Then('{string} has no SEBI results on {string}') do |fund_name, date|
  fp = cmp_fund_pack(fund_name)
  expect(ComplianceResult.joins(:compliance_run).where(fund_compliance_pack_id: fp.id, compliance_runs: { run_date: cmp_date(date) })).to be_none
end

Then('{string} has SEBI results on {string}') do |fund_name, date|
  fp = cmp_fund_pack(fund_name)
  expect(ComplianceResult.joins(:compliance_run).where(fund_compliance_pack_id: fp.id, compliance_runs: { run_date: cmp_date(date) })).to exist
end

Then('no version switch was recorded for {string} on {string}') do |_fund_name, _date|
  expect(Array(cmp_setup.reload.digest_notes).grep(/applied/)).to be_empty
  expect(Noticed::Event.where(type: "ComplianceNotifier").select { |e| e.params[:message].to_s.include?("switched") }).to be_empty
end

Then('the SEBI check {string} is not overridable') do |check|
  check_def = cmp[:sebi].checks.detect { |c| c["name"] == check }
  expect(check_def["override"]).to eq("none")
  submit = ComplianceRequestSubmit.call(user: cmp_user("Meera"), kind: "override", target: cmp_fund_pack("Horizon Growth Fund I"),
                                        check_key: check_def["key"], reason: "Board policy 2026-07", payload: { "limit" => 900 })
  expect(submit.error).to include("This check cannot be overridden")
end

Then('{string} cannot edit the SEBI pack') do |user|
  expect(Pundit.policy(cmp_user(user), cmp[:sebi].compliance_pack).update?).to be false
  expect(Pundit.policy(cmp_user(user), cmp[:sebi]).update?).to be false
end

def cmp_sebi_draft
  pack = cmp[:sebi].compliance_pack
  @draft = pack.versions.create!(version_no: pack.versions.maximum(:version_no) + 1, definition: cmp[:sebi].definition_hash)
  @draft.mark_tested!(nil)
  @draft
end

When('Priya publishes a SEBI draft with no applicability') do
  cmp_sebi_draft
  @published = @draft.publish!(user: nil, attrs: { effective_from: Date.new(2027, 1, 1), applicability: "", counsel_reviewer: "A. Kapoor", counsel_reviewed_on: Date.new(2026, 11, 20) })
end

When('Priya publishes a SEBI draft effective {string} with a transition until {string}') do |effective, until_date|
  cmp_sebi_draft
  @published = @draft.publish!(user: nil, attrs: { effective_from: cmp_date(effective), applicability: "transition", transition_ends_on: cmp_date(until_date),
                                                    counsel_reviewer: "A. Kapoor", counsel_reviewed_on: Date.new(2026, 11, 20) })
end

Then('the version publish is refused with {string}') do |message|
  expect(@published).to be false
  expect(@draft.errors.full_messages.join("\n")).to include(message)
end
