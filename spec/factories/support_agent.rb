FactoryBot.define do
  factory :support_agent do
    association :entity
    name { 'Test Agent' }
    agent_type { 'PortfolioCompanyAgent' }
    enabled { true }
    llm_model { 'gemini-3-flash-preview' }
    category { "Ops" }
  end
end
