# frozen_string_literal: true

# Step definitions for Deal Update Agent v2 warehouse resolution scenarios.
# Tests manual filing and discarding of items the agent couldn't auto-process.

# --- Preconditions ---

Given("a v2 warehoused item exists for the deal with intent {string}") do |intent|
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

When("I v2 resolve the warehouse item as {string} for investor {string}") do |resolution, investor_name|
  investor = Investor.find_by!(investor_name: investor_name)
  deal_investor = DealInvestor.find_by!(deal: @deal, investor: investor)

  ActiveRecord::Base.transaction do
    note = Note.create!(
      entity_id: @deal.entity_id,
      user_id: @user.id,
      owner: deal_investor,
      details: @ingested_email.parse_json["body"] || "Filed from warehouse",
      on: Date.current
    )
    @ingested_email.mark_filed!(confidence: 1.0, match_tier: "M", filed_as: note)
    @warehouse_item.resolve!(user: @user, resolution: resolution)
  end
end

When("I v2 resolve the warehouse item as {string}") do |resolution|
  @warehouse_item.resolve!(user: @user, resolution: resolution)
end

# --- Assertions ---

Then("a v2 Note should exist on {string} flagged as match_tier {string}") do |investor_name, tier|
  investor = Investor.find_by!(investor_name: investor_name)
  deal_investor = DealInvestor.find_by!(deal: @deal, investor: investor)

  note = Note.find_by(owner: deal_investor)
  expect(note).not_to be_nil,
                      "Expected a Note on #{investor_name} but none found"
  @ingested_email.reload
  expect(@ingested_email.filed_as).to eq(note)
  expect(@ingested_email.match_tier).to eq(tier)
end

Then("the v2 WarehouseItem should be resolved as {string}") do |resolution|
  @warehouse_item.reload
  expect(@warehouse_item.resolution).to eq(resolution)
  expect(@warehouse_item.resolved_at).not_to be_nil
  expect(@warehouse_item.resolved_by).to eq(@user)
end

Then("no v2 Note or Task should be created") do
  @ingested_email.reload
  expect(@ingested_email.filed_as).to be_nil,
                                      "Expected no Note or Task but found #{@ingested_email.filed_as_type} ##{@ingested_email.filed_as_id}"
end
