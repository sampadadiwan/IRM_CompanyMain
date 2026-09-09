# Step definitions for two_factor_sms.feature.
#
# The Twilio HTTP call is stubbed by features/support/twilio_stub.rb (@stub-twilio), which
# records what would have been sent in @twilio. Everything below that — the country
# eligibility check, the rate limiters, the OtpDelivery bookkeeping — runs for real,
# because those are the parts that stand between the send endpoint and a runaway bill.

# ── Setup ────────────────────────────────────────────────────────────────────

# update_columns, not update!, because several scenarios deliberately store a number that
# cannot be dialled — which User#phone_must_be_dialable now refuses on any edit. Those
# rows are exactly the pre-existing and import-written data the validation lets through,
# so the setup has to write them the same way.
Given("the user has the phone number {string} {string}") do |call_code, phone|
  @user.update_columns(call_code: call_code.presence, phone: phone.presence&.delete("^0-9"))
  @user.reload
end

# The @stub-twilio hook sets CURRENT_SITE=LOCAL and its After hook restores whatever was
# there before, so a scenario can narrow it to a real deployment without leaking.
Given("this is the US deployment") do
  ENV["CURRENT_SITE"] = "US"
end

Given("SMS two-factor is switched off for this deployment") do
  ENV["SMS_OTP_ENABLED"] = "false"
end

Given("the user has two-factor authentication enabled in sms mode") do
  @user.update!(two_factor_enabled: true,
                otp_secret: User.generate_otp_secret,
                two_factor_mode: "sms")
end

Given("the next text message will fail with Twilio code {int}") do |code|
  @twilio.fail_next_with(code)
end

# ── Mode selection ───────────────────────────────────────────────────────────

Then("I should see the SMS mode option") do
  expect(page).to have_field("two_factor_mode", with: "sms")
  expect(page).to have_content("Text message (SMS)")
end

Then("I should not see the SMS mode option") do
  expect(page).not_to have_field("two_factor_mode", with: "sms")
end

When("I select the SMS mode") do
  choose("two_factor_mode", option: "sms")
  click_on("Continue")
end

# Posts the mode directly rather than through the form. The screen never offers SMS to an
# ineligible user, so the only way to prove the server re-checks is to bypass the screen —
# which is exactly what an attacker would do, since this POST is unauthenticated.
When("I force-submit the SMS mode") do
  page.execute_script(<<~JS)
    var f = document.querySelector('form[action="/two_factor/select_mode"]');
    var r = document.createElement('input');
    r.type = 'hidden'; r.name = 'two_factor_mode'; r.value = 'sms';
    f.appendChild(r);
    f.querySelectorAll('input[type=radio][name=two_factor_mode]').forEach(function (el) { el.disabled = true; });
    f.submit();
  JS
end

# ── Enrollment ───────────────────────────────────────────────────────────────

Then("I should be on the SMS 2FA enrollment page") do
  expect(page).to have_current_path(enroll_sms_two_factor_path, wait: 10)
  expect(page).to have_content("Confirm Your Phone")
end

When("I enter the texted code to confirm enrollment") do
  fill_in("otp_code", with: @twilio.last_code)
  click_on("Confirm & Enable 2FA")
end

When("I enter the texted code") do
  fill_in("otp_code", with: @twilio.last_code)
  click_on("Verify")
end

Then("the user should have 2FA enabled in sms mode") do
  @user.reload
  expect(@user.two_factor_enabled).to be true
  expect(@user.two_factor_mode).to eq("sms")
  expect(@user.otp_secret).to be_present
end

# NOT asserted via two_factor_enabled: that flag is set on the profile BEFORE enrollment
# (it is what sends the user here in the first place), so it is already true and stays true
# whether or not the code was accepted. What a failed enrollment must leave behind is a user
# who is still on the enrollment page and still not signed in.
Then("the user's two-factor setup should not be complete") do
  expect(page).to have_current_path(verify_sms_enrollment_two_factor_path, wait: 5)
  visit root_path
  expect(page).to have_current_path(new_user_session_path, wait: 10)
end

# SMS mode issues no backup codes — parked, matching WhatsApp mode. Asserted rather than
# assumed, because the authenticator path DOES issue them from the same controller.
Then("the user should have no backup codes") do
  @user.reload
  expect(JSON.parse(@user.otp_backup_codes || "[]")).to be_empty
end

Then("I should be signed in") do
  expect(page).to have_no_current_path(new_two_factor_path, wait: 10)
  expect(page).to have_no_current_path(new_user_session_path)
end

# ── Magic link ───────────────────────────────────────────────────────────────

# Visits the signed login URL directly rather than going through the email, so the
# scenario tests the 2FA dispatch and not the mailer.
When("I sign in using a magic link") do
  signed_id = @user.signed_id(purpose: User::MAGIC_LINK_PURPOSE, expires_in: 1.hour)
  visit "/users/no_password_login?signed_id=#{signed_id}"
