# Step definitions for two_factor_help_links.feature — the login-less guide pages
# and the help/download links on the two-factor setup screens.

# ── Public guide pages ───────────────────────────────────────────────────────

When("I visit the public authenticator setup guide") do
  visit public_guide_path("authenticator_app_setup_user_guide")
end

When("I visit the public two factor guide") do
  visit public_guide_path("two_factor_authentication_user_guide")
end

When("I visit the public guide {string}") do |guide_id|
  # Built by hand rather than through the helper so an already-escaped traversal
  # payload reaches the controller intact.
  visit "/help/#{guide_id}"
end

Then("I should see a download link for {string}") do |app_name|
  expect(page).to have_content(app_name)
  # Every listed app offers both stores; assert the pair rather than the label alone
  # so a heading with no working link cannot pass.
  expect(page).to have_link("iPhone")
  expect(page).to have_link("Android")
end

Then("I should not be asked to sign in") do
  expect(page).to have_no_current_path(new_user_session_path)
  expect(page).to have_no_field("user[password]")
end

# "I should be redirected to the login page" is defined in two_factor_steps.rb.

# ── Help links on the two-factor screens ─────────────────────────────────────

Then("I should see a link to the authenticator setup guide") do
  expect(page).to have_link("Read the setup guide",
                            href: public_guide_path("authenticator_app_setup_user_guide"))
end

Then("I should see the authenticator download links") do
  expect(page).to have_css(".authenticator-apps", visible: :visible, wait: 5)
  within(".authenticator-apps") do
    expect(page).to have_content("Google Authenticator")
    expect(page).to have_content("Microsoft Authenticator")
    expect(page).to have_content("Twilio Authy")
  end
end

Then("I should not see the authenticator download links") do
  # visible: :visible so the assertion fails if the block is merely present but shown —
  # the Stimulus controller hides it with the hidden attribute rather than removing it.
  expect(page).to have_no_css(".authenticator-apps", visible: :visible, wait: 5)
end

When("I choose the Authenticator mode without continuing") do
  choose("two_factor_mode", option: "authenticator")
end

When("I choose the WhatsApp mode without continuing") do
  choose("two_factor_mode", option: "whatsapp")
end
