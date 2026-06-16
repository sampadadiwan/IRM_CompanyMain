# frozen_string_literal: true

FactoryBot.define do
  factory :customer_support_escalation do
    association :agent_chat_session
    association :user
    association :entity
    reason { "customer_requested" }
    status { "open" }
    summary { "User requested human support." }

    trait :resolved do
      status { "resolved" }
      resolved_at { Time.current }
      association :resolved_by, factory: :user
    end

    trait :max_iterations do
      reason { "max_iterations" }
      summary { "Auto-escalated: agent exceeded tool call limit." }
    end
  end
end
