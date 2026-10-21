# Step definitions for features/misc/investor_notice_criteria.feature
#
# Covers InvestorNoticeCriteriaEvaluator (a Dentaku expression, never Ruby
# eval, that further narrows an already-generated notice audience at render
# time) and InvestorNotice's save-time validation that rejects a broken
# expression before it can silently hide a notice from everyone.
#
# Reuses @entity (access_rights_cache_steps.rb), @investor_notices
# (investor_notice_owner_scoping_steps.rb), and @carousel_investors + "I
# login as investor .../I log out" (investor_notice_carousel_owner_scoping_steps.rb).

Given('the investor notice {string} has criteria {string}') do |title, expr|
  @investor_notices[title].update!(criteria: expr)
end

# Bypasses InvestorNotice's own save-time validation (update_column skips
# validations/callbacks) — used to set up the "already-broken" case the
# validation exists to prevent, so we can assert the render-time fail-closed
# behavior independently of the save-time guard.
Given('the investor notice {string} has criteria {string} without validation') do |title, expr|
  @investor_notices[title].update_column(:criteria, expr)
end

Then('setting the investor notice {string} criteria to {string} should be rejected') do |title, expr|
  notice = @investor_notices[title]
  expect(notice.update(criteria: expr)).to be false
  expect(notice.errors[:criteria]).to be_present
end

When('I visit the edit page for the investor notice {string}') do |title|
  visit edit_investor_notice_path(@investor_notices[title])
end

Then('the criteria field should not be present') do
  expect(page).to have_no_css("#investor_notice_criteria")
end

Then('the criteria field should be present') do
  expect(page).to have_css("#investor_notice_criteria")
end

Given('the investor notice {string} has a line item titled {string} linking to the edit profile page') do |title, item_title|
  # /users/[user.id]/edit (UsersController#edit), not Devise's edit_user_registration_path
  # (/users/edit) — the latter has no phone field, so it can't actually be
  # used to satisfy this notice's own "add your phone number" premise.
  @investor_notices[title].investor_notice_items.create!(
    title: item_title,
    details: "Keep your contact information up to date.",
    link: "/users/[user.id]/edit"
  )
end

# Fixture setup, not a user edit: skip the emailed-code check that guards changing an
# existing number (User#existing_phone_change_must_be_verified).
Given('investor {string} has no phone number') do |investor_name|
  user = @carousel_investors[investor_name][:user]
  user.skip_phone_change_verification!
  user.update!(phone: nil)
end

Given('investor {string} has phone number {string}') do |investor_name, phone|
  user = @carousel_investors[investor_name][:user]
  user.skip_phone_change_verification!
  user.update!(phone: phone)
end
