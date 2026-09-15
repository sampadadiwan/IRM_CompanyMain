When('I visit the new investment instrument page') do
  # Mirrors the real "New" link in investment_instruments/_index.html.erb, which always sends
  # investment_instrument[entity_id] - the controller's `new` action requires the
  # investment_instrument param key to be present at all (ActionController::ParameterMissing
  # otherwise), so a bare /investment_instruments/new visit isn't a state the UI ever produces.
  visit(new_investment_instrument_path("investment_instrument[entity_id]": @user.entity_id))
end

When('I visit the new investment instrument page for that portfolio company') do
  visit(new_investment_instrument_path("investment_instrument[portfolio_company_id]": @portfolio_company.id))
end

Then('the {string} field should not be locked') do |label|
  expect(page).to have_select(label, disabled: false)
end

Then('the {string} field should be locked to {string}') do |label, selected_option|
  expect(page).to have_select(label, disabled: true, selected: selected_option)
end

Then('the {string} field should offer {string} and {string} as choices') do |label, option_one, option_two|
  expect(page).to have_select(label, with_options: [option_one, option_two])
end

When('I fill in the investment instrument name as {string} and save') do |name|
  fill_in "investment_instrument_name", with: name
  click_on "Save"
end

Then('the investment instrument should have been created for the portfolio company {string}') do |portfolio_company_name|
  instrument = InvestmentInstrument.order(:id).last
  expect(page).to have_content("Investment instrument was successfully created")
  expect(instrument.portfolio_company&.investor_name).to eq(portfolio_company_name)
end