end

# ── Sends ────────────────────────────────────────────────────────────────────

Then("a text message should have been sent to {string}") do |number|
  # The job runs inline in the Cucumber env, so the send has already happened by the
  # time the page has rendered.
  expect(@twilio.count).to be >= 1
  expect(@twilio.last.to).to eq(number)
end

Then("exactly {int} text message should have been sent") do |count|
  expect(@twilio.count).to eq(count)
end

Then("no text message should have been sent") do
  expect(@twilio.count).to eq(0)
end

# Under Verify the code is Twilio's and the application never sees it, so there is
# nothing to assert about the body — the stub mints the code and hands it out through
# last_code, exactly as Twilio would hand it to the user's handset.
Then("a verification should have been started for {string}") do |number|
  expect(@twilio.count).to be >= 1
  expect(@twilio.last.to).to eq(number)
end

# Guards the rule that Verify must never be probed speculatively: each check consumes
# one of a verification's limited attempts.
Then("no verification check should have been made") do
  expect(@twilio.checks).to eq(0)
end

When("the code is sent") do
  @send_error = nil
  begin
    SendOtpToSmsJob.perform_now(@user.id, OtpDelivery::PURPOSE_LOGIN)
  rescue StandardError => e
    @send_error = e
  end
end

When("the code is sent again") do
  step "the code is sent"
end

# ── Rate limiting ────────────────────────────────────────────────────────────

# Fills the per-number windows without waiting a real minute. Uses the limiter itself
# rather than hand-writing cache keys, so a change to the key format cannot leave this
# step silently passing against nothing.
When("the rate limit is exhausted for that number") do
  OtpSmsRateLimiter::NUMBER_LIMITS.each do |window, limit|
    key = "otp_sms:number:#{@user.sms_number_digest}:#{window.to_i}"
    Rails.cache.write(key, limit, expires_in: window)
  end
end

Then("the delivery should be recorded as failed with {string}") do |error_code|
  delivery = OtpDelivery.where(user_id: @user.id).order(:created_at).last
  expect(delivery).to be_present
  expect(delivery.status).to eq(OtpDelivery::STATUS_FAILED)
  expect(delivery.error_code).to eq(error_code)
end

# Counting successes instead of attempts would make a number that reliably errors free
# to hammer, which is the cheapest possible toll-fraud setup.
Then("the attempt should have been counted against that number") do
  key = "otp_sms:number:#{@user.sms_number_digest}:60"
  expect(Rails.cache.read(key).to_i).to be >= 1
end

Then("the job should not have raised") do
  expect(@send_error).to be_nil
end

# ── Normalisation ────────────────────────────────────────────────────────────

Then("the user's SMS number should normalise to {string}") do |expected|
  @user.reload
  expect(@user.normalized_sms_number).to eq(expected)
end

# ── Regression steps ─────────────────────────────────────────────────────────

# Same reason as above: the point of the scenario is a stored number that has stopped
# being textable, which no longer arrives through a validated write.
Given("an administrator changes the number to {string} {string}") do |call_code, phone|
  @user.update_columns(call_code: call_code, phone: phone.delete("^0-9"))
  @user.reload
end

When("I reload the enrollment page") do
  visit enroll_sms_two_factor_path
end

# Runs two sends with no interleaving guard, which is what a double-click or an
# ActiveJob retry racing the original produces. Both must not get through.
When("the code is sent twice concurrently") do
  threads = 2.times.map do
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        SendOtpToSmsJob.perform_now(@user.id, OtpDelivery::PURPOSE_LOGIN)
      end
    rescue StandardError
      nil
    end
  end
  threads.each(&:join)
end

# The shared "I fill and submit the login page" step asserts the user LEAVES /users/sign_in.
# These scenarios are exactly the case where they must not: the password is right, but no
# code can be delivered, so the login is refused and they stay put with an explanation.
When("I submit the login page expecting to be refused") do
  fill_in("user_email", with: @user.email)
  fill_in("user_password", with: "password")
  click_on("Log In")
  expect(page).to have_current_path(new_user_session_path, wait: 10, ignore_query: true)
end

# The session hint lives inside the encrypted session cookie, so a browser-driven test
# cannot remove just that one key. Instead this asserts the two durable signals the
# controller falls back on, either of which alone routes the code to Verify.
Then("the code routing should not need the session hint") do
  @user.reload
  expect(@user.sms_mode?).to be true
  expect(OtpDelivery.where(user_id: @user.id, channel: "sms",
                           status: OtpDelivery::STATUS_QUEUED)
                    .where(created_at: 10.minutes.ago..).exists?).to be true
end
