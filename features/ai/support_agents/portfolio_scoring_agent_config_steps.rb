# Step definitions for the Portfolio Scoring Agent configuration health check.
# Covers the show-page warning banner, inline failed-report errors, and the
# setup service's skill-field meta_data backfill.

# Template attrs for the two skill fields the scoring agent ships with.
# Mirrors SupportAgentsSetupService::SUPPORT_AGENT_FORM_CONFIGS so drift in the
# template is caught by the assertions below.
def scoring_skill_field_templates
  SupportAgentsSetupService.skill_field_templates("PortfolioScoringAgent")
end

# Creates a PortfolioScoringAgent whose FormType is auto-provisioned by
# SupportAgent#setup_form_type, then adds its two skill File fields with the
# given meta_data (nil simulates the drift seen on old instances).
def create_scoring_agent_with_skill_fields(entity, meta_data:)
  @support_agent = SupportAgent.create!(
    entity:     entity,
    name:       "Scoring Agent",
    agent_type: "PortfolioScoringAgent",
    enabled:    true,
    category:   "Portfolio"
  )

  scoring_skill_field_templates.each do |tpl|
    @support_agent.form_type.form_custom_fields.create!(
      name:       tpl[:name],
      label:      tpl[:label],
      field_type: "File",
      position:   tpl[:position],
      meta_data:  meta_data == :template ? tpl[:meta_data] : meta_data
    )
  end
  @support_agent
end

# Uploads a tiny markdown skill file named after the field label — the exact
# name skill_for_sector looks up via documents.find_by(name: fcf.human_label).
def upload_skill_document(support_agent, fcf)
  # .txt (not .md) — markdown is not in the allowed upload extensions in test
  Tempfile.create(["skill", ".txt"]) do |f|
    f.write("# Skill\nScore on growth, margins, retention.")
    f.flush

    doc = Document.new(
      owner:      support_agent,
      name:       fcf.human_label,
      entity_id:  support_agent.entity_id,
      user_id:    @user&.id,
      send_email: false,
      folder:     support_agent.document_folder
    )
    doc.file = File.open(f.path)
    doc.save!
  end
end

Given("there is a portfolio scoring agent with skill fields having blank meta data") do
  create_scoring_agent_with_skill_fields(@entity, meta_data: nil)
end

Given("there is a portfolio scoring agent with tagged skill fields but no uploaded files") do
  create_scoring_agent_with_skill_fields(@entity, meta_data: :template)
end

Given("there is a fully configured portfolio scoring agent") do
  create_scoring_agent_with_skill_fields(@entity, meta_data: :template)
  @support_agent.form_custom_fields.where(field_type: "File").each do |fcf|
    upload_skill_document(@support_agent, fcf)
  end
end

# Adds an ordinary (non-skill) File field — used to prove other agents and
# unrelated File fields are never flagged or modified.
Given("the agent has a File custom field with blank meta data") do
  @plain_file_field = @support_agent.form_type.form_custom_fields.create!(
    name:       "some_upload",
    label:      "Some Upload",
    field_type: "File",
    position:   99,
    meta_data:  nil
  )
end

Given("there is a failed scoring report with error {string}") do |error|
  # @investor is set by "there is an existing portfolio company" — reports require an owner
  FactoryBot.create(:support_agent_report, :failed,
    support_agent: @support_agent,
    owner:         @investor,
    json_fields:   { "error" => error, "final_status" => "failed" })
end

When("I visit the support agent page") do
  visit support_agent_path(@support_agent)
end

When("I visit the support agent page scoring reports tab") do
  visit support_agent_path(@support_agent, tab: "scoring_reports")
end

# Re-runs only the custom-field upsert against the live FormType — the exact
# code path a full SupportAgentsSetupService.call takes for existing fields.
When("the support agent custom fields are re-synced from the template") do
  cfg = SupportAgentsSetupService::SUPPORT_AGENT_FORM_CONFIGS.find { |c| c[:tag] == "PortfolioScoringAgent" }
  service = SupportAgentsSetupService.new(@entity.id, output: Logger.new(IO::NULL))
  service.send(:upsert_custom_fields, @support_agent.form_type, cfg[:fields])
end

Then("I should see the configuration warning banner") do
  expect(page).to have_content("This agent is not fully configured")
end

Then("I should not see the configuration warning banner") do
  expect(page).not_to have_content("This agent is not fully configured")
end

Then("I should see a configuration issue {string}") do |fragment|
  expect(page).to have_content(fragment)
end

Then("I should see {string} in the reports table") do |text|
  expect(page).to have_content(text)
end

Then("the skill fields should have their template meta data") do
  scoring_skill_field_templates.each do |tpl|
    fcf = @support_agent.form_type.form_custom_fields.find_by(name: tpl[:name])
    expect(fcf.meta_data).to eq(tpl[:meta_data]),
      "expected '#{tpl[:name]}' meta_data to be backfilled to '#{tpl[:meta_data]}', got '#{fcf.meta_data}'"
  end
end

Then("the non-skill File field should still have blank meta data") do
  expect(@plain_file_field.reload.meta_data).to be_blank
end
