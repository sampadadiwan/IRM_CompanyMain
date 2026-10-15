# Steps for features/fund/capital_call_requires_commitments.feature
# (openspec/changes/block-capital-call-without-commitments, worked examples in design.md Part 4)

# Runs CapitalCallCreate the way the controller and importer do. closes is comma separated ("All",
# "First Close, Second Close"); a Percentage of Commitment call gets 10% for each named close.
When('I create a capital call through the operation for {string} closes with basis {string}') do |closes, basis|
  @calls_before = CapitalCall.where(fund: @fund).count
  fund_closes = closes.split(",").map(&:strip)
  @capital_call = FactoryBot.build(:capital_call, fund: @fund, entity: @fund.entity, call_basis: basis, fund_closes:,
                                                  name: "Call #{SecureRandom.hex(3)}")
  @capital_call.close_percentages = fund_closes.excluding("All").index_with { "10" } if fund_closes.exclude?("All")
  allow(UpdateDocumentFolderPathJob).to receive(:perform_later).and_return(nil)
  @create_result = CapitalCallCreate.call(capital_call: @capital_call)
end

Then('the capital call is created') do
  expect(@create_result).to be_success, @create_result[:errors].to_s
  expect(@capital_call).to be_persisted
end

Then('the capital call create is refused with the no commitments message') do
  expect(@create_result).to be_failure
  expect(@create_result[:errors]).to eq(CapitalCallCreate::NO_APPLICABLE_COMMITMENTS_MESSAGE)
  expect(@capital_call.errors[:base]).to include(CapitalCallCreate::NO_APPLICABLE_COMMITMENTS_MESSAGE)
end

Then('no capital call is created') do
  expect(CapitalCall.where(fund: @fund).count).to eq(@calls_before)
  expect(CapitalRemittance.where(fund: @fund)).not_to exist
end

Then('remittances are created only for the {string} commitments') do |fund_close|
  expected = @fund.capital_commitments.where(fund_close:).pluck(:id)
  expect(expected).not_to be_empty
  expect(@capital_call.reload.capital_remittances.pluck(:capital_commitment_id)).to match_array(expected)
end

# The New Call form on a fund whose commitments don't cover the call (X1)
When('I submit the new capital call form named {string}') do |name|
  @calls_before = CapitalCall.where(fund: @fund).count
  visit(fund_url(@fund))
  open_tab_pane('capital-calls-tab') # under the fund page's Cash Flows dropdown
  click_on "New Call"
  click_on "Classic Form"
  fill_in('capital_call_name', with: name)
  fill_in('capital_call_due_date', with: Time.zone.today + 2.weeks)
  fill_in('capital_call_percentage_called', with: "10") if page.has_field?('capital_call_percentage_called', wait: 0)
  allow(UpdateDocumentFolderPathJob).to receive(:perform_later).and_return(nil)
  click_on "Save"
end

Then('the capital call form shows the no commitments error and keeps the name {string}') do |name|
  expect(page).to have_content("prohibited this capital call from being saved")
  expect(page).to have_content(CapitalCallCreate::NO_APPLICABLE_COMMITMENTS_MESSAGE)
  # The re-rendered form opens in wizard mode, like any other failed save
  click_on "Classic Form"
  expect(page).to have_field('capital_call_name', with: name)
end

# Signs in through the real sign-in form on an integration session, as report_builder_steps.rb does
When('I post a capital call as JSON for the fund') do
  @calls_before = CapitalCall.where(fund: @fund).count
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.post("/users/sign_in", params: { user: { email: @user.email, password: "password" } })
  session.post("/capital_calls.json",
               params: { capital_call: { entity_id: @fund.entity_id, fund_id: @fund.id, name: "JSON Call", call_basis: "Percentage of Commitment",
                                         percentage_called: 10, fund_closes: ["All"],
                                         call_date: Time.zone.today, due_date: Time.zone.today + 2.weeks } }.to_json,
               headers: { "Content-Type" => "application/json", "Accept" => "application/json" })
  @json_response = session.response
end

Then('the JSON response is refused with the no commitments message') do
  expect(@json_response.status).to eq(422)
  expect(JSON.parse(@json_response.body)["base"]).to include(CapitalCallCreate::NO_APPLICABLE_COMMITMENTS_MESSAGE)
end

When('I change the capital call closes to {string}') do |closes|
  @capital_call.reload
  @capital_call.fund_closes = closes.split(",").map(&:strip)
  @update_result = CapitalCallUpdate.call(capital_call: @capital_call, current_user: @user)
end

Then('the capital call edit is saved') do
  expect(@update_result).to be_success, @update_result[:errors].to_s
  expect(@capital_call.reload.fund_closes).to eq(["Second Close"])
end

Then('the fund has a capital call named {string}') do |name|
  expect(@fund.capital_calls.where(name:)).to exist
end
