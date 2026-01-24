FactoryBot.define do
  factory :investment_criteria_template do
    name { "Default Template" }
    criteria { [{ name: "ARR", value: ">$1M" }] }
    usage_count { 0 }
    association :created_by_user, factory: :user
    association :entity
  end
end
