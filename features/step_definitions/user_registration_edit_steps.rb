# Step definitions for features/login/user_registration_edit.feature
#
# Regression for WithAuthentication#authenticate_user! raising ArgumentError
# on Devise::RegistrationsController#edit (authenticate_scope! calls
# authenticate_user!(force: true), which a 0-arg override can't accept).

When('I visit the account edit page') do
  visit edit_user_registration_path
end

Then('I should not see an application error') do
  # The custom devise/registrations/edit view (app/packs/core/users/views/devise/registrations/edit.html.erb)
  # renders an "Edit User" heading and the email field — asserting on real
  # page content, not just "didn't raise", so a future template regression
  # would also be caught here.
  expect(page).to have_content("Edit User")
  expect(page).to have_css("#user_email")
end
