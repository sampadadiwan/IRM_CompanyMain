# frozen_string_literal: true

#
# Regression coverage for the scope-based authorization bypass fix in
# FundAssistantDataManager -- see authorization_bypass_prevention_steps.rb for the full
# writeup of the vulnerability class this defends against.

Given('the user has the company_admin role') do
  @user.add_role(:company_admin)
end

Given('there is a capital call for the entity') do
  fund = FactoryBot.create(:fund, entity: @entity)
  @capital_call = FactoryBot.create(:capital_call, fund: fund, entity: @entity)
end

When('I call list_capital_calls with scope {string}') do |scope|
  FundAssistantDataManager.new(user: @user).list_capital_calls(scope: scope)
end

Then('the capital call should still exist') do
  expect(CapitalCall.where(id: @capital_call.id)).to be_any
end
