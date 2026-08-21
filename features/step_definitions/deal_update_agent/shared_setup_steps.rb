# frozen_string_literal: true

# Shared setup steps for Deal Update Agent cucumber features.
# Configures entity, user, deal, investor, and ingest address fixtures.
# Stubs LLM so tests never call a real AI provider.

Before('@deal_update_agent') do
  # Stub LLM parser to return controlled responses.
  # The actual parse result is set per-scenario via @llm_parse_result.
  @llm_parse_result = nil
  allow(DealEmailParser).to receive(:call) do
    @llm_parse_result || {
      "intent" => "meeting_note",
      "stakeholder_string" => "Sequoia Capital",
      "body" => "Great call with Sequoia Capital today, positive signals on 5M commitment",
      "due_date" => nil,
      "due_date_source_text" => nil
    }
  end

  # Use :test adapter so we can assert enqueued jobs and control execution.
  # Default :inline would run the job immediately on authenticate, before
  # we can assert on the intermediate "pending" state.
  @original_queue_adapter = ActiveJob::Base.queue_adapter
  ActiveJob::Base.queue_adapter = :test

  # Disable Chewy indexing in tests.
  Chewy.strategy(:bypass)

  # Clear mail deliveries.
  ActionMailer::Base.deliveries.clear
end

After('@deal_update_agent') do
  # Restore original queue adapter to avoid leaking into other tests.
  ActiveJob::Base.queue_adapter = @original_queue_adapter if @original_queue_adapter
end

Given("an entity exists with deals enabled") do
  @entity = FactoryBot.create(:entity, entity_type: "Company", enable_deals: true)
end

Given("a user exists with role {string} in the entity") do |role|
  @user = FactoryBot.create(:user, entity: @entity, email: "fm1@testfund.com")
  @user.add_role(role.to_sym)
end

Given("a deal {string} exists in the entity") do |deal_name|
  @deal = FactoryBot.create(:deal, entity: @entity, name: deal_name)
end

Given("the deal has an investor {string}") do |investor_name|
  @investor = FactoryBot.create(:investor, entity: @entity, investor_name: investor_name)
  @deal_investor = FactoryBot.create(:deal_investor, deal: @deal, investor: @investor)
end

Given("a deal ingest address exists for the user on the deal") do
  @ingest_address = DealIngestAddress.create!(deal: @deal, user: @user)
end
