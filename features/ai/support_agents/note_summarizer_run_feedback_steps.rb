# Steps for features/ai/support_agents/note_summarizer_run_feedback.feature
# (openspec/changes/fix-portfolio-dashboard-widgets-2/design.md#worked-examples)
# "today is {string}" comes from features/step_definitions/evergreen_order_steps.rb

Given('the note summariser is enabled for the entity with summary period {string}') do |period|
  @entity.support_agents.set!(:note_summarization_agent)
  @note_summariser = FactoryBot.create(:support_agent, entity: @entity, agent_type: "NoteSummarizerAgent", name: "Note Summariser",
                                                       enabled: true, json_fields: { "summary_period" => period, "auto_tag_notes" => "No" })
  # No real model call: a period without notes skips the LLM, and the steps below set a reply where one is needed
  allow(LlmService).to receive(:ruby_llm_chat).and_return(double("chat", ask: double("reply", content: "")))
end

Given("the note summariser's summary period is {string}") do |period|
  @note_summariser.update!(json_fields: @note_summariser.json_fields.merge("summary_period" => period))
end

Given('the note summariser is disabled for the entity') do
  @entity.support_agents.unset!(:note_summarization_agent)
end

Given('the company {string} has notes dated {string}') do |name, dates|
  company = Investor.find_by!(entity_id: @entity.id, investor_name: name)
  dates.split(",").map(&:strip).each_with_index do |date, index|
    Note.create!(owner: company, entity: @entity, user: @user, on: Date.strptime(date, "%d/%m/%Y"),
                 details: "Update #{index + 1} on #{date}")
  end
end

Given("the summariser's LLM replies {string}") do |text|
  allow(LlmService).to receive(:ruby_llm_chat).and_return(double("chat", ask: double("reply", content: text)))
end

Given("the summariser's LLM fails") do
  chat = double("chat")
  allow(chat).to receive(:ask).and_raise(StandardError, "model unavailable")
  allow(LlmService).to receive(:ruby_llm_chat).and_return(chat)
end

When('I open the notes of {string}') do |name|
  company = Investor.find_by!(entity_id: @entity.id, investor_name: name)
  visit(notes_path(owner_id: company.id, owner_type: "Investor"))
end

Then('the run window should say {string}') do |text|
  # The window is a closed modal until the button is clicked, so read its text whether shown or not
  expect(find("#run-note-summarizer-agent-modal", visible: :all)).to have_text(:all, text)
end

When('I run the note summariser from the notes list') do
  click_on("Summarise Notes")
  within("#run-note-summarizer-agent-modal") { click_on("Run Summariser") }
end

Then('I should see the page message {string}') do |text|
  expect(find("#user_alert")).to have_content(text)
end

Then('the Summarise Notes button should be locked') do
  expect(page).to have_css("button[style*='pointer-events:none'] .ti-lock")
end

# The same request the run window's form sends; jobs run inline in tests
When('the note summariser runs for {string}') do |name|
  company = Investor.find_by!(entity_id: @entity.id, investor_name: name)
  page.driver.submit(:post, run_support_agents_path, { agent_type: "NoteSummarizerAgent", target_type: "Investor", target_id: company.id })
end

When('I open the Note Summaries of {string}') do |name|
  company = Investor.find_by!(entity_id: @entity.id, investor_name: name)
  visit(note_summaries_support_agents_path(entity_id: @entity.id, owner_id: company.id))
end

def note_summary_entry
  find("[id^='note-summary-detail-']", match: :first, visible: :all)
end

Then('the Note Summaries entry should show {string}') do |text|
  expect(note_summary_entry).to have_content(text)
end

Then('the Note Summaries entry should not show {string}') do |text|
  expect(note_summary_entry).to have_no_content(text)
end

Then('the Note Summaries entry should show notes processed {string}') do |count|
  label = note_summary_entry.find("small", text: "Notes processed:")
  expect(label.find(:xpath, "..").find("strong").text.strip).to eq(count)
end

Then('the Note Summaries entry should show a summary box') do
  expect(note_summary_entry).to have_css(".card-title", text: "Summary")
end

Then('the Note Summaries entry should not show a summary box') do
  expect(note_summary_entry).to have_no_css(".card-title", text: "Summary")
end

Then('the notes should include a {string} note dated {string} reading {string}') do |tag, date, text|
  row = find("#notes tr", text: date, match: :first)
  expect(row).to have_content(tag)
  expect(row).to have_content(text)
end
