# Steps for features/compliance/ai_check_drafting.feature and the drafting rows of
# features/security/compliance_tenant_isolation.feature (E64, E65, X43).
# The AI is always stubbed at LlmService.ruby_llm_chat; every prompt it receives is captured so
# scenarios can check what was (and was not) sent.
# openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md › 8. AI drafting

# A fake RubyLLM chat: records instructions + messages, answers with the given reply or raises
class ComplianceFakeDraftChat
  attr_reader :prompts

  def initialize(reply: nil, error: nil, prompts: [])
    @reply = reply
    @error = error
    @prompts = prompts
  end

  def with_instructions(text, **)
    @prompts << text.to_s
    self
  end

  def with_schema(_schema)
    self
  end

  def ask(message, **)
    @prompts << message.to_s
    raise @error if @error

    Struct.new(:content).new(@reply)
  end
end

module ComplianceDraftingWorld
  def cmp_ai_prompts
    cmp[:ai_prompts] ||= []
  end

  def cmp_stub_ai!(reply: nil, error: nil)
    prompts = cmp_ai_prompts
    # R158: the drafter asks for a plain-words description; a canned reply without one gets a test text
    # (E199 passes its own and asserts it)
    if reply.is_a?(String) && reply.strip.start_with?("{")
      parsed = JSON.parse(reply)
      # Only check drafts (they carry "kind"); the document reader's canned replies are left as they are
      reply = parsed.merge("description" => parsed["description"].presence || "Drafted check — test description of what it checks and why.").to_json if parsed.is_a?(Hash) && parsed.key?("kind")
    end
    allow(LlmService).to receive(:ruby_llm_chat) { ComplianceFakeDraftChat.new(reply:, error:, prompts:) }
  end

  def cmp_fa_draft
    cmp[:fa_draft] || raise("No fund agreement draft — add 'Given Meera has a draft v2 of the fund agreement pack'")
  end

  def cmp_last_draft
    ComplianceCheckDraft.order(:id).last
  end

  def cmp_draft_row(id)
    find("#draft_#{id} td")
  end
end
World(ComplianceDraftingWorld)

Given('Describe in words is on for Horizon') do
  setup = cmp_setup
  setup.ai_settings = setup.ai_settings_hash.merge("drafting" => true)
  setup.save!
end

Given('Describe in words is off for Horizon') do
  setup = cmp_setup
  setup.ai_settings = setup.ai_settings_hash.merge("drafting" => false)
  setup.save!
end

Given('Meera has a draft v2 of the fund agreement pack') do
  pack = cmp[:fa]
  cmp[:fa_draft] = pack.versions.create!(version_no: 2, definition: pack.latest_published_version.definition_hash)
end

Given('the compliance AI replies with:') do |json|
  cmp_stub_ai!(reply: json)
end

Given('the compliance AI fails with {string}') do |kind|
  error = kind == "a timeout" ? Timeout::Error.new("execution expired") : StandardError.new("provider error")
  cmp_stub_ai!(error:)
end

Given('Delta Partners has an entity pack with a check {string}') do |name|
  delta = cmp_entity!("Delta Partners")
  defn = cmp_fa_definition
  defn["checks"].first["name"] = name
  cmp[:delta_pack] = cmp_entity_pack!(delta, "Delta — house limits", defn)
end

# ── Drafting through the screens (rack_test) ─────────────────────────────────────────────────
When('I open the fund agreement draft version') do
  visit compliance_pack_version_path(cmp_fa_draft)
end

When('I describe the check {string}') do |sentence|
  visit compliance_pack_version_path(cmp_fa_draft)
  within("#describeInWordsModal") do
    fill_in "compliance_check_draft[sentence]", with: sentence
    click_button "Draft check"
  end
end

When('I describe a check of exactly {int} characters') do |length|
  sentence = "No more than 15% of investable funds in any one sector — LPA clause 8.2 "
  sentence = (sentence * ((length / sentence.length) + 1)).first(length)
  expect(sentence.length).to eq(length)
  cmp[:sentence] = sentence
  # Sent as the form would send it (the textarea's maxlength stops a browser at 1,000)
  page.driver.submit :post, compliance_check_drafts_path(compliance_pack_version_id: cmp_fa_draft.id),
                     { compliance_check_draft: { sentence: } }
end

When('I test-run the draft check on {string}') do |fund_name|
  within("#draft_test") do
    select fund_name, from: "fund_id"
    click_button "Test run"
  end
end

When('I save the draft check') do
  within("#draft_save") { click_button "Save check" }
end

When('I cancel the draft check') do
  click_link "Cancel", id: "draft_cancel"
end

When('I change the draft {string} to {string}') do |label, value|
  within("#draft_edit") do
    if page.has_select?(label, wait: 0)
      select value, from: label
    else
      fill_in label, with: value
    end
    click_button "Update draft"
  end
end

When('I send a draft request for the fund agreement draft') do
  page.driver.submit :post, compliance_check_drafts_path(compliance_pack_version_id: cmp_fa_draft.id),
                     { compliance_check_draft: { sentence: "No single LP above 20% of the fund" } }
end

# ── Outcomes ─────────────────────────────────────────────────────────────────────────────────
Then('the draft {word} reads {string}') do |row, text|
  expect(cmp_draft_row(row)).to have_text(text)
end

Then('the draft shows {string}') do |text|
  expect(page).to have_text(text)
end

Then('Save check is disabled') do
  expect(page).to have_button("Save check", disabled: true)
end

Then('Save check is enabled') do
  expect(page).to have_button("Save check", disabled: false)
end

Then('the draft test run shows {string}') do |text|
  expect(find_by_id("draft_test_result")).to have_text(text)
end

