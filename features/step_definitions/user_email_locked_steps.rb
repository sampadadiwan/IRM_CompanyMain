# Steps for features/security/user_email_locked.feature (User#email_cannot_change).

When('I update my own user with email {string} and first name {string}') do |email, first_name|
  # Straight PATCH to UsersController#update, the path the users form and JSON API share.
  page.driver.submit :patch, user_path(@user), { user: { email:, first_name: } }
end

When('I submit the account edit form with email {string}') do |email|
  # Devise::RegistrationsController#update; account_update params permit email by default.
  page.driver.submit :put, user_registration_path, { user: { email:, current_password: "password" } }
end

When('my user is saved with email {string}') do |email|
  @save_result = @user.reload.update(email:)
end

When('my user is saved with first name {string}') do |first_name|
  @save_result = @user.reload.update(first_name:)
end

Given('my user\'s email is stored as {string}') do |email|
  # update_column skips validations and Devise's normalisation, recreating a legacy row.
  @user.update_column(:email, email)
end

Then('the save fails with {string}') do |message|
  expect(@save_result).to be false
  expect(@user.errors.full_messages).to include(message)
end

Then('the save succeeds') do
  expect(@save_result).to be true
end

Then('my user\'s email is still {string}') do |email|
  expect(@user.reload.email).to eq(email)
end

Then('my user\'s first name is {string}') do |first_name|
  expect(@user.reload.first_name).to eq(first_name)
end
