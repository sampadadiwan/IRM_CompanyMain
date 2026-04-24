FactoryBot.define do
  factory :report_schedule do
    report { nil }
    frequency { "MyString" }
    recipients { "MyText" }
    cron_expression { "MyString" }
    active { false }
    last_run_at { "2026-04-23 22:25:51" }
  end
end
