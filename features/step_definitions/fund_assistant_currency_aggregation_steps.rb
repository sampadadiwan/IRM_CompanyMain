# frozen_string_literal: true

#
# Regression coverage for the currency-mixing fix in
# FundAssistantDataManager#perform_aggregation (CURRENCY_GROUPING / currency_aware_sum /
# currency_aware_group_by_sum) -- see that constant's comment for the full writeup of which
# models are currency-resolved vs deliberately left flagged as `currency_unresolved`.

Given('there is a capital call of {int} cents in a fund with currency {string}') do |cents, currency|
  fund = FactoryBot.create(:fund, entity: @entity, currency: currency)
  # call_basis: 'Upload' skips CapitalCall's auto-generate-remittances side effect (only
  # fires when call_basis != 'Upload'), which isn't needed for an aggregation-only test.
  FactoryBot.create(:capital_call, fund: fund, entity: @entity, call_basis: 'Upload', call_amount_cents: cents)
end

Given('there is a capital call of {int} cents in another fund with currency {string}') do |cents, currency|
  fund = FactoryBot.create(:fund, entity: @entity, currency: currency)
  FactoryBot.create(:capital_call, fund: fund, entity: @entity, call_basis: 'Upload', call_amount_cents: cents)
end

When('I sum capital calls by {string}') do |field|
  @aggregate_result = FundAssistantDataManager.new(user: @user).list_capital_calls(aggregate: 'sum', query: { aggregate_field: field })
end

Then('the sum result should be a single total of {int} with currency {string}') do |total, currency|
  expect(@aggregate_result[:total]).to eq(total)
  expect(@aggregate_result[:currency]).to eq(currency)
end

Then('the sum result should report separate totals for {string} and {string} instead of one blended number') do |currency_a, currency_b|
  breakdown = @aggregate_result[:totals_by_currency]
  expect(breakdown).not_to be_nil
  currencies = breakdown.pluck(:currency)
  expect(currencies).to include(currency_a, currency_b)
end

Given('there is a capital commitment for the entity') do
  fund = FactoryBot.create(:fund, entity: @entity)
  # Investor.create! (not the :investor factory) to avoid that factory's flaky
  # Entity.startups.sample defaults, mirroring the pattern already used for portfolio
  # companies elsewhere in this suite.
  investor = Investor.create!(entity_id: @entity.id, investor_name: 'LP One',
                              primary_email: 'lp.one@example.com', category: 'Investor')
  @capital_commitment = FactoryBot.create(:capital_commitment, fund: fund, entity: @entity, investor: investor)
end

When('I sum capital commitments by {string}') do |field|
  @aggregate_result = FundAssistantDataManager.new(user: @user).list_capital_commitments(aggregate: 'sum', query: { aggregate_field: field })
end

Then('the sum result should be marked as currency_unresolved') do
  expect(@aggregate_result[:currency_unresolved]).to eq(true)
end
