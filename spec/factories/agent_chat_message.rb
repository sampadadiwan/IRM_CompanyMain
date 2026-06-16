# frozen_string_literal: true

FactoryBot.define do
  factory :agent_chat_message do
    association :agent_chat_session
    role { "assistant" }
    content { "This is a test response." }
    channel { "web" }

    trait :user_message do
      role { "user" }
      content { "How do I create a capital call?" }
    end

    trait :assistant_message do
      role { "assistant" }
      content { "Here are the steps to create a capital call..." }
    end
  end
end
