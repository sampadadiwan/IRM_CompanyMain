# Steps for features/security/user_phone_change.feature
# (User#existing_phone_change_must_be_verified, PhoneChangeStart, PhoneChangeConfirm).

# Emails carrying a phone change code to `email`. Cucumber runs jobs inline, so
# SendPhoneChangeCodeJob has already sent it by the time the request returns.
def phone_change_code_emails(email)
  ActionMailer::Base.deliveries.select do |m|
    m.to.include?(email) && m.subject == "Confirm your mobile number change"
  end
end

# The 6-digit code from the newest code email to `email` (the big, letter-spaced line).
def emailed_phone_change_code(email)
  mail = phone_change_code_emails(email).last
  expect(mail).to be_present
  mail.body.encoded[/letter-spacing:4px;">\s*(\d{6})\s*</, 1]
end

# A 6-digit code that is guaranteed not to be the emailed one.
def wrong_phone_change_code(email)
  format("%06d", (emailed_phone_change_code(email).to_i + 1) % 1_000_000)
end

Given('{string} has no phone number yet') do |email|
  # Fixture setup: clear the number without the emailed-code path.
  User.find_by!(email:).update_columns(phone: nil)
end

Given('there is a colleague {string}') do |kv|
  # build, not create: key_values sets email and phone, both guarded once the user is saved.
  colleague = FactoryBot.build(:user, entity: @entity)
  key_values(colleague, kv)
  colleague.save!
end

When('I ask to change the phone of {string} to {string} with call code {string}') do |email, phone, call_code|
  # The "Send Code" button in users/_change_phone_modal posts exactly this.
  page.driver.submit :post, user_phone_change_path(User.find_by!(email:)), { call_code:, phone: }
end

When('I enter the emailed code for {string}') do |email|
  # Through the real "enter the code" page.
  visit user_phone_change_path(User.find_by!(email:))
  fill_in "phone_change_code", with: emailed_phone_change_code(email)
  click_on "Confirm Change"
end

When('I submit the emailed code for {string}') do |email|
  # Straight PATCH: the code page itself redirects away once no change is waiting.
  page.driver.submit :patch, user_phone_change_path(User.find_by!(email:)), { code: emailed_phone_change_code(email) }
end

When('I enter a wrong code for {string}') do |email|
  page.driver.submit :patch, user_phone_change_path(User.find_by!(email:)), { code: wrong_phone_change_code(email) }
end

When('I enter a wrong code for {string} {int} times') do |email, times|
  times.times { step %(I enter a wrong code for "#{email}") }
end

When('the phone change code for {string} has expired') do |email|
  # Expiry is checked before the code, so the digest no longer matching does not matter.
  User.find_by!(email:).phone_change_requests.pending.last.update_columns(expires_at: 1.minute.ago)
end

When('the last phone change for {string} was requested {int} minutes ago') do |email, minutes|
  # Moves the request out of the one-minute resend cooldown.
  User.find_by!(email:).phone_change_requests.last.update_columns(created_at: minutes.minutes.ago)
end

When('I keep the emailed code for {string}') do |email|
  @kept_phone_change_code = emailed_phone_change_code(email)
end

When('I submit the kept code for {string}') do |email|
  page.driver.submit :patch, user_phone_change_path(User.find_by!(email:)), { code: @kept_phone_change_code }
end

When('I update my own user with phone {string} and call code {string}') do |phone, call_code|
  # Straight PATCH to UsersController#update, as a crafted request would.
  page.driver.submit :patch, user_path(@user), { user: { phone:, call_code:, first_name: @user.first_name } }
end

When('I visit the user page of {string}') do |email|
  visit user_path(User.find_by!(email:))
end

When('I visit the edit page of {string}') do |email|
  visit edit_user_path(User.find_by!(email:))
end

When('the user {string} is saved with phone {string}') do |email, phone|
  @phone_user = User.find_by!(email:)
  @phone_save_result = @phone_user.update(phone:)
end

When('the user {string} is synced with phone {string}') do |email, phone|
  # What UsersSyncController#apply_user! does for a payload from the origin region.
  user = User.find_by!(email:)
  user.skip_phone_change_verification!
  user.update!(phone:)
end

Then('a phone change code is emailed to {string}') do |email|
  expect(emailed_phone_change_code(email)).to match(/\A\d{6}\z/)
end

Then('{int} phone change code(s) is/are emailed to {string}') do |count, email|
  expect(phone_change_code_emails(email).size).to eq(count)
end

Then('a {string} email is sent to {string}') do |subject, email|
  expect(ActionMailer::Base.deliveries.any? { |m| m.to.include?(email) && m.subject == subject }).to be true
end

Then('the phone of {string} is (still ){string}') do |email, phone|
  expect(User.find_by!(email:).phone).to eq(phone)
end

Then('the phone save fails with {string}') do |message|
  expect(@phone_save_result).to be false
  expect(@phone_user.errors.full_messages).to include(message)
end

Then('the phone save succeeds') do
  expect(@phone_save_result).to be true
end

Then('I should see the change phone button') do
  expect(page).to have_css("#change_phone_button")
end

Then('the phone fields are disabled') do
  expect(page).to have_field("user[phone]", disabled: true)
  expect(page).to have_field("user[call_code]", disabled: true)
end
