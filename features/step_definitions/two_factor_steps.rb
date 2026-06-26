# Step definitions for two_factor_*.feature

Given("the user has two-factor authentication enabled but not configured") do
  @user.update!(two_factor_enabled: true)
  # otp_secret is nil — will be generated on enrollment page
end

Given("the user has two-factor authentication enabled and configured") do
  secret = User.generate_otp_secret
  @user.update!(two_factor_enabled: true, otp_secret: secret)
end

Given("the user has two-factor authentication enabled and configured with backup codes") do
  secret = User.generate_otp_secret
  @user.update!(two_factor_enabled: true, otp_secret: secret)
  @backup_codes = @user.generate_backup_codes!
end

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

Then("the user should have 2FA enabled") do
  @user.reload
  expect(@user.two_factor_enabled).to be true
  expect(@user.otp_secret).not_to be_nil
  expect(@user.otp_backup_codes).not_to be_nil
end

Then("I should still be on the enrollment page") do
  expect(page).to have_current_path(verify_enrollment_two_factor_path, wait: 5)
end

# ── Verification steps ──────────────────────────────────────────────────────

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

# ── Backup code steps ───────────────────────────────────────────────────────

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
  remaining = JSON.parse(@user.otp_backup_codes || '[]')
  expect(remaining.size).to eq(7) # 8 original - 1 consumed
end
