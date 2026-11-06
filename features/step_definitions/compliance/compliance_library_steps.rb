# Rule library steps — openspec/changes/fund-compliance-monitoring/business-rules.md (group 1)
module ComplianceLibraryHelpers
  MEASURES = {
    "largest investment cost per investee" => { "key" => "cost_per_investee", "op" => "sum", "source" => "portfolio_investments", "field" => "cost", "group_by" => "investee" },
    "required interest" => { "key" => "required_interest", "label" => "Required interest", "op" => "expr", "expr" => ["min", ["*", 0.025, "corpus"], 50_000_000] },
    "investors not qualified purchasers" => { "key" => "not_qp", "op" => "count", "source" => "investor_kycs", "filters" => [["json_fields.qualified_purchaser", "ne", "Yes"]] },
    "misspelt commitment" => { "key" => "bad", "op" => "sum", "source" => "commitments", "field" => "commited_amount" }
  }.freeze

  def draft_definition(classifications = 5)
    cmp_described({
      "currency" => "INR", "period_basis" => "fy_apr",
      "classifications" => ["Category I", "Category II", "Category III", "Category I — LVF", "Category II — LVF"].first(classifications),
      "inputs" => [], "measures" => [{ "key" => "corpus", "label" => "Corpus", "op" => "sum", "source" => "commitments", "field" => "amount" }],
      "checks" => [{ "key" => "corpus_min", "name" => "Corpus minimum", "kind" => "limit", "applies_to" => "all", "figure" => "corpus",
                     "compare" => "gte", "limit" => { "value" => 1, "unit" => "amount" }, "citation" => "Test citation" }],
      "duties" => []
    })
  end

  def edit_draft
    defn = @draft.definition_hash
    yield defn
    @draft.definition = defn
    @draft_saved = @draft.save
  end
end
World(ComplianceLibraryHelpers)

Given('Priya is a CapHive content admin') do
  caphive = cmp_entity!("CapHive", type: "Company")
  priya = cmp_user!(caphive, "Priya")
  # :super cannot go through add_role (User#forbid_bad_role) — granted by the join row, as in support_console_steps.rb
  role = Role.find_or_create_by!(name: "super")
  ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array(["INSERT INTO users_roles (user_id, role_id) VALUES (?, ?)", priya.id, role.id]))
  cmp[:users]["Priya"] = User.find(priya.id)
end

When('Priya creates a draft CapHive pack {string} with {int} classifications') do |name, count|
  pack = CompliancePack.create!(entity_id: nil, name:, regime: "SEBI", locked: true)
  @draft = pack.versions.build(version_no: 1, definition: draft_definition(count))
  @draft_saved = @draft.save
end

When('Priya adds the measure {string} to the draft') do |name|
  edit_draft { |d| d["measures"] << ComplianceLibraryHelpers::MEASURES.fetch(name) }
end

Then('the draft saves without errors') do
  expect(@draft_saved).to be(true), @draft.errors.full_messages.to_sentence
end

Then('the draft is refused with {string}') do |message|
  expect(@draft_saved).to be false
  expect(@draft.errors.full_messages.join("\n")).to include(message)
end

Then('the measure {string} reads {string}') do |key, text|
  expect(ComplianceDescriber.measure(@draft, key)).to eq(text)
end

Then('{string} cannot see the pack {string}') do |user, name|
  expect(Pundit.policy_scope(cmp_user(user), CompliancePack).where(name:)).to be_none
end

Then('{string} can see the pack {string}') do |user, name|
  expect(Pundit.policy_scope(cmp_user(user), CompliancePack).where(name:)).to exist
end

Given('the CapHive Demo entity has a fund {string} with an investment of ₹{float} cr') do |fund_name, value|
  demo = cmp_entity!("CapHive Demo")
  fund = cmp_fund!(demo, fund_name, category: "Category II", start_date: Date.new(2025, 1, 1))
  inv = cmp_investor!(demo, "Demo LP")
  cmp_commit!(fund, inv, cr(200))
  cmp_invest!(fund, "Demo Co", cr(value))
