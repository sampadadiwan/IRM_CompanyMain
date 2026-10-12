# Steps for features/fund/evergreen/wording.feature (E212–E215)

# rack_test: every following request reports this browser locale, which WithLocale reads
Given('the browser asks for the locale {string}') do |locale|
  page.driver.header("Accept-Language", locale)
end

Given("the fund's investors hold {string}") do |unit|
  @fund.evergreen_fund_setting.update!(unit_term: unit)
end

# "unit=share;capital_commitment=Account" → entity_settings.evergreen_labels
Given("the entity's open-ended fund wording is {string}") do |values|
  labels = values.split(";").to_h { |pair| pair.split("=", 2) }
  setting = @fund.entity.entity_setting || @fund.entity.build_entity_setting
  setting.update!(evergreen_labels: labels)
end

Then('the evergreen tab {string} should be shown') do |label|
  expect(page).to have_css("#evergreen_tabs a", text: label, visible: :all)
end
