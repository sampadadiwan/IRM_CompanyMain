# frozen_string_literal: true

# Steps for features/api/calls_distributions_bulk.feature (funds-json-api-hardening phase 10: P12 P13 G16
# G17 G18). Requests and setup come from api_json_steps.rb and api_import_steps.rb.

Given("{string} is an approver") do |name|
  api_user(name).add_role(:approver)
end

Given("every capital call of my fund is approved already") do
  @fund.capital_calls.find_each { |call| call.update_columns(approved: true, approved_by_user_id: @user.id) }
end

Then("every capital call of my fund is approved") do
  expect(@fund.capital_calls.where(approved: false)).to be_none, @fund.capital_calls.pluck(:name, :approved).inspect
end

Then("no capital call of my fund is approved") do
  expect(@fund.capital_calls.where(approved: true)).to be_none
end

Then("every capital call of my fund has units_job_finished_at set") do
  expect(@fund.capital_calls.where(units_job_finished_at: nil)).to be_none
end

Then("every capital distribution of my fund is approved") do
  expect(@fund.capital_distributions.where(approved: false)).to be_none
end

Given("every capital distribution of my fund has unit prices") do
  @fund.capital_distributions.find_each do |distribution|
    distribution.update_column(:unit_prices, distribution.unit_prices.presence || { "Series A" => 100 })
  end
end

Then("every capital distribution of my fund has units_job_finished_at set") do
  expect(@fund.capital_distributions.where(units_job_finished_at: nil)).to be_none
end

Given("my fund's start date is {string} and first close date is {string}") do |start_date, first_close|
  @fund.update_columns(start_date: Date.iso8601(start_date), first_close_date: Date.iso8601(first_close))
end

# E43 — the template's currency columns are still stored on the distribution as custom fields (as before)
Then("the capital distribution {string} has {string} in its custom fields") do |title, value|
  distribution = @fund.capital_distributions.find_by!(title:)
  expect(distribution.properties.to_h.values.map(&:to_s)).to include(value), distribution.properties.inspect
end