end

When('Priya test-runs the SEBI draft on {string}') do |fund_name|
  fund = cmp_fund(fund_name)
  version = cmp[:sebi]
  allowed = CompliancePreview.allowed_fund?(cmp_user("Priya"), version, fund)
  expect(allowed).to be true
  @preview = CompliancePreview.call(version:, fund:, classification: "Category II")
end

Then('the test run shows results with figures') do
  expect(@preview.rows).not_to be_empty
  expect(@preview.rows.map(&:message).compact).not_to be_empty
end

Then('no compliance results exist for {string}') do |fund_name|
  expect(ComplianceResult.where(fund_compliance_pack_id: FundCompliancePack.where(fund_id: cmp_fund(fund_name).id).select(:id))).to be_none
end

When('Priya test-runs the draft') do
  @draft.reload.mark_tested!(cmp_user("Priya"))
end

When('Priya publishes the draft effective {string} with counsel {string} on {string}') do |effective, reviewer, on|
  @draft.reload
  @published = @draft.publish!(user: cmp_user("Priya"), attrs: { effective_from: cmp_date(effective), applicability: "all",
                                                                  counsel_reviewer: reviewer.presence, counsel_reviewed_on: on.present? ? cmp_date(on) : nil })
end

Then('publishing is refused with {string}') do |message|
  expect(@published).to be false
  expect(@draft.errors.full_messages.join("\n")).to include(message)
end

Then('the pack {string} is {string}') do |name, text|
  pack = CompliancePack.find_by!(name:)
  expect("Published #{pack.latest_published_version.label}").to eq(text)
end

Then('the pack {string} is offered in Attach pack') do |name|
  expect(CompliancePack.find_by!(name:).attachable?).to be true
end

Then('the pack {string} is not offered in Attach pack') do |name|
  expect(CompliancePack.find_by!(name:).attachable?(Time.zone.today)).to be false
end

When('{string} drafts the fund agreement pack with the single-sector limit at {int}%') do |_user, value|
  pack = cmp[:fa]
  defn = pack.latest_published_version.definition_hash
  defn["checks"].each { |c| c["limit"]["value"] = value if c["key"] == "fa_single_sector" }
  @draft = pack.versions.create!(version_no: pack.versions.maximum(:version_no) + 1, definition: defn)
end

When('{string} saves an entity pack check without a citation') do |_user|
  pack = cmp[:fa]
  defn = pack.latest_published_version.definition_hash
  defn["checks"].each { |c| c.delete("citation") }
  @draft = pack.versions.build(version_no: pack.versions.maximum(:version_no) + 1, definition: defn)
  @draft_saved = @draft.save
end

When('{string} saves an on-demand duty {string} without a due rule') do |_user, name|
  pack = cmp[:fa]
  defn = pack.latest_published_version.definition_hash
  defn["duties"] = [{ "key" => "kp", "name" => name, "trigger" => { "on_demand" => true }, "evidence" => true }]
  @draft = pack.versions.build(version_no: pack.versions.maximum(:version_no) + 1, definition: defn)
  @draft_saved = @draft.save
end

When('{string} saves an IC note check without a checks-from date') do |_user|
  pack = cmp[:fa]
  defn = pack.latest_published_version.definition_hash
  defn["checks"].each { |c| c.delete("checks_from") if c["kind"] == "record_document" }
  @draft = pack.versions.build(version_no: pack.versions.maximum(:version_no) + 1, definition: defn)
  @draft_saved = @draft.save
end

When('Priya adds an amount limit of {int} with no currency') do |value|
  edit_draft { |d| d["checks"].first["limit"] = { "value" => value, "unit" => "amount" } }
end

