# frozen_string_literal: true

# Step definitions for Deal Update Agent processing scenarios.
# Tests the DealIngestProcessor pipeline — LLM parsing, stakeholder matching,
# Note/Task creation, and warehouse flow.

# --- LLM Stubbing ---

Given("the LLM will parse the email as a meeting note for {string}") do |stakeholder|
  @llm_parse_result = {
    "intent" => "meeting_note",
    "stakeholder_string" => stakeholder,
    "body" => "Great call with #{stakeholder} today, positive signals on 5M commitment",
    "due_date" => nil,
    "due_date_source_text" => nil
  }
end

Given("the LLM will parse the email as a task for {string} due {string}") do |stakeholder, due_date|
  @llm_parse_result = {
    "intent" => "task",
    "stakeholder_string" => stakeholder,
    "body" => "Send term sheet to #{stakeholder}",
    "due_date" => due_date,
    "due_date_source_text" => "by next Friday"
  }
end

Given("the LLM will parse the email with intent {string}") do |intent|
  @llm_parse_result = {
    "intent" => intent,
    "stakeholder_string" => nil,
    "body" => "Random gibberish content",
    "due_date" => nil,
    "due_date_source_text" => nil
  }
end

# --- Job Execution ---

When("the job is performed") do
  @ingested_email ||= AgentIngestedEmail.last
  expect(@ingested_email).not_to be_nil, "No AgentIngestedEmail found to process"

  # Execute the processor directly (bypasses Sidekiq for test determinism).
  # Temporarily switch to inline so deliver_later actually delivers.
  ActiveJob::Base.queue_adapter = :inline
  Chewy.strategy(:bypass) do
    DealIngestProcessor.call(@ingested_email.id)
  end
  ActiveJob::Base.queue_adapter = :test
  @ingested_email.reload
end

# --- Assertions: Note Creation ---

Then("a Note should exist on {string} with text {string}") do |investor_name, text_fragment|
  investor = Investor.find_by!(investor_name: investor_name)
  deal_investor = DealInvestor.find_by!(deal: @deal, investor: investor)

  @created_note = Note.find_by(owner: deal_investor, source_email: @ingested_email)
  expect(@created_note).not_to be_nil,
    "Expected a Note on #{investor_name} but none found"
  expect(@created_note.details.to_plain_text).to include(text_fragment)
end

Then("the Note should be flagged as created_by_agent with match_tier {string}") do |tier|
  expect(@created_note.created_by_agent).to be true
  expect(@created_note.match_tier).to eq(tier)
end

# --- Assertions: Task Creation ---

Then("a Task should exist on {string} with due date {string}") do |investor_name, due_date|
  investor = Investor.find_by!(investor_name: investor_name)
  deal_investor = DealInvestor.find_by!(deal: @deal, investor: investor)

  @created_task = Task.find_by(owner: deal_investor, source_email: @ingested_email)
  expect(@created_task).not_to be_nil,
    "Expected a Task on #{investor_name} but none found"
  expect(@created_task.due_date).to eq(Date.parse(due_date))
end

Then("the Task should be flagged as created_by_agent with match_tier {string}") do |tier|
  expect(@created_task.created_by_agent).to be true
  expect(@created_task.match_tier).to eq(tier)
end

# --- Assertions: Email Status ---

Then("the AgentIngestedEmail status should be {string}") do |status|
  @ingested_email.reload
  expect(@ingested_email.status).to eq(status),
    "Expected email status '#{status}' but got '#{@ingested_email.status}'"
end

# --- Assertions: Mailers ---

Then("a confirmation email should be sent to the user") do
  # Subject format: "✓ Meeting Note created on {deal} — {stakeholder}"
  confirmation = ActionMailer::Base.deliveries.find do |mail|
    mail.to.include?(@user.email) && mail.subject&.include?("created on")
  end
  expect(confirmation).not_to be_nil,
    "Expected a confirmation email to #{@user.email} but none found. Deliveries: #{ActionMailer::Base.deliveries.map(&:subject)}"
end

Then("a warehouse notification email should be sent to the user") do
  # Subject format: "⏳ Your update for {deal} needs manual review"
  notification = ActionMailer::Base.deliveries.find do |mail|
    mail.to.include?(@user.email) && mail.subject&.include?("manual review")
  end
  expect(notification).not_to be_nil,
    "Expected a warehouse notification email to #{@user.email} but none found. Deliveries: #{ActionMailer::Base.deliveries.map(&:subject)}"
end

# --- Assertions: Warehouse ---

Then("a WarehouseItem should exist for the deal with intent {string}") do |intent|
  @warehouse_item = WarehouseItem.find_by(deal: @deal)
  expect(@warehouse_item).not_to be_nil,
    "Expected a WarehouseItem for the deal but none found"
  expect(@warehouse_item.parsed_intent).to eq(intent)
  expect(@warehouse_item).to be_pending
end
