# Steps for features/fund/evergreen/settings.feature and regression.feature.
# Worked examples H1, H2, X1–X4, E1, E47 — openspec/changes/open-ended-funds/design.md#worked-examples

Given('the entity has evergreen funds switched on') do
  enable_evergreen_for(@user.entity)
end

Given('the fund is evergreen') do
  make_fund_evergreen(@fund, @user)
end

Given('the fund is evergreen with {string}') do |settings|
  make_fund_evergreen(@fund, @user, evergreen_kv(settings))
end

When('I open the evergreen settings of the fund') do
  evergreen_visit(evergreen_settings_path(@fund))
end

When('I set the initial price of class {string} to {string}') do |unit_type, price|
  evergreen_wizard_reveal("#class_term_#{unit_type.parameterize}")
  within("#class_term_#{unit_type.parameterize}") do
    find("input[name$='[initial_price]']").fill_in(with: price)
  end
end

When('I save the evergreen settings') do
  evergreen_wizard_reveal("#save_evergreen_settings")
  click_on("save_evergreen_settings")
end

When('I set the evergreen field {string} to {string}') do |field, value|
  evergreen_wizard_reveal("[name='evergreen_fund_setting[#{field}]']")
  fill_in("evergreen_fund_setting[#{field}]", with: value)
end

When('I clear every redemption form') do
  evergreen_wizard_reveal("#redemption_form_units")
  %w[units amount all].each { |f| uncheck("redemption_form_#{f}") }
end

# X3: Next on Redemptions with no way to redeem stays on Redemptions
When('I try to go past the redemptions step') do
  @redemption_forms_before = @fund.evergreen_fund_setting.reload.redemption_forms
  within(find("#redemption_form_units").ancestor(".setup-content")) { find(".nextBtn").click }
  expect(page).to have_css("#redemption_form_units", visible: true)
end

Then('the ways to redeem should be marked {string}') do |text|
  within(find("#redemption_form_units").ancestor("[data-eg-required-group]")) { expect(page).to have_content(text) }
end

Then("the fund's redemption forms should be unchanged") do
  expect(@fund.evergreen_fund_setting.reload.redemption_forms).to eq(@redemption_forms_before)
end

When('I pick the preset {string}') do |key|
  evergreen_wizard_reveal("#evergreen_preset_#{key}")
  find("#evergreen_preset_#{key}").click
  expect(page).to have_css("#preset_summary_#{key}", text: "✓")
end

Then('the fund should be evergreen with the default settings') do
  @fund.reload.reset_evergreen_cache
  expect(@fund.evergreen?).to be(true)
  s = @fund.evergreen_fund_setting
  expect([s.subscription_calendar, s.redemption_calendar, s.dealing_day, s.payment_timing]).to eq(%w[monthly quarterly first before])
  expect([s.subscription_cutoff_days, s.unready_handling, s.order_journeys, s.redemption_settlement_days]).to eq([5, "roll", "off", 10])
  expect(s.redemption_forms).to match_array(%w[units amount all])
  expect([s.gate_pct.to_d, s.gate_level, s.gate_period, s.gate_method, s.investor_gate_pct.to_d]).to eq([0, "fund", "dealing_date", "pro_rata", 0])
  expect(s.evergreen_class_terms.find_by(unit_type: "A").initial_price_cents).to eq(1_000_000)
end

Then('the fund should not be evergreen') do
  @fund.reload.reset_evergreen_cache
  expect(@fund.evergreen?).to be(false)
end

Then('the settings form should show {string} as {string}') do |field, value|
  expect(page).to have_field("evergreen_fund_setting[#{field}]", with: value, visible: :all)
end

Then('the settings form should select {string} for {string}') do |value, field|
  expect(page).to have_select("evergreen_fund_setting[#{field}]", selected: value, visible: :all)
end

Given('the fund has a confirmed dealing date on {string}') do |date|
  d = Date.parse(date)
  DealingDate.create!(entity_id: @fund.entity_id, fund: @fund, date: d, cutoff_at: d - 5.days, payment_timing: "before",
                      has_subscriptions: true, status: "confirmed", confirmed_at: Time.current)
end

When('I press {string} and accept the popup') do |label|
  accept_confirm { click_on(label) }
end

# Regression (E1, E47)
When('I open the fund page') do
  evergreen_visit(fund_path(@fund))
end

Then('I should see the closed-ended fund page') do
  expect(page).to have_content(@fund.name)
  expect(page).not_to have_css("#evergreen_tabs")
end

Then('the fund actions should not offer evergreen') do
  expect(page).not_to have_content("Make this fund evergreen")
end

When('I request the evergreen settings page directly') do
  evergreen_visit(evergreen_settings_path(@fund))
end

Then('I should not see the evergreen settings form') do
  expect(page).not_to have_css("#save_evergreen_settings")
end
