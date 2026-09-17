When('I visit the edit page for the fund') do
  visit(edit_fund_path(@fund))
end

Then('the tracking currency field should be disabled') do
  expect(page).to have_css("select#fund_tracking_currency[disabled]")
end

Then('the tracking currency field should not be disabled') do
  expect(page).to have_css("select#fund_tracking_currency")
  expect(page).not_to have_css("select#fund_tracking_currency[disabled]")
end

# Simulates a user bypassing the client-side "disabled" attribute (e.g. via dev tools) and
# submitting the real form - this must still be rejected server-side for non-support users.
When('I try to update the fund\'s tracking currency to {string} bypassing the disabled field') do |currency|
  visit(edit_fund_path(@fund))
  page.execute_script("document.querySelector('#fund_tracking_currency').removeAttribute('disabled')")
  select(currency, from: "fund_tracking_currency")
  click_on("Next")
  click_on("Save")
  # The submit goes through Turbo (async fetch + redirect), so click_on can return before the
  # server has finished processing/committing. Wait for the page to actually leave the edit
  # form (success -> fund show page, denial -> root) before any DB assertion runs, otherwise
  # @fund.reload can race the request and read pre-commit state.
  expect(page).to have_no_current_path(edit_fund_path(@fund))
end

Then('the tracking currency update should be denied') do
  expect(page).to have_content("Access Denied")
end

Then('the fund\'s tracking currency should still be blank') do
  expect(@fund.reload.tracking_currency).to be_blank
end

Then('the fund\'s tracking currency should be {string}') do |currency|
  expect(@fund.reload.tracking_currency).to eq(currency)
end
