# Step definitions for two_factor_*.feature

# ── Setup steps ──────────────────────────────────────────────────────────────

Given("the user has two-factor authentication enabled but not configured") do
  # two_factor_mode left nil — session controller routes to select_mode on login
  @user.update!(two_factor_enabled: true, two_factor_mode: nil)
end

Given("the user has two-factor authentication enabled and configured") do
  secret = User.generate_otp_secret
  @user.update!(two_factor_enabled: true, otp_secret: secret, two_factor_mode: "authenticator")
end

Given("the user has two-factor authentication enabled and configured with backup codes") do
  secret = User.generate_otp_secret
  @user.update!(two_factor_enabled: true, otp_secret: secret, two_factor_mode: "authenticator")
  @backup_codes = @user.generate_backup_codes!
end

Given("the user has two-factor authentication enabled in whatsapp mode") do
  secret = User.generate_otp_secret
  @user.update!(two_factor_enabled: true, otp_secret: secret, two_factor_mode: "whatsapp",
                whatsapp_enabled: true)
end

Given("the user has WhatsApp enabled") do
  @user.update!(whatsapp_enabled: true)
end

# ── Mode selection steps ─────────────────────────────────────────────────────

Then("I should be on the 2FA mode selection page") do
  expect(page).to have_current_path(select_mode_two_factor_path, wait: 10)
  expect(page).to have_content("Set Up Two-Factor Authentication")
end

Then("I should see the WhatsApp mode option") do
  expect(page).to have_content("WhatsApp")
  expect(page).to have_field("two_factor_mode", with: "whatsapp")
end

Then("I should not see the WhatsApp mode option") do
  expect(page).not_to have_field("two_factor_mode", with: "whatsapp")
end

When("I select the Authenticator mode") do
  choose("two_factor_mode", option: "authenticator")
  click_on("Continue")
end

When("I select the WhatsApp mode") do
  choose("two_factor_mode", option: "whatsapp")
  click_on("Continue")
end

# ── Authenticator enrollment steps ──────────────────────────────────────────

Then("I should be on the 2FA enrollment page") do
  expect(page).to have_current_path(enroll_two_factor_path, wait: 10)
  expect(page).to have_content("Set Up Two-Factor Authentication")
end

Then("I should see a QR code for setup") do
  expect(page).to have_css("svg", wait: 5) # QR code rendered as SVG
end

When("I enter a valid TOTP code and confirm") do
  # Generate a valid TOTP code using the user's secret
  @user.reload
  code = @user.current_otp
  fill_in("otp_code", with: code)
  click_on("Confirm & Enable 2FA")
end

When("I enter an invalid TOTP code and confirm") do
  fill_in("otp_code", with: "000000")
  click_on("Confirm & Enable 2FA")
end

Then("I should see backup codes") do
  expect(page).to have_content("Backup Codes")
  expect(page).to have_content("Continue to Dashboard")
end

Then("the user should have 2FA enabled in authenticator mode") do
  @user.reload
  expect(@user.two_factor_enabled).to be true
  expect(@user.two_factor_mode).to eq("authenticator")
  expect(@user.otp_secret).not_to be_nil
  expect(@user.otp_backup_codes).not_to be_nil
end

Then("I should still be on the enrollment page") do
  expect(page).to have_current_path(verify_enrollment_two_factor_path, wait: 5)
end

# ── WhatsApp enrollment steps ────────────────────────────────────────────────

Then("I should be on the WhatsApp 2FA enrollment page") do
  expect(page).to have_current_path(enroll_whatsapp_two_factor_path, wait: 10)
  expect(page).to have_content("Confirm Your WhatsApp")
end

When("I enter the WhatsApp OTP to confirm enrollment") do
  # WhatsApp delivery is stubbed in tests; read current TOTP from the secret directly
  @user.reload
  code = @user.current_otp
  fill_in("otp_code", with: code)
  click_on("Confirm & Enable 2FA")
end

Then("I should see the resend WhatsApp code button") do
  expect(page).to have_button("Didn't get it? Resend code via WhatsApp")
end

When("I click the resend WhatsApp code button") do
  click_on("Didn't get it? Resend code via WhatsApp")
  expect(page).to have_css("#whatsapp-status", visible: :visible, wait: 10)
end

# enroll_whatsapp has just sent a code, so the 30-second server-side cooldown in
# send_whatsapp is still running — the resend is refused with the wait message. That is
# the honest thing to assert here: the button is wired and the endpoint answered.
Then("I should see the WhatsApp resend cooldown message") do
  expect(page).to have_css("#whatsapp-status", text: "Please wait 30 seconds", wait: 10)
end

Then("the user should have 2FA enabled in whatsapp mode") do
  @user.reload
  expect(@user.two_factor_enabled).to be true
  expect(@user.two_factor_mode).to eq("whatsapp")
  expect(@user.otp_secret).not_to be_nil
  # WhatsApp mode has no backup codes
  expect(@user.otp_backup_codes).to be_nil.or(eq("[]"))
end

# ── Login verification steps ─────────────────────────────────────────────────

Then("I should be on the 2FA verification page") do
  expect(page).to have_current_path(new_two_factor_path, wait: 10)
  expect(page).to have_content("Two-Factor Authentication")
end

When("I enter a valid TOTP code") do
  @user.reload
  code = @user.current_otp
  fill_in("otp_code", with: code)
  click_on("Verify")
end

When("I enter the WhatsApp OTP to verify") do
  # WhatsApp delivery is stubbed; TOTP secret is set so current_otp gives the same code
  @user.reload
  code = @user.current_otp
  fill_in("otp_code", with: code)
  click_on("Verify")
end

When("I enter an invalid TOTP code") do
  fill_in("otp_code", with: "000000")
  click_on("Verify")
end

When("I enter an invalid TOTP code {int} times") do |count|
  count.times do
    fill_in("otp_code", with: "000000")
    click_on("Verify")
    # Wait for page to reload between attempts
    sleep(0.5) unless count == 1
  end
end

Then("I should be redirected to the login page") do
  expect(page).to have_current_path(new_user_session_path, wait: 10)
end

Then("I should not be on the 2FA verification page") do
  expect(page).not_to have_content("Two-Factor Authentication")
end

# ── Backup code steps ────────────────────────────────────────────────────────

When("I enter a valid backup code") do
  fill_in("otp_code", with: @backup_codes.first)
  click_on("Verify")
end

When("I enter an invalid backup code") do
  fill_in("otp_code", with: "INVALID-CODE")
  click_on("Verify")
end

Then("the backup code should be consumed") do
  @user.reload
  remaining = JSON.parse(@user.otp_backup_codes || "[]")
  expect(remaining.size).to eq(7) # 8 original - 1 consumed
end
