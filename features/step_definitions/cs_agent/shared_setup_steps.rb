# frozen_string_literal: true

# Shared setup steps used across all CS agent feature files.

Before do
  # Stub LLM so tests never call a real AI provider.
  # Returns context-appropriate responses based on the user message.
  fake_chat = double("RubyLLM::Chat",
    with_instructions: nil,
    with_tools: nil,
    add_message: nil,
    on_new_message: nil,
    before_tool_call: nil,
    messages: []
  )
  allow(fake_chat).to receive(:ask) do |message|
    content = case message.to_s.downcase
              when /capital call/
                "To create a capital call, navigate to **Funds > Capital Calls** and click 'New Capital Call'. Follow the steps in the guide."
              when /how many funds/
                "Based on your entity data, you currently have 3 active funds."
              when /speak to a human|escalat|help me/
                "Your conversation has been escalated to our support team. They will review your request shortly."
              else
                "Here is some helpful information based on your question. Please refer to the user guides for more details."
              end
    OpenStruct.new(content: content)
  end
  allow(LlmService).to receive(:ruby_llm_chat).and_return(fake_chat)
end


Given("an entity exists with a customer support agent configured") do
  @entity = FactoryBot.create(:entity)
  @entity_setting = FactoryBot.create(:entity_setting, entity: @entity, cs_judge_enabled: true)
  @support_agent = FactoryBot.create(:support_agent,
                                     entity: @entity,
                                     agent_type: "CustomerSupportAgent",
                                     name: "Customer Support Agent")
end

Given("a fund manager user exists in that entity") do
  @fm_user = FactoryBot.create(:user, entity: @entity)
  @fm_user.add_role(:employee)
end

Given("the entity has cs_judge_enabled set to {string}") do |value|
  setting = @entity.entity_setting || FactoryBot.create(:entity_setting, entity: @entity)
  setting.update!(cs_judge_enabled: value == "true")
end

Given("the entity has cs_judge_enabled set to true") do
  setting = @entity.entity_setting || FactoryBot.create(:entity_setting, entity: @entity)
  setting.update!(cs_judge_enabled: true)
end

Given("the entity has cs_judge_enabled set to false") do
  setting = @entity.entity_setting || FactoryBot.create(:entity_setting, entity: @entity)
  setting.update!(cs_judge_enabled: false)
end

Given("I am logged in as the fund manager user") do
  @user = @fm_user
  steps %(
    And I am at the login page
    When I fill and submit the login page
  )
end

Given("the FM user has a chat session with a negative-rated feedback item") do
  @chat_session = FactoryBot.create(:agent_chat_session,
                                    support_agent: @support_agent,
                                    analyst: @fm_user,
                                    chattable: @fm_user)

  user_msg = FactoryBot.create(:agent_chat_message, :user_message,
                               agent_chat_session: @chat_session)

  @assistant_msg = FactoryBot.create(:agent_chat_message, :assistant_message,
                                     agent_chat_session: @chat_session,
                                     created_at: user_msg.created_at + 1.second)

  @feedback = FactoryBot.create(:agent_chat_message_feedback, :negative,
                                agent_chat_message: @assistant_msg,
                                entity: @entity,
                                status: "needs_review")
end
