# frozen_string_literal: true

# Step definitions for Deal Update Agent warehouse resolution scenarios.
# Tests manual filing and discarding of items the agent couldn't auto-process.

# --- Preconditions ---

Given("a warehoused item exists for the deal with intent {string}") do |intent|
  @ingested_email = AgentIngestedEmail.create!(
    deal: @deal,
    sender_user: @user,
    message_id: "warehouse-test-#{SecureRandom.hex(4)}@mail.test",
    raw_payload: "Test email for warehouse",
    received_at: 1.hour.ago,
    status: "warehoused",
    parse_json: {
      "intent" => intent,
      "stakeholder_string" => "Unknown Company",
      "body" => "Test email content for warehouse filing",
      "due_date" => nil
    }
  )

  @warehouse_item = WarehouseItem.create!(
    agent_ingested_email: @ingested_email,
    deal: @deal,
    parsed_intent: intent,
    candidate_stakeholder_ids: []
  )
end

# --- Actions ---

When("I resolve the warehouse item as {string} for investor {string}") do |resolution, investor_name|
  investor = Investor.find_by!(investor_name: investor_name)
  deal_investor = DealInvestor.find_by!(deal: @deal, investor: investor)

  # Simulate the controller's file_warehouse_item! logic directly.
  ActiveRecord::Base.transaction do
    Note.create!(
      entity_id: @deal.entity_id,
      user_id: @user.id,
      owner: deal_investor,
      details: @ingested_email.parse_json["body"] || "Filed from warehouse",
      on: Date.current,
      source_email: @ingested_email,
      created_by_agent: true,
      match_tier: "M"
    )
    @ingested_email.mark_filed!(confidence: 1.0, match_tier: "M")
    @warehouse_item.resolve!(user: @user, resolution: resolution)
  end
end

When("I resolve the warehouse item as {string}") do |resolution|
  @warehouse_item.resolve!(user: @user, resolution: resolution)
end

# --- Assertions ---

Then("a Note should exist on {string} flagged as match_tier {string}") do |investor_name, tier|
  investor = Investor.find_by!(investor_name: investor_name)
  deal_investor = DealInvestor.find_by!(deal: @deal, investor: investor)

  note = Note.find_by(owner: deal_investor, match_tier: tier)
  expect(note).not_to be_nil,
    "Expected a Note on #{investor_name} with match_tier '#{tier}' but none found"
  expect(note.created_by_agent).to be true
end

Then("the WarehouseItem should be resolved as {string}") do |resolution|
  @warehouse_item.reload
  expect(@warehouse_item.resolution).to eq(resolution)
  expect(@warehouse_item.resolved_at).not_to be_nil
  expect(@warehouse_item.resolved_by).to eq(@user)
end

Then("no Note or Task should be created") do
  notes_count = Note.where(source_email: @ingested_email).count
  tasks_count = Task.where(source_email: @ingested_email).count
  expect(notes_count + tasks_count).to eq(0),
    "Expected no Note or Task but found #{notes_count} notes and #{tasks_count} tasks"
end
