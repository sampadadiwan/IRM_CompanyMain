# for generating support agent reports, with traits for different statuses and KPI issues.
FactoryBot.define do
  factory :support_agent_report do
    association :support_agent
    owner { nil } # polymorphic association, set explicitly in tests
    owner_type { 'Investor' }
    status { 'completed' }
    json_fields { {} }

    # Trait for pending reports
    trait :pending do
      status { 'pending' }
    end

    # Trait for failed reports
    trait :failed do
      status { 'failed' }
    end

    # Trait with blocking issues
    trait :with_kpi_issues do
      json_fields do
        {
          "kpi_issues" => [
            { "field" => "revenue", "severity" => "blocking", "issue" => "Missing required KPI" }
          ]
        }
      end
    end
  end
end