Then('the draft has no test run') do
  expect(page).to have_no_css("#draft_test_result")
  expect(cmp_last_draft.reload.test_result_hash).to be_empty
end

Then('the version shows {string}') do |text|
  expect(page).to have_current_path(compliance_pack_version_path(cmp_fa_draft))
  # The version's Checks and Duties tabs load lazily into their frames (E143): read both as Turbo would
  shown = %w[checks duties].any? do |pane|
    cmp_frame_visit("version_#{pane}_pane", compliance_pack_version_path(cmp_fa_draft, pane:))
    page.has_text?(text, wait: 0)
  end
  expect(shown).to be(true), "#{text} is not on the version's Checks or Duties tab"
end

Then('the {string} tab of the fund agreement draft shows {string}') do |pane, text|
  cmp_frame_visit("version_#{pane}_pane", compliance_pack_version_path(cmp_fa_draft, pane:))
  expect(page).to have_text(text)
end

Then('the fund agreement draft has {int} checks and {int} duties') do |checks, duties|
  v = cmp_fa_draft.reload
  expect([v.checks.size, v.duties.size]).to eq([checks, duties])
end

Then('the fund agreement draft is unchanged') do
  v = cmp_fa_draft.reload
  expect(v.definition_hash).to eq(cmp[:fa].versions.find_by!(version_no: 1).definition_hash)
end

Then('the saved check {string} divides by {string} of {string}') do |name, field, source|
  defn = cmp_fa_draft.reload.definition_hash
  check = defn["checks"].detect { |c| c["name"] == name } || raise("No check #{name}")
  divisor = defn["measures"].detect { |m| m["key"] == check["figure"].last }
  expect([divisor["field"], divisor["source"]]).to eq([field, source])
end

Then('the saved duty {string} needs evidence on demand') do |name|
  duty = cmp_fa_draft.reload.duties.detect { |d| d["name"] == name && d["drafted_with_ai"] }
  expect(duty).to be_present
  expect([duty["trigger"], duty["evidence"]]).to eq([{ "on_demand" => true }, true])
end

Then('no draft check was created') do
  expect(ComplianceCheckDraft.count).to eq(0)
end

Then('a draft check was created') do
  expect(cmp_last_draft.sentence).to eq(cmp[:sentence])
end

# ── E63: runs never call AI ─────────────────────────────────────────────────────────────────
Given('the AI-drafted check {string} is saved and published in the fund agreement pack') do |name|
  draft = ComplianceCheckDraft.create!(compliance_pack_version: cmp_fa_draft, user: cmp_user("Meera"), entity_id: horizon.id,
                                       sentence: "No more than 15% of investable funds in any one sector — LPA clause 8.2")
  ComplianceCheckDrafter.call(draft:)
  expect(draft.reload.status).to eq("ready")
  draft.update!(test_result: ComplianceCheckDraftTest.call(draft:, fund: cmp_fund("Horizon Growth Fund I")))
  expect(draft.save_into_version!(cmp_user("Meera"))).to eq([])
  v = cmp_fa_draft.reload
  v.mark_tested!(cmp_user("Meera"))
  expect(v.publish!(user: cmp_user("Meera"), attrs: { effective_from: Date.new(2026, 11, 10), applicability: "all" })).to be(true)
  cmp[:ai_check_key] = v.checks.detect { |c| c["name"] == name }["key"]
end

When('the nightly compliance runs happen on {string} and {string} with the AI watched') do |d1, d2|
  cmp[:ai_calls_in_runs] = 0
  allow(LlmService).to receive(:ruby_llm_chat) do
    cmp[:ai_calls_in_runs] += 1
    raise "AI must not be called during a run"
  end
  cmp_run!("Horizon Growth Fund I", d1)
  cmp_run!("Horizon Growth Fund I", d2)
end

Then('the AI was not called and both results of the AI-drafted check are identical') do
  expect(cmp[:ai_calls_in_runs]).to eq(0)
  fps = FundCompliancePack.where(fund_id: cmp_fund("Horizon Growth Fund I").id)
  results = ComplianceResult.where(fund_compliance_pack_id: fps.select(:id), check_key: cmp[:ai_check_key]).order(:id).last(2)
  expect(results.size).to eq(2)
  expect(results.map { |r| [r.outcome, r.figure.to_s, cmp_text(r)] }.uniq.size).to eq(1)
end

# ── E64 / E65: what is sent ─────────────────────────────────────────────────────────────────
Then('the AI prompt does not mention {string}') do |text|
  expect(cmp_ai_prompts).not_to be_empty
  expect(cmp_ai_prompts.join("\n")).not_to include(text)
end

Then('the AI prompt mentions {string}') do |text|
  expect(cmp_ai_prompts.join("\n")).to include(text)
end

Then('the examples sent come only from Horizon and CapHive packs') do
  ids = Array(cmp_last_draft.sent_context["example_pack_ids"])
  expect(ids).not_to be_empty
  expect(CompliancePack.where(id: ids).where.not(entity_id: [nil, horizon.id])).to be_none
end

Then('the AI prompt carries no investor names, amounts or documents') do
  prompt = cmp_ai_prompts.join("\n")
  expect(prompt).not_to be_empty
  Investor.where(entity_id: horizon.id).pluck(:investor_name).each { |name| expect(prompt).not_to include(name) }
  Document.where(entity_id: horizon.id).pluck(:name).each { |name| expect(prompt).not_to include(name) }
  CapitalCommitment.where(entity_id: horizon.id).distinct.pluck(:committed_amount_cents).each do |cents|
    [cents.to_i.to_s, (cents / 100).to_i.to_s].each { |amount| expect(prompt).not_to include(amount) }
  end
end
