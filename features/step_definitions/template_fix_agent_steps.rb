# Steps for features/ai/support_agents/template_fix_agent.feature
# The LLM is always stubbed at the service layer (LlmService.ruby_llm_chat) —
# see features/step_definitions/side_letter_obligation_steps.rb for why not
# allow_any_instance_of(RubyLLM::Chat).

Given('the entity has an LLM provider configured') do
  @entity.entity_setting.update!(gemini_api_key: "test-gemini-key")
end

Given('the template fix admin is a company admin') do
  @user.add_role(:company_admin)
end

Given('a fund exists for the template fix entity') do
  @fund = FactoryBot.create(:fund, entity: @entity)
end

Given('the fund has a commitment template document {string}') do |fixture_name|
  # name is derived from the fixture so distinct scenarios (or a scenario that layers a
  # second template document on top of the Background's) don't collide under Document's
  # name+owner_tag+owner uniqueness validation (see document.rb) for two different files.
  @template_document = FactoryBot.create(
    :document,
    entity: @entity,
    owner: @fund,
    folder: @fund.document_folder,
    user: @user,
    owner_tag: "Commitment Template",
    name: File.basename(fixture_name, ".*"),
    file: Rails.public_path.join("sample_uploads", fixture_name).open
  )
  expect(@template_document.template?).to be(true)
end

Given('the Fix Me AI reports back {string}') do |summary|
  fake_chat = double("chat", with_instructions: nil, with_tools: nil)
  allow(fake_chat).to receive(:ask).and_return(OpenStruct.new(content: summary))
  allow(LlmService).to receive(:ruby_llm_chat).and_return(fake_chat)
end

When('I open the fix me modal and describe the issue {string}') do |issue|
  visit document_path(@template_document)
  click_button "Fix Me"
  within("#fixMeModal") do
    fill_in "issue_description", with: issue
    click_button "Run Fix Me"
  end
end

When('I visit the template document page') do
  visit document_path(@template_document)
end

Then('a template fix agent report should exist with status {string}') do |status|
  agent = SupportAgent.find_by!(entity_id: @entity.id, agent_type: "TemplateFixAgent")
  @fix_report = SupportAgentReport.find_by!(owner: @template_document, support_agent: agent)
  expect(@fix_report.final_status).to eq(status)
end

Then('a new draft document should exist, distinct from the template') do
  draft = Document.find_by(id: @fix_report.json_fields["result_document_id"])
  expect(draft).to be_present
  expect(draft.id).not_to eq(@template_document.id)
  # template/orignal are forced true on every draft (DocxWorkspace#save_as_new_document!)
  # so it's immediately usable as a template — but owner_tag stays nil, so it never
  # auto-appears in owner_tag-filtered template lists (e.g. CapitalCommitmentDocJob's
  # default scan) until a human reviews it and promotes it themselves.
  expect(draft.template?).to be(true)
  expect(draft.orignal?).to be(true)
  expect(draft.owner_tag).to be_nil
  expect(draft.from_template_id).to eq(@template_document.id)
end

Then('the fix should report a passing content check') do
  content_check = @fix_report.json_fields["content_check"]
  expect(content_check).to be_present
  expect(content_check["passed"]).to be(true)
  expect(content_check.dig("paragraph_count", "original")).to eq(content_check.dig("paragraph_count", "fixed"))
  expect(content_check.dig("word_count", "original")).to eq(content_check.dig("word_count", "fixed"))
  expect(content_check["word_for_word_match"]).to be(true)
end
