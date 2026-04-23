# frozen_string_literal: true

# Step definitions for the LP Assistant tool scenarios.
#
# These steps exercise the four tools exposed to the LP Assistant LLM —
# ListSkillsTool, LoadSkillTool, RunQueryTool, DocumentUrlTool — by
# instantiating them directly with trusted scope ids. This matches the
# Cucumber style used for CashFlowAssistantAgent: behaviour-level
# assertions on security guards and scope substitution, without
# spinning up the full chat provider / LLM round-trip.
#
# Shared instance variables set here:
#   @lp_entity_ids          — Array<Integer> of FM entity_ids
#   @lp_fund_ids            — Array<Integer> of fund ids the LP can see
#   @lp_investor_ids        — Array<Integer> of investors.id rows for the LP org
#   @run_query_response     — String returned by RunQueryTool#execute
#   @skills_response        — String returned by ListSkillsTool#execute
#   @skill_response         — String returned by LoadSkillTool#execute
#   @document               — Document under test
#   @document_response      — String returned by DocumentUrlTool#execute

# ─── LP Scope Setup ────────────────────────────────────────────────────────

Given('an LP scope is set up with entity {string} and fund {string}') do |_entity_name, _fund_name|
  @lp_entity_ids   = [@fund.entity_id]
  @lp_fund_ids     = [@fund.id]
  @lp_investor_ids = [@fund.id + 10_000] # placeholder investor id — real row not needed for query tests
end

Given('the LP scope is cleared of all accessible funds') do
  @lp_fund_ids = []
end

# ─── RunQueryTool ──────────────────────────────────────────────────────────

When('the LP runs the query {string}') do |sql|
  tool = RunQueryTool.new(
    entity_ids:              @lp_entity_ids,
    accessible_fund_ids:     @lp_fund_ids,
    accessible_investor_ids: @lp_investor_ids
  )
  @run_query_response = tool.execute(sql: sql)
  puts "\n####RunQueryTool response####\n#{@run_query_response}\n"
end

Then('the query response should include {string}') do |text|
  expect(@run_query_response).to include(text)
end

Then("the query response should list the LP's fund id") do
  expect(@run_query_response).to include(@fund.id.to_s)
end

# ─── ListSkillsTool ────────────────────────────────────────────────────────

When('the LP calls list_skills') do
  @skills_response = ListSkillsTool.new.execute
  puts "\n####ListSkillsTool response####\n#{@skills_response}\n"
end

Then('the skills response should list {string}') do |skill_name|
  expect(@skills_response).to include(skill_name)
end

# ─── LoadSkillTool ─────────────────────────────────────────────────────────

When('the LP loads the skill {string}') do |skill_name|
  @skill_response = LoadSkillTool.new.execute(skill_name: skill_name)
  puts "\n####LoadSkillTool response####\n#{@skill_response.to_s.lines.first(3).join}\n"
end

Then('the skill response should include {string}') do |text|
  expect(@skill_response).to include(text)
end

# ─── DocumentUrlTool ───────────────────────────────────────────────────────

Given("a fund document {string} is attached to the LP's fund") do |doc_name|
  @document = build_fund_document(name: doc_name, fund: @fund)
end

Given('a fund document {string} is attached to a fund outside the LP\'s scope') do |doc_name|
  other_entity = FactoryBot.create(:entity, name: "Other FM", entity_type: "Investment Fund")
  other_fund   = FactoryBot.create(:fund, entity: other_entity, name: "Other Fund")
  @document    = build_fund_document(name: doc_name, fund: other_fund, entity: other_entity)
end

Given("a document with unsupported owner_type is created under the LP's entity") do
  folder = FactoryBot.create(:folder, owner: @fund, entity: @fund.entity)
  @document = FactoryBot.create(:document,
    name:   "Random Note",
    entity: @fund.entity,
    folder: folder,
    user:   @user
  )
  @document.update_columns(owner_type: "Note", owner_id: @fund.id)
end

When('the LP requests the URL for that document') do
  tool = DocumentUrlTool.new(
    entity_ids:              @lp_entity_ids,
    accessible_fund_ids:     @lp_fund_ids,
    accessible_investor_ids: @lp_investor_ids
  )
  # Stub out Shrine/S3 URL generation — we only assert scope, not signed URL mechanics
  allow_any_instance_of(Document).to receive_message_chain(:file, :blank?).and_return(false)
  allow_any_instance_of(Document).to receive_message_chain(:file, :url).and_return("https://s3.example.test/doc.pdf")
  allow_any_instance_of(Document).to receive(:name_with_extension).and_return("doc.pdf")

  @document_response = tool.execute(document_id: @document.id)
  puts "\n####DocumentUrlTool response####\n#{@document_response}\n"
end

Then('the document response should include {string}') do |text|
  expect(@document_response).to include(text)
end

Then('the document response should not include {string}') do |text|
  expect(@document_response).not_to include(text)
end

# ─── Helpers ───────────────────────────────────────────────────────────────

def build_fund_document(name:, fund:, entity: nil)
  ent = entity || fund.entity
  folder = FactoryBot.create(:folder, owner: fund, entity: ent)
  doc = FactoryBot.create(:document,
    name:   name,
    entity: ent,
    folder: folder,
    user:   @user
  )
  doc.update_columns(owner_type: "Fund", owner_id: fund.id)
  doc
end
