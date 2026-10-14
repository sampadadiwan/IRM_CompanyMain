# Steps for features/fund/evergreen/evergreen_fund_on_create.feature: choose closed-ended or open-ended on
# New Fund, create an open-ended fund with its terms in one go, and no switching afterwards.
# Worked examples H1–H5, E1–E6, X1–X5 — openspec/changes/evergreen-fund-on-create/design.md#worked-examples

# Lands on the type page (company with open-ended funds on, H5) or straight on the fund details (E1)
When('I start a new fund') do
  evergreen_visit(new_fund_path)
  expect(page).to have_css("#fund_type_choice, #fund_name", visible: true)
end

# H5, E4: pick a card on the type page and Continue; from the fund details, "Change" goes back first
When('I choose fund type {string}') do |label|
  find("#change_fund_type").click if page.has_css?("#change_fund_type", visible: true, wait: 0)
  find("#fund_type_card_#{label == 'Open-ended' ? 'open_ended' : 'closed_end'}").click
  find("#fund_type_continue").click
  expect(page).to have_css("#fund_name", visible: true)
end

Then('I should see the fund type page with both types and Continue disabled') do
  within("#fund_type_choice") do
    expect(page).to have_content("Closed-ended")
    expect(page).to have_content("Open-ended (evergreen)")
  end
  expect(page).to have_css("#fund_type_continue[disabled]")
  expect(page).to have_no_css("#fund_name", visible: true)
end

Then('the fund details should show the type {string}') do |text|
  within("#fund_type_chosen") { expect(page).to have_content(text) }
end

When('I go back to the fund type page') do
  find("#fund_back_to_type").click
  expect(page).to have_css("#fund_type_choice", visible: true)
end

Then('the {string} card should be selected') do |label|
  expect(find("#fund_type_#{label == 'Open-ended' ? 'open_ended' : 'closed_end'}", visible: :all)).to be_checked
end

When('I fill the fund details {string} with unit types {string}') do |name, unit_types|
  fill_in("fund_name", with: name)
  select("INR", from: "fund_currency")
  fill_in("fund_unit_types", with: unit_types)
end

When('I go to step 2 of the fund') do
  within("#step-1") { click_on("Next") }
  expect(page).to have_css("#fund_back_to_step_1", visible: true)
end

When('I continue to the evergreen steps') do
  find("#fund_next_to_evergreen").click
  expect(page).to have_css("#evergreen_presets", visible: true)
end

# X1: with no unit types the form goes back to step 1 instead of opening the open-ended terms
When('I try to continue to the evergreen steps') do
  find("#fund_next_to_evergreen").click
  expect(page).to have_css("#fund_name", visible: true)
end

When('I go back to the fund details') do
  10.times do
    break if page.has_css?("#fund_name", visible: true, wait: 0)

    first(".setup-content .prevBtn", visible: true).click
  end
  expect(page).to have_css("#fund_name", visible: true)
end

When('I change the unit types to {string}') do |unit_types|
  fill_in("fund_unit_types", with: unit_types)
end

When('I create the fund') do
  evergreen_wizard_reveal("#create_fund")
  @fund_count_before = Fund.count
  click_on("create_fund")
end

# H4: Edit Fund's last step saves the fund and its open-ended terms together
When('I save the open-ended fund') do
  evergreen_wizard_reveal("#save_open_ended_fund")
  click_on("save_open_ended_fund")
  expect(page).to have_content("Fund was successfully updated.")
end

Then('the fund {string} should have classes {string} with class {string} priced {string}') do |name, classes, unit_type, price|
  fund = Fund.find_by!(name:)
  fund.reset_evergreen_cache
  terms = fund.evergreen_fund_setting.evergreen_class_terms.order(:unit_type)
  expect(terms.map(&:unit_type)).to eq(classes.split(","))
  expect(terms.find_by!(unit_type:).initial_price_cents.to_d).to eq(evergreen_cents(price))
end

