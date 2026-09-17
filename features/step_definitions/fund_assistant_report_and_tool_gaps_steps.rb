# frozen_string_literal: true

# Regression coverage for three response-quality gaps: FundAssistant's previously-empty
# default_report_queries, SpecificFundAssistant's dead OPERATIONAL_QUERIES, and
# ListCapitalDistributionPayments' "at least one filter" guard wrongly rejecting a
# query-only request.

Given('there is a fund for the entity') do
  @fund = FactoryBot.create(:fund, entity: @entity)
end

# "it should return more than one query" is already defined in
# portfolio_assistant_data_manager_steps.rb and asserts against @report_queries.size -- same
# variable name, reused here rather than redefining an identical step.
When('I ask FundAssistant for its default report queries') do
  @report_queries = FundAssistant.new(user: @user).default_report_queries
end

When('I ask SpecificFundAssistant for its default report queries') do
  @report_queries = SpecificFundAssistant.new(user: @user, fund: @fund).default_report_queries
end

Then('the queries should include one from STRATEGIC_QUERIES') do
  expect(@report_queries).to include(SpecificFundAssistant::STRATEGIC_QUERIES.first)
end

Then('the queries should include one from OPERATIONAL_QUERIES') do
  expect(@report_queries).to include(SpecificFundAssistant::OPERATIONAL_QUERIES.first)
end

When('I call the list_capital_distribution_payments tool with only a query filter') do
  data_manager = FundAssistantDataManager.new(user: @user)
  tool = FundAssistantTools::ListCapitalDistributionPayments.new(data_manager)
  @tool_response = JSON.parse(tool.execute(query: { payment_date_gteq: '2024-01-01' }))
end

Then('the tool should return a plain list, not an "at least one filter" error') do
  expect(@tool_response).to be_a(Array)
end
