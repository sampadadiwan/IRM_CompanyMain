# frozen_string_literal: true

# Steps for features/security/fund_records_firm_policy.feature. Requests go through the website as the
# signed-in user (rack_test), the way a tampered form would. Tenant setup and "I am denied access" are in
# tenant_isolation_batch1_steps.rb.

When('I create a capital call {string} on the fund {string}') do |name, fund_name|
  fund = Fund.find_by!(name: fund_name)
  # The firm the form posts is the user's own; only the fund names the other firm
  page.driver.submit :post, capital_calls_path,
                     { capital_call: { entity_id: @entity.id, fund_id: fund.id, name:, percentage_called: 10,
                                       call_date: Time.zone.today, due_date: Time.zone.today + 30,
                                       call_basis: "Percentage of Commitment", fund_closes: ["All"] } }
end

# A call needs at least one commitment it applies to. Investor.create! (not the :investor factory) avoids
# that factory's random Entity defaults, as lp_portfolio_steps.rb does.
Given('the fund {string} has a commitment') do |fund_name|
  fund = Fund.find_by!(name: fund_name)
  investor = Investor.create!(entity_id: fund.entity_id, investor_name: "LP #{SecureRandom.hex(3)}",
                              primary_email: "lp-#{SecureRandom.hex(3)}@example.com", category: "LP")
  FactoryBot.create(:capital_commitment, fund:, entity_id: fund.entity_id, investor:, folio_id: "F-#{SecureRandom.hex(2)}")
end

Given('there is a capital call {string} on the fund {string}') do |name, fund_name|
  fund = Fund.find_by!(name: fund_name)
  FactoryBot.create(:capital_call, fund:, entity: fund.entity, name:)
end

When('I move the capital call {string} to the fund {string}') do |name, fund_name|
  call = CapitalCall.find_by!(name:)
  page.driver.submit :patch, capital_call_path(call), { capital_call: { fund_id: Fund.find_by!(name: fund_name).id } }
end

When('I rename the capital call {string} to {string}') do |name, new_name|
  call = CapitalCall.find_by!(name:)
  page.driver.submit :patch, capital_call_path(call), { capital_call: { name: new_name } }
end

Then('the fund {string} has a capital call {string}') do |fund_name, name|
  # On failure, show the page the request answered (eg the form's validation errors)
  expect(Fund.find_by!(name: fund_name).capital_calls.where(name:)).to exist,
                                                                        page.all(".alert, .invalid-feedback, #error_explanation").map(&:text).join(" | ").presence || page.text.squish.last(600)
end

Then('the fund {string} has no capital call {string}') do |fund_name, name|
  expect(Fund.find_by!(name: fund_name).capital_calls.where(name:)).not_to exist
end

Then('the capital call {string} is on the fund {string}') do |name, fund_name|
  expect(CapitalCall.find_by!(name:).fund).to eq(Fund.find_by!(name: fund_name))
end
