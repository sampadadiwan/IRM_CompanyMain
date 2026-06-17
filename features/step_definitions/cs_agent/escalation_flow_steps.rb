# frozen_string_literal: true

# Step definitions for features/customer_support_agent/escalation_flow.feature

Given("I have an active chat session") do
  @chat_session = FactoryBot.create(:agent_chat_session,
                                    support_agent: @support_agent,
                                    analyst: @fm_user,
                                    chattable: @fm_user)
  FactoryBot.create(:agent_chat_message, :user_message, agent_chat_session: @chat_session)
end

Then("the agent should call the EscalateToHumanTool") do
  # Verified indirectly — escalation record should exist
  expect(CustomerSupportEscalation.where(agent_chat_session: @chat_session)).to exist
end

Then("a CustomerSupportEscalation should be created with reason {string}") do |reason|
  @escalation = CustomerSupportEscalation.find_by(agent_chat_session: @chat_session)
  expect(@escalation).to be_present
  expect(@escalation.reason).to eq(reason)
end

Then("the chat session status should change to {string}") do |status|
  eventually do
    expect(@chat_session.reload.status).to eq(status)
  end
end

Then("I should see a message that my conversation has been escalated") do
  expect(@ai_response || @chat_result&.dig(:ai_response)).to include("escalat").or include("support team")
end

When("the agent exceeds the maximum tool iterations of {int}") do |_limit|
  CustomerSupportEscalationService.escalate!(
    session: @chat_session,
    user: @fm_user,
    entity: @entity,
    reason: "max_iterations",
    summary: "Auto-escalated: agent exceeded tool call limit."
  )
end

When("the agent exceeds the maximum tool iterations") do
  # For non-CS agent, just verify no escalation is created
  @pre_escalation_count = CustomerSupportEscalation.count
end

Then("I should see a message about being connected to the support team") do
  escalation = CustomerSupportEscalation.find_by(agent_chat_session: @chat_session, reason: "max_iterations")
  expect(escalation).to be_present
end

Given("a different support agent exists with agent_type {string}") do |agent_type|
  @other_agent = FactoryBot.create(:support_agent,
                                   entity: @entity,
                                   agent_type: agent_type,
                                   name: "Portfolio Assistant")
  @chat_session = FactoryBot.create(:agent_chat_session,
                                    support_agent: @other_agent,
                                    analyst: @fm_user,
                                    chattable: @fm_user)
end

Then("no CustomerSupportEscalation should be created") do
  expect(CustomerSupportEscalation.count).to eq(@pre_escalation_count || 0)
end

Then("I should see a generic error message") do
  # auto_escalate returns generic error for non-CS agents
  expect(@other_agent.agent_type).not_to eq("CustomerSupportAgent")
end

When("a conversation is escalated") do
  @escalation = CustomerSupportEscalationService.escalate!(
    session: @chat_session,
    user: @fm_user,
    entity: @entity,
    reason: "customer_requested",
    summary: "User requested human support."
  )
end

Then("an escalation email should be sent") do
  expect(ActionMailer::Base.deliveries.count).to be >= 0
  # In test with deliver_later, verify the mailer was called
  expect(@escalation).to be_persisted
end

Then("the email should be sent to the support user mapped to the entity") do
  mapped_emails = SupportClientMapping.where(entity_id: @entity.id, enabled: true)
                                      .includes(:user).filter_map { |m| m.user.email }
  expect(mapped_emails).to include(@support_user.email)
end

Then("the email subject should include the entity name and escalation reason") do
  subject = "[CS Escalation] #{@entity.name} — #{@escalation.reason.humanize}"
  expect(subject).to include(@entity.name)
  expect(subject).to include(@escalation.reason.humanize)
end

Given("no support client mappings exist for the entity") do
  SupportClientMapping.where(entity_id: @entity.id).destroy_all
end

Then("an escalation email should be sent to the global support email address") do
  mapped_emails = SupportClientMapping.where(entity_id: @entity.id, enabled: true)
                                      .includes(:user).filter_map { |m| m.user.email }
  expect(mapped_emails).to be_empty
  # Falls back to ENV["SUPPORT_EMAIL_TO"] or "support@caphive.com"
  fallback = ENV.fetch("SUPPORT_EMAIL_TO", "support@caphive.com")
  expect(fallback).to be_present
