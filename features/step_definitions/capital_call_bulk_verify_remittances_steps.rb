# Step definitions for bulk-verifying remittances from the capital call show page

When('I visit the capital call remittances tab') do
  visit(capital_call_url(@capital_call))
  click_on "Remittances"
end

When('I open the bulk verify remittances modal for the capital call') do
  step 'I visit the capital call remittances tab'
  click_on "Verify Pending Remittances"
end

Then('the bulk verify modal should contain {string}') do |text|
  expect(page).to have_css('#bulkVerifyRemittancesModal', visible: true)
  within('#bulkVerifyRemittancesModal') do
    expect(page).to have_content(text)
  end
end

When('I confirm the bulk verify remittances action') do
  within('#bulkVerifyRemittancesModal') do
    click_on "Verify Remittances"
  end
end

When('I bulk verify pending remittances for the capital call') do
  step 'I open the bulk verify remittances modal for the capital call'
  step 'I confirm the bulk verify remittances action'
end

Then('all remittances for the capital call should be verified') do
  # Re-visit the page fresh on every retry (rather than reloading in-process AR objects,
  # or trusting Capybara's own auto-wait against an already-loaded static page) so this
  # assertion checks exactly what a real user would see, and actually re-fetches from the
  # server each attempt. `wait: 0` on `have_content` is required here: without it, Capybara's
  # own internal wait (up to Capybara.default_max_wait_time) polls the *static* page DOM,
  # which can never change on its own, and swallows the entire retry budget on the very
  # first attempt -- leaving `eventually` no time left to re-visit and see the updated state.
  remittance_ids = @capital_call.capital_remittances.pluck(:id)
  eventually do
    visit(capital_call_url(@capital_call))
    click_on "Remittances"
    remittance_ids.each do |id|
      within("#capital_remittance_#{id}") do
        expect(page).to have_content("Yes", wait: 0)
      end
    end
  end
end

Then('I should not see the {string} button on the remittances tab') do |text|
  expect(page).not_to have_button(text)
end
