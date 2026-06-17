# frozen_string_literal: true

FactoryBot.define do
  factory :agent_chat_session do
    association :support_agent
    association :analyst, factory: :user
    status { "active" }

    trait :escalated do
      status { "escalated" }
    end

    trait :with_chattable do
      chattable { association :user }
    end
  end
end