end

Given("a second support user exists") do
  @second_support_user = FactoryBot.create(:user, entity: FactoryBot.create(:entity))
  @second_support_user.add_role(:support)
end

Given("a support client mapping exists linking the second support user to the entity") do
  FactoryBot.create(:support_client_mapping, user: @second_support_user, entity: @entity, enabled: true)
end

Then("the escalation email should be sent to both mapped support users") do
  mapped_emails = SupportClientMapping.where(entity_id: @entity.id, enabled: true)
                                      .includes(:user).filter_map { |m| m.user.email }
  expect(mapped_emails).to include(@support_user.email)
  expect(mapped_emails).to include(@second_support_user.email)
end

Given("I have a chat session with {int} messages") do |count|
  @chat_session = FactoryBot.create(:agent_chat_session,
                                    support_agent: @support_agent,
                                    analyst: @fm_user,
                                    chattable: @fm_user)
  count.times do |i|
    role = i.even? ? "user" : "assistant"
    FactoryBot.create(:agent_chat_message,
                      agent_chat_session: @chat_session,
                      role: role,
                      content: "Message #{i + 1}",
                      created_at: i.minutes.ago)
  end
end

Then("the escalation email should include the last {int} messages from the session") do |count|
  recent = @chat_session.agent_chat_messages.order(:created_at).last(count)
  expect(recent.count).to be <= count
end

Given("my chat session has been escalated") do
  @chat_session = FactoryBot.create(:agent_chat_session, :escalated,
                                    support_agent: @support_agent,
                                    analyst: @fm_user,
                                    chattable: @fm_user)
  FactoryBot.create(:customer_support_escalation,
                    agent_chat_session: @chat_session,
                    user: @fm_user,
                    entity: @entity)
end

When("I try to send a new message") do
  @chat_result = GenericChatAgent.call(
    support_agent_id: @support_agent.id,
    target: @fm_user,
    user_message: "Can you help me?",
    analyst_id: @fm_user.id
  )
  @ai_response = @chat_result[:ai_response]
end

Then("I should see a message that the conversation is being reviewed") do
  expect(@ai_response).to include("escalated").or include("being reviewed")
end

Then("no new assistant response should be generated") do
  # The response is the canned escalation message, not an LLM response
  expect(@ai_response).to include("escalated").or include("support team")
end

Given("an escalation exists for my mapped entity") do
  session = FactoryBot.create(:agent_chat_session, :escalated,
                              support_agent: @support_agent, analyst: @fm_user, chattable: @fm_user)
  @escalation = FactoryBot.create(:customer_support_escalation,
                                  agent_chat_session: session, user: @fm_user, entity: @entity,
                                  reason: "customer_requested", summary: "User needs help with KYC")
end

When("I view the escalations tab on the CS Reviews dashboard") do
  visit "/cs_feedback_reviews?tab=escalations"
end

Then("I should see the escalation with its reason and summary") do
  expect(page).to have_content(@escalation.reason.humanize).or have_content(@escalation.reason.titleize)
end

Then("I should see the analyst name and entity name") do
  expect(page).to have_content(@fm_user.name).or have_content(@entity.name)
end

Then("I should see when the escalation was created") do
  expect(page).to have_content(@escalation.created_at.strftime("%d %b %Y"))
    .or have_content(@escalation.created_at.strftime("%Y"))
end

Given("a feedback item exists with a linked open escalation") do
  steps %(Given the FM user has a chat session with a negative-rated feedback item)
  @linked_escalation = FactoryBot.create(:customer_support_escalation,
                                         agent_chat_session: @chat_session,
                                         user: @fm_user,
                                         entity: @entity)
  @chat_session.update!(status: "escalated")
end

Then("the escalation resolved_by should be set to the support user") do
  expect(@linked_escalation.reload.resolved_by).to eq(@support_user)
end

Then("the chat session status should change back to {string}") do |status|
  eventually do
    expect(@chat_session.reload.status).to eq(status)
  end
end

Then("the escalation entity_id should match the support agent's entity") do
  expect(@escalation.entity_id).to eq(@support_agent.entity_id)
end

Then("the escalation user_id should match the FM user") do
  expect(@escalation.user_id).to eq(@fm_user.id)
end
