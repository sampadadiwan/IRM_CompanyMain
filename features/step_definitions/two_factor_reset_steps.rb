# Step definitions for features/login/two_factor_method_reset.feature
#
# Shared setup steps (user creation, TOTP enrollment/verification, mode selection) live in
# two_factor_steps.rb and features/common.rb — only reset-specific steps are defined here.

# ── Setup ─────────────────────────────────────────────────────────────────────

Given("the user is a company admin") do
  @user.add_role(:company_admin)
end

# A second user in @entity already enrolled in WhatsApp mode — the target of admin resets.
Given("there is a colleague {string} in the same entity using WhatsApp two-factor") do |kv|
  @colleague = FactoryBot.build(:user, entity: @entity)
  key_values(@colleague, kv)
  @colleague.save!
  @colleague.update!(two_factor_enabled: true,
                     otp_secret: User.generate_otp_secret,
                     two_factor_mode: "whatsapp",
                     whatsapp_enabled: true)
end

# ── Navigation ────────────────────────────────────────────────────────────────

When("I visit my own user page") do
  visit user_path(@user)
  expect(page).to have_content("Two-Factor Authentication", wait: 10)
end

When("I visit the colleague's user page") do
  visit user_path(@colleague)
  expect(page).to have_content("Two-Factor Authentication", wait: 10)
end

# "I log out" is the shared step in login.rb (profile menu → Log Out → Logout).

When("I log in as the colleague") do
  visit new_user_session_path
  fill_in("user_email", with: @colleague.email)
  fill_in("user_password", with: "password")
  click_on("Log In")
end

# ── User page assertions ──────────────────────────────────────────────────────

Then("I should see the two-factor method badge {string}") do |label|
  expect(page).to have_css("#two_factor_mode_badge", text: label, wait: 10)
end

Then("I should see the {string} two-factor button") do |label|
  expect(page).to have_button(label)
end

# ── Modal ─────────────────────────────────────────────────────────────────────

When("I open the reset two-factor modal") do
  find("#reset_two_factor_button").click
  # Bootstrap animates the modal in; wait until the effects list is actually visible.
  expect(page).to have_css("#resetTwoFactorModal.show #reset_two_factor_effects", wait: 10)
end

Then("the reset modal should warn me about the consequences of a self reset") do
  within("#resetTwoFactorModal") do
    expect(page).to have_content("Immediate Actions")
    expect(page).to have_content("Current method removed")
    expect(page).to have_content("You will be signed out now")
    expect(page).to have_content("Two-factor authentication stays switched on")
    expect(page).to have_content("Confirmation email sent")
    expect(page).to have_content("Before you continue, have ready")
    expect(page).to have_field("password", type: "password")
    expect(page).to have_unchecked_field("reset_two_factor_acknowledge")
  end
end

Then("the reset modal should warn me about the consequences of an admin reset") do
  within("#resetTwoFactorModal") do
    expect(page).to have_content("Immediate Actions")
    expect(page).to have_content("Current method removed")
    expect(page).to have_content("Takes effect at their next sign-in")
    expect(page).to have_content("Two-factor authentication stays switched on")
    expect(page).to have_content("Verify the request is genuine")
    expect(page).to have_field("message")
    # No password step-up for administrators
    expect(page).not_to have_field("password", type: "password")
  end
end

Then("the reset submit button should be disabled") do
  expect(page).to have_button("Reset 2FA Method", disabled: true)
end

When("I confirm the self-service reset with password {string}") do |password|
  within("#resetTwoFactorModal") do
    fill_in("password", with: password)
    check("reset_two_factor_acknowledge")
    # The Stimulus controller enables the button once both inputs are filled in.
    expect(page).to have_button("Reset 2FA Method", disabled: false, wait: 5)
    click_on("Reset 2FA Method")
  end
end

When("I confirm the admin reset with message {string}") do |message|
  within("#resetTwoFactorModal") do
    fill_in("message", with: message)
    click_on("Reset 2FA Method")
  end
end

# Bypasses the UI: an unauthorised user must be refused by UserPolicy#reset_two_factor?
# even when they hand-craft the POST. Uses the browser session so the CSRF token is valid.
When("I post a two-factor reset for the colleague directly") do
  visit user_path(@user) # any signed-in page, so the DOM carries a CSRF token
  page.execute_script(<<~JS)
    (async () => {
      const token = document.querySelector('meta[name="csrf-token"]')?.content || '';
      const body = new FormData();
      body.append('authenticity_token', token);
      try {
        const r = await fetch('#{reset_two_factor_user_path(@colleague)}', {
          method: 'POST', headers: { 'X-CSRF-Token': token, 'Accept': 'text/html' },
          body: body, credentials: 'same-origin', redirect: 'manual'
        });
        window.__resetStatus = r.status;
      } catch (e) { window.__resetError = String(e); }
      window.__resetDone = true;
    })();
  JS
  eventually { expect(page.evaluate_script('window.__resetDone === true')).to be(true) }
end

# ── Outcome assertions ────────────────────────────────────────────────────────

Then("the user should have no two-factor method but two-factor still enabled") do
  @user.reload
  expect(@user.two_factor_enabled).to be true
  expect(@user.two_factor_mode).to be_nil
  expect(@user.otp_secret).to be_nil
  expect(@user.two_factor_reset_at).to be_present
  expect(@user.two_factor_reset_by_id).to eq(@user.id)
end

Then("the colleague should have no two-factor method but two-factor still enabled") do
  @colleague.reload
  expect(@colleague.two_factor_enabled).to be true
  expect(@colleague.two_factor_mode).to be_nil
  expect(@colleague.otp_secret).to be_nil
  expect(@colleague.two_factor_reset_by_id).to eq(@user.id)
end

Then("the user should still be in authenticator mode") do
  @user.reload
  expect(@user.two_factor_mode).to eq("authenticator")
  expect(@user.otp_secret).to be_present
end

Then("the colleague should still be in whatsapp mode") do
  @colleague.reload
  expect(@colleague.two_factor_mode).to eq("whatsapp")
  expect(@colleague.otp_secret).to be_present
end

# Cucumber runs ActiveJob inline, so deliver_later mail is already in deliveries.
Then("the user should have received a two-factor reset email") do
  mail = ActionMailer::Base.deliveries.find do |m|
    m.to.include?(@user.email) && m.subject.include?("two-factor authentication method was reset")
  end
  expect(mail).to be_present
  expect(mail.body.encoded).to include("You reset your two-factor authentication method")
end

Then("the colleague should have received a two-factor reset email mentioning {string}") do |text|
  mail = ActionMailer::Base.deliveries.find do |m|
    m.to.include?(@colleague.email) && m.subject.include?("two-factor authentication method was reset")
  end
  expect(mail).to be_present
  expect(mail.body.encoded).to include("reset by your administrator")
  expect(mail.body.encoded).to include(text)
end

# ── Mode-selection banner ─────────────────────────────────────────────────────

Then("I should see the two-factor reset banner") do
  expect(page).to have_css("#two_factor_reset_banner", text: "Your two-factor method was reset", wait: 10)
  expect(page).to have_css("#two_factor_reset_banner", text: "by you")
end

Then("I should see the two-factor reset banner from an administrator") do
  expect(page).to have_css("#two_factor_reset_banner", text: "by your administrator", wait: 10)
end
