# Steps for: features/core/custom_field_step_visibility.feature

When('I visit the edit page for the capital commitment') do
  visit(edit_capital_commitment_path(@capital_commitment))
end

Then('I should see a field labelled {string}') do |label|
  expect(page).to have_field(label)
end

When('I fill in the field labelled {string} with {string} and save') do |label, value|
  fill_in(label, with: value)
  click_on("Save")
  expect(page).to have_no_current_path(edit_capital_commitment_path(@capital_commitment))
end

Then('the capital commitment custom field {string} should be {string}') do |name, value|
  expect(@capital_commitment.reload.properties[name]).to eq(value)
end

Then('the field labelled {string} should contain {string}') do |label, value|
  expect(page).to have_field(label, with: value)
end
