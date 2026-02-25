FactoryBot.define do
  factory :agent_schedule do
    association :support_agent
    entity { support_agent.entity }
    frequency { 'daily' }
    run_at_time { '13:03' }
    timezone { 'UTC' }
    enabled { false }
    retry_count { 0 }
    retry_interval_minutes { 0 }
    notify_on_failure { false }
  end
end