Then('the limit reads {string}') do |text|
  check = @draft.definition_hash["checks"].first
  expect(ComplianceFormat.limit(check["limit"]["value"], check["limit"]["unit"], @draft.currency)).to eq(text)
end

When('Priya sets a check\'s time to fix to {int}') do |days|
  edit_draft { |d| d["checks"].first["time_to_fix_days"] = days }
end

When('Priya adds a check without a citation') do
  edit_draft { |d| d["checks"].first.delete("citation") }
end

When('Priya adds a check applying to {string}') do |cls|
  edit_draft { |d| d["checks"].first["applies_to"] = [cls] }
end

When('Priya adds a quarterly duty without a due rule') do
  edit_draft { |d| d["duties"] << { "key" => "q", "name" => "Quarterly filing", "trigger" => { "schedule" => "quarterly" } } }
end

When('Priya drafts SEBI v2') do
  pack = cmp[:sebi].compliance_pack
  @draft = pack.versions.create!(version_no: 2, definition: cmp[:sebi].definition_hash)
end

Given('the SEBI pack is retired on {string}') do |date|
  cmp[:sebi].compliance_pack.update!(retired_on: cmp_date(date))
end

Given('Horizon has granted CapHive support access to Priya') do
  SupportClientMapping.insert!({ user_id: cmp_user("Priya").id, entity_id: horizon.id, enabled: true, created_at: Time.current, updated_at: Time.current })
end

# ── Versions (shared with pack_versions / changes_over_time) ────────────────────────────────
def cmp_publish_sebi_version(published_on, effective, applicability, limit: nil, transition_end: nil, early: false, corrects: nil,
                             published_at_time: "10:00", definition: nil)
  pack = cmp[:sebi].compliance_pack
  defn = cmp_described(definition || cmp[:sebi].definition_hash)
  if limit
    defn["checks"].each { |c| c["limit"]["value"] = limit if c["key"] == "sebi_concentration_cat12" }
  end
  at = ActiveSupport::TimeZone[ComplianceWorld::IST].parse("#{published_on} #{published_at_time}")
  travel_to(at) do
    v = pack.versions.create!(version_no: pack.versions.maximum(:version_no) + 1, definition: defn, corrects_version_id: corrects&.id)
    v.mark_tested!(cmp_user("Meera"))
    ok = v.publish!(user: nil, attrs: { effective_from: cmp_date(effective), applicability:, transition_ends_on: transition_end && cmp_date(transition_end),
                                        allows_early_adoption: early, counsel_reviewer: "A. Kapoor", counsel_reviewed_on: at.to_date })
    raise v.errors.full_messages.to_sentence unless ok

    CompliancePublishNotices.call(v)
    cmp[:v2] = v unless corrects
    v
  end
end

Given('SEBI v2 is published on {string} effective {string} for {string} funds') do |published, effective, applicability|
  cmp_publish_sebi_version(published, effective, applicability)
end

Given('SEBI v2 is published on {string} effective {string} for {string} funds with the concentration limit at {int}') do |published, effective, applicability, limit|
  cmp_publish_sebi_version(published, effective, applicability, limit:)
end

Given('an approved override of {string} on {string} at {int}') do |check, fund_name, value|
  fp = cmp_fund_pack(fund_name)
  submit = ComplianceRequestSubmit.call(user: cmp_user("Meera"), kind: "override", target: fp, check_key: cmp_check_key(check, fund_name),
                                        reason: "Board policy 2026-07", payload: { "limit" => value })
  expect(submit.error).to be_nil
  decision = ComplianceRequestDecide.call(request: submit.request, decider: cmp_user("Rahul"), decision: "approve")
  expect(decision.success?).to be(true), decision[:error].to_s
  @override_request = submit.request
end

Then('the next digest includes {string}') do |text|
  digest = ComplianceDigest.new(horizon, Time.zone.today + 1.day).call
  expect(digest.lines.join("\n")).to include(text)
end
