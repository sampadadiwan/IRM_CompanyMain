# frozen_string_literal: true

# Step definitions for Deal Update Agent v2 processing scenarios.
# Tests the DealIngestProcessor pipeline — LLM parsing, stakeholder
# matching, Note/Task creation, and warehouse flow.
# Key v2 change: warehoused emails do NOT send a notification.

# --- LLM Stubbing ---

Given("the v2 LLM will parse the email as a meeting note for {string}") do |stakeholder|
  @llm_parse_result = {
    "intent" => "meeting_note",
    "stakeholder_string" => stakeholder,
    "body" => "Great call with #{stakeholder} today, positive signals on 5M commitment",
    "due_date" => nil,
    "due_date_source_text" => nil
  }
end

Given("the v2 LLM will parse the email as a task for {string} due {string}") do |stakeholder, due_date|
  @llm_parse_result = {
    "intent" => "task",
    "stakeholder_string" => stakeholder,
    "body" => "Send term sheet to #{stakeholder}",
    "due_date" => due_date,
    "due_date_source_text" => "by next Friday"
  }
end

Given("the v2 LLM will parse the email with intent {string}") do |intent|
  @llm_parse_result = {
    "intent" => intent,
    "stakeholder_string" => nil,
    "body" => "Random gibberish content",
    "due_date" => nil,
    "due_date_source_text" => nil
  }
end

# --- Job Execution ---

When("the v2 job is performed") do
  @ingested_email ||= AgentIngestedEmail.last
  expect(@ingested_email).not_to be_nil, "No AgentIngestedEmail found to process"

  # Execute the processor directly. Temporarily switch to inline
  # so deliver_later actually delivers (for confirmation email assertions).
  ActiveJob::Base.queue_adapter = :inline
  Chewy.strategy(:bypass) do
    DealIngestProcessor.call(@ingested_email.id)
  end
  ActiveJob::Base.queue_adapter = :test
  @ingested_email.reload
end

# --- Assertions: Note Creation ---

Then("a v2 Note should exist on {string} with text {string}") do |investor_name, text_fragment|
  investor = Investor.find_by!(investor_name: investor_name)
  deal_investor = DealInvestor.find_by!(deal: @deal, investor: investor)

  @created_note = Note.find_by(owner: deal_investor)
  expect(@created_note).not_to be_nil,
                               "Expected a Note on #{investor_name} but none found"
  expect(@created_note.details.to_plain_text).to include(text_fragment)
end

Then("the v2 Note should be flagged as created_by_agent with match_tier {string}") do |tier|
  @ingested_email.reload
  expect(@ingested_email.filed_as).to eq(@created_note)
  expect(@ingested_email.match_tier).to eq(tier)
end

# --- Assertions: Task Creation ---

Then("a v2 Task should exist on {string} with due date {string}") do |investor_name, due_date|
  investor = Investor.find_by!(investor_name: investor_name)
  deal_investor = DealInvestor.find_by!(deal: @deal, investor: investor)

  @created_task = Task.find_by(owner: deal_investor)
  expect(@created_task).not_to be_nil,
                               "Expected a Task on #{investor_name} but none found"
  expect(@created_task.due_date).to eq(Date.parse(due_date))
end

Then("the v2 Task should be flagged as created_by_agent with match_tier {string}") do |tier|
  @ingested_email.reload
  expect(@ingested_email.filed_as).to eq(@created_task)
  expect(@ingested_email.match_tier).to eq(tier)
end

# --- Assertions: Email Status ---

Then("the v2 AgentIngestedEmail status should be {string}") do |status|
  @ingested_email.reload
  expect(@ingested_email.status).to eq(status),
                                    "Expected email status '#{status}' but got '#{@ingested_email.status}'"
end

# --- Assertions: Mailers ---

Then("a v2 confirmation email should be sent to the user") do
  confirmation = ActionMailer::Base.deliveries.find do |mail|
    mail.to.include?(@user.email) && mail.subject&.include?("created on")
  end
  expect(confirmation).not_to be_nil,
                              "Expected a confirmation email to #{@user.email} but none found. Deliveries: #{ActionMailer::Base.deliveries.map(&:subject)}"
end

# --- Assertions: Warehouse ---

Then("a v2 WarehouseItem should exist for the deal with intent {string}") do |intent|
  @warehouse_item = WarehouseItem.find_by(deal: @deal)
  expect(@warehouse_item).not_to be_nil,
                                 "Expected a WarehouseItem for the deal but none found"
  expect(@warehouse_item.parsed_intent).to eq(intent)
  expect(@warehouse_item).to be_pending
end

# Asserts the cleaned body text that was passed to the LLM parser
# after EmailBodyCleaner stripped signatures and quoted replies.
#
# @param expected_body [String] the expected cleaned body text
Then("the v2 LLM should have received body {string}") do |expected_body|
  expect(DealEmailParser).to have_received(:call).with(
    hash_including(email_body: expected_body.strip)
  )
end

# Asserts that a Task has the expected number of attached Documents
# with a specific filename.
#
# @param count [Integer] expected document count
# @param filename [String] expected document name
Then("the v2 Task should have {int} attached document named {string}") do |count, filename|
  expect(@created_task.documents.count).to eq(count),
                                           "Expected #{count} document(s) but found #{@created_task.documents.count}"
  expect(@created_task.documents.first.name).to eq(filename)
end

# Asserts that a Task has exactly N attached Documents (any name).
#
# @param count [Integer] expected document count
Then("the v2 Task should have {int} attached documents") do |count|
  expect(@created_task.documents.count).to eq(count),
                                           "Expected #{count} document(s) but found #{@created_task.documents.count}"
end

# Asserts no Documents were created during processing.
Then("no v2 Document should be created") do
  expect(Document.count).to eq(0),
                            "Expected no Documents but found #{Document.count}"
end

# Stub the LLM to return a task parse result with an assignee.
#
# @param stakeholder [String] stakeholder name
# @param due_date [String] ISO 8601 due date
# @param assignee [String] assignee name extracted by LLM
Given("the v2 LLM will parse the email as a task for {string} due {string} assigned to {string}") do |stakeholder, due_date, assignee|
  @llm_parse_result = {
    "intent" => "task",
    "stakeholder_string" => stakeholder,
    "body" => "Send term sheet to #{stakeholder}",
    "due_date" => due_date,
    "due_date_source_text" => "by next Friday",
    "assignee_string" => assignee
  }
end

# Asserts the Task is assigned to a specific named user.
#
# @param user_key [String] the user key from @users hash
Then("a v2 Task should exist on {string} assigned to {string}") do |investor_name, user_key|
  investor = Investor.find_by!(investor_name: investor_name)
  deal_investor = DealInvestor.find_by!(deal: @deal, investor: investor)

  @created_task = Task.find_by(owner: deal_investor)
  expect(@created_task).not_to be_nil,
                               "Expected a Task on #{investor_name} but none found"
  expect(@created_task.assigned_to).to eq(@users[user_key]),
                                       "Expected task assigned to #{user_key} but got user ##{@created_task.assigned_to_id}"
end

# Asserts the Task is assigned to the sender (primary user).
Then("a v2 Task should exist on {string} assigned to the sender") do |investor_name|
  investor = Investor.find_by!(investor_name: investor_name)
  deal_investor = DealInvestor.find_by!(deal: @deal, investor: investor)

  @created_task = Task.find_by(owner: deal_investor)
  expect(@created_task).not_to be_nil,
                               "Expected a Task on #{investor_name} but none found"
  expect(@created_task.assigned_to).to eq(@user),
                                       "Expected task assigned to sender but got user ##{@created_task.assigned_to_id}"
end
