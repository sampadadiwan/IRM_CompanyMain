# frozen_string_literal: true

# Shared setup and teardown for Deal Update Agent v2 cucumber features.
# Configures entity, users, deal, investor, and the single per-deal
# ingest address. Stubs LLM so tests never call a real AI provider.

Before('@deal_update_agent_v2') do
  # Stub LLM parser to return controlled responses.
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
  @original_queue_adapter = ActiveJob::Base.queue_adapter
  ActiveJob::Base.queue_adapter = :test

  # Disable Chewy indexing in tests.
  Chewy.strategy(:bypass)

  # Clear mail deliveries.
  ActionMailer::Base.deliveries.clear

  # Set the domain so the feature is enabled.
  @original_domain = ENV.fetch("DEAL_INGEST_DOMAIN", nil)
  ENV["DEAL_INGEST_DOMAIN"] = "dev.caphive.app"
end

After('@deal_update_agent_v2') do
  ActiveJob::Base.queue_adapter = @original_queue_adapter if @original_queue_adapter
  ENV["DEAL_INGEST_DOMAIN"] = @original_domain
end

# --- Entity ---

Given("a v2 entity exists with deals enabled") do
  @entity = FactoryBot.create(:entity, entity_type: "Company", enable_deals: true)
end

# --- Users ---
# Stores multiple users in @users hash for multi-user scenarios.

Given("a v2 user {string} exists with role {string} in the entity") do |user_key, role|
  @users ||= {}
  email = "#{user_key}@testfund.com"
  user = FactoryBot.create(:user, entity: @entity, email: email)
  user.add_role(role.to_sym) if role != "employee"
  @users[user_key] = user

  # First user created becomes @user (primary user for most scenarios).
  @user ||= user
end

# --- Deal Access ---
# In v2, address is per-deal. Users need AccessRight to send emails.

Given("the user has deal access to the deal") do
  AccessRight.create!(owner: @deal, user: @user, entity: @entity, access_type: "Deal")
end

Given("the second user has deal access to the deal") do
  second_user = @users.values.last
  AccessRight.create!(owner: @deal, user: second_user, entity: @entity, access_type: "Deal")
end

# --- Deal ---

Given("a v2 deal {string} exists in the entity") do |deal_name|
  @deal = FactoryBot.create(:deal, entity: @entity, name: deal_name)
end

# --- Investor ---

Given("the deal has a v2 investor {string}") do |investor_name|
  @investor = FactoryBot.create(:investor, entity: @entity, investor_name: investor_name)
  @deal_investor = FactoryBot.create(:deal_investor, deal: @deal, investor: @investor)
end

# --- Ingest Address ---
# One address per deal (not per user). Default = deal ID.

Given("a deal ingest address exists for the deal") do
  @ingest_address = @deal.ensure_deal_ingest_address ||
                    DealIngestAddress.create!(deal: @deal, address: @deal.id.to_s)
end

# Grant deal access to a named user (not the primary user).
#
# @param user_key [String] the user key from @users hash
Given("the {string} user has deal access to the deal") do |user_key|
  user = @users[user_key]
  AccessRight.create!(owner: @deal, user: user, entity: @entity, access_type: "Deal")
end

# Set a user's first name explicitly for assignee matching scenarios.
#
# @param user_key [String] the user key from @users hash
# @param first_name [String] the first name to set
Given("the {string} user has first name {string}") do |user_key, first_name|
  @users[user_key].update!(first_name: first_name)
end
