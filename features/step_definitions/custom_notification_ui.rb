Given('I open the fund notifications tab') do
  visit(fund_path(@fund))
  click_on("Notifications")
  expect(page).to have_content("Custom Notifications")
end

Given('I open the capital call notifications tab') do
  @capital_call = CapitalCall.last if @capital_call.nil? || @capital_call.id.blank?
  visit(capital_call_path(@capital_call))
  click_on("Notification")
  expect(page).to have_content("Custom Notifications")
end

Given('I open the capital distribution notifications tab') do
  @capital_distribution = CapitalDistribution.last if @capital_distribution.nil? || @capital_distribution.id.blank?
  visit(capital_distribution_path(@capital_distribution))
  click_on("Notification")
  expect(page).to have_content("Custom Notifications")
end

Given('I open the new notification dropdown') do
  click_on("New Notification") unless page.has_css?(".dropdown-menu.show", visible: true)
end

When('I click {string} in the new notification dropdown') do |option|
  step 'I open the new notification dropdown'
  click_on(option)
end

Then('the new notification dropdown should offer {string}') do |option|
  step 'I open the new notification dropdown'
  expect(page).to have_link(option)
end

Then('the new notification dropdown should not offer {string}') do |option|
  step 'I open the new notification dropdown'
  expect(page).not_to have_link(option)
end

Then('the custom notification form should target owner_type {string} and for_type {string}') do |owner_type, for_type|
  expect(find("#custom_notification_owner_type", visible: false).value).to eq(owner_type)
  expect(find("#custom_notification_for_type", visible: false).value).to eq(for_type)
end

Then('the custom notification form title should include {string}') do |text|
  expect(page).to have_content(text)
end

When('I select {string} as the notification email type') do |label|
  select(label, from: "custom_notification_email_method")
end

Then('I should see a warning that the fund default will be overridden') do
  expect(page).to have_content("this fund already has a default notification for this email", wait: 5)
end

Then('I should not see a warning about overriding the fund default') do
  expect(page).not_to have_content("this fund already has a default notification for this email")
end

# Latest Match Only / Attachment Mandatory only make sense once attachment_names has a value —
# see the conditional-visibility controller wired up in custom_notifications/_form.html.erb
Then('the attachment checkboxes should be hidden') do
  expect(page).not_to have_field("custom_notification_latest_doc_only")
  expect(page).not_to have_field("custom_notification_attachment_mandatory")
end

Then('the attachment checkboxes should be visible') do
  expect(page).to have_field("custom_notification_latest_doc_only", wait: 5)
  expect(page).to have_field("custom_notification_attachment_mandatory")
end
