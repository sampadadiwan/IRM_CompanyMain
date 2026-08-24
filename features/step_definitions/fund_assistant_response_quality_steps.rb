# frozen_string_literal: true

#
# Regression coverage for two FundAssistantDataManager response-quality fixes:
#  1. bounded_limit -- extends the same server-side default-LIMIT cap already covered for
#     PortfolioAssistantDataManager (see portfolio_assistant_data_manager_steps.rb) to
#     FundAssistantDataManager; reuses that file's "the resulting SQL should apply..." Then
#     steps since they just assert against @bounded_relation regardless of which data
#     manager produced it.
#  2. unrecognized_scope_error -- an LLM-supplied `scope` that isn't declared on the
#     relevant *Query class now comes back as an explicit error instead of being silently
#     dropped (which previously looked like a successful, but quietly unfiltered, result).

When('I bound a fund assistant query relation with no explicit limit') do
  @bounded_relation = FundAssistantDataManager.new(user: @user).send(:bounded_limit, CapitalCall.all, nil)
end

When('I bound a fund assistant query relation with an explicit limit of {int}') do |limit|
  @bounded_relation = FundAssistantDataManager.new(user: @user).send(:bounded_limit, CapitalCall.all, limit)
end

When('I call list_fund_ratios with scope {string}') do |scope|
  @fund_ratio_result = FundAssistantDataManager.new(user: @user).list_fund_ratios(scope: scope)
end

Then('I should get an unrecognized scope error naming the valid scopes {string}') do |scopes_csv|
  expect(@fund_ratio_result).to be_a(Hash)
  expect(@fund_ratio_result[:error]).to include("Unknown scope")
  scopes_csv.split(', ').each { |valid_scope| expect(@fund_ratio_result[:error]).to include(valid_scope) }
end

Given('there is a fund ratio named {string} marked latest for the entity') do |name|
  fund = FactoryBot.create(:fund, entity: @entity)
  FactoryBot.create(:fund_ratio, entity: @entity, fund: fund, name: name,
                                 owner_type: 'Fund', owner_id: fund.id, latest: true)
end

Then('the fund ratio results should include {string}') do |name|
  expect(@fund_ratio_result.pluck(:name)).to include(name)
end
