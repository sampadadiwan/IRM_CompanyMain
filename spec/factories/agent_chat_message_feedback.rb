# frozen_string_literal: true

FactoryBot.define do
  factory :agent_chat_message_feedback do
    association :agent_chat_message
    association :entity
    status { "open" }
    channel { "web" }

    trait :negative do
      rating { "negative" }
    end

    trait :positive do
      rating { "positive" }
    end

    trait :judged do
      judge_completeness { 2 }
      judge_grounding { 1 }
      judge_actionability { 2 }
      judge_total { 5 }
      judge_issues { ["Minor grounding issue"].to_json }
    end

    trait :low_score do
      judge_completeness { 1 }
      judge_grounding { 0 }
      judge_actionability { 1 }
      judge_total { 2 }
      status { "needs_review" }
    end

    trait :high_score do
      judge_completeness { 3 }
      judge_grounding { 3 }
      judge_actionability { 3 }
      judge_total { 9 }
    end
  end
end
