FactoryBot.define do
  factory :ai_report_section do
    ai_portfolio_report { nil }
    section_type { "MyString" }
    order_index { 1 }
    ai_generated_summary { "MyText" }
    status { "draft" }
  end
end