# X2: Next on the Classes step with a blank starting price stays on Classes
When('I try to go past the classes step') do
  @fund_count_before = Fund.count
  within(find("#class_terms", visible: true).ancestor(".setup-content")) { find(".nextBtn").click }
  expect(page).to have_css("#class_terms", visible: true)
end

Then('the starting price of class {string} should be marked required') do |unit_type|
  within("#class_term_#{unit_type.parameterize}") do
    expect(page).to have_css("input[name$='[initial_price]'].is-invalid")
    expect(page).to have_content("Required")
  end
end

When('I save the closed-ended fund') do
  find("#save_fund").click
  expect(page).to have_content("Fund was successfully created.")
end

Then('the classes step should show the classes {string}') do |classes|
  evergreen_wizard_reveal("#class_terms")
  shown = all("#class_terms [id^='class_term_'] input[name$='[unit_type]']", visible: :all).map(&:value)
  expect(shown).to eq(classes.split(","))
end

Then('the fund {string} should be open-ended with classes {string} priced {string}') do |name, classes, price|
  fund = Fund.find_by!(name:)
  fund.reset_evergreen_cache
  expect(fund.evergreen?).to be(true)
  terms = fund.evergreen_fund_setting.evergreen_class_terms.order(:unit_type)
  expect(terms.map(&:unit_type)).to eq(classes.split(","))
  terms.each { |t| expect(t.initial_price_cents.to_d).to eq(evergreen_cents(price)) }
  @fund = fund
end

Then('the fund {string} should be closed-ended') do |name|
  fund = Fund.find_by!(name:)
  fund.reset_evergreen_cache
  expect(fund.evergreen?).to be(false)
  expect(fund.evergreen_fund_setting).to be_nil
end

Then('no fund should have been created') do
  expect(Fund.count).to eq(@fund_count_before)
  expect(EvergreenFundSetting.count).to eq(0)
end

Then('the fund type choice should not be offered') do
  expect(page).to have_css("#fund_name")
  expect(page).to have_no_css("#fund_type_choice")
end

# E1, X3, X4, X5: requests a user could send without the form
When('a request creates the fund {string} with unit types {string} and fund type {string}') do |name, unit_types, fund_type|
  session = evergreen_http_session(@user)
  @fund_count_before = Fund.count
  session.post funds_path, params: { fund_type:, fund: { name:, currency: "INR", unit_types: } }
  @http_status = session.response.status
end

Then('the request should be answered with status {int}') do |status|
  expect(@http_status).to eq(status)
end

When('a request tries to make the fund evergreen through the old settings address') do
  session = evergreen_http_session(@user)
  # No such route any more: the app answers 404 (in tests the routing error surfaces directly)
  begin
    session.post "/funds/#{@fund.id}/evergreen/settings", params: { evergreen_fund_setting: { gate_pct: 5 } }
    @http_status = session.response.status
  rescue ActionController::RoutingError
    @http_status = 404
  end
end

When('a request tries to switch the fund back through the old settings address') do
  session = evergreen_http_session(@user)
  begin
    session.delete "/funds/#{@fund.id}/evergreen/settings"
    @http_status = session.response.status
  rescue ActionController::RoutingError
    @http_status = 404
  end
end

When('I open the evergreen settings address of the closed-ended fund') do
  evergreen_visit(evergreen_settings_path(@fund))
end

Then('the fund actions should not offer {string}') do |label|
  evergreen_visit(fund_path(@fund))
  expect(page).to have_css("a.dropdown-item", visible: :all)
  expect(page).to have_no_css("a.dropdown-item", text: label, visible: :all)
end

When('I edit the fund') do
  evergreen_visit(edit_fund_path(@fund))
end

Then('the fund type should read {string}') do |text|
  expect(find("#fund_type_readonly")).to have_content(text)
end

Then('the fund should still be open-ended') do
  @fund.reload.reset_evergreen_cache
  expect(@fund.evergreen?).to be(true)
end

# H3, X2: what was typed is still in the field (Back, or the form shown again after a refusal)
Then('the {string} field should contain {string}') do |field_id, value|
  expect(find("##{field_id}", visible: :all).value).to eq(value)
end
