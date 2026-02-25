FactoryBot.define do
  factory :support_agent do
    association :entity
    name { 'Test Agent' }
    agent_type { 'PortfolioCompanyAgent' }
    enabled { true }
  end
end
