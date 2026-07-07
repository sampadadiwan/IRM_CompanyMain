# Step definitions for features/core/access_right_notification.feature

When('the user {string} is granted access to the fund with notify enabled') do |email|
  grantee = User.find_by!(email: email)
  @access_right = AccessRight.create!(entity: @fund.entity, owner: @fund, user_id: grantee.id, notify: true)
end

When('the user {string} is granted access to the fund without notify enabled') do |email|
  grantee = User.find_by!(email: email)
  @access_right = AccessRight.create!(entity: @fund.entity, owner: @fund, user_id: grantee.id, notify: false)
end

Then('the user {string} receives an access granted notification email for the fund') do |email|
  open_email(email)
  expect(current_email).not_to be_nil, "No email delivered to #{email}"
  expect(current_email.subject).to eq("Access Granted to Fund #{@fund.name} by #{@fund.entity.name}")
  clear_emails
end

Then('the user {string} does not receive an access granted notification email') do |email|
  open_email(email)
  expect(current_email).to be_nil, "Unexpected email delivered to #{email}"
end

# access_to_investor_id path: AccessRight#users resolves recipients via
# investor.notification_users(owner), which itself checks FundPolicy#show? for @investor_user —
# granted here by this very AccessRight (the after_create_commit callback runs post-commit, so
# the just-created row is already visible to that policy check).
When('the investor is granted access to the fund with notify enabled') do
  @access_right = AccessRight.create!(entity: @fund.entity, owner: @fund, access_to_investor_id: @investor.id, notify: true)
end

When('the investor is granted access to the fund without notify enabled') do
  @access_right = AccessRight.create!(entity: @fund.entity, owner: @fund, access_to_investor_id: @investor.id, notify: false)
end

Then('the investor\'s user receives an access granted notification email for the fund') do
  open_email(@investor_user.email)
  expect(current_email).not_to be_nil, "No email delivered to #{@investor_user.email}"
  expect(current_email.subject).to eq("Access Granted to Fund #{@fund.name} by #{@fund.entity.name}")
  clear_emails
end

Then('the investor\'s user does not receive an access granted notification email') do
  open_email(@investor_user.email)
  expect(current_email).to be_nil, "Unexpected email delivered to #{@investor_user.email}"
end

# access_to_category path: AccessRight#users resolves recipients via
# User.joins(investor_accesses: :investor).where(entity_id:, 'investors.category': access_to_category)
# — "entity_id" there is the ACCESS RIGHT's own entity_id column, matched against the recipient
# USER's entity_id, NOT the fund/owner's entity. Confirmed empirically: entity: @fund.entity (the
# GP entity, as every other AccessRight in this suite sets it) matches zero users, since investor
# users live on their own investor entity (@investor_entity) — so this branch only ever resolves
# recipients when entity is set to the recipient's own entity instead, unlike the other two paths.
When('investors in category {string} are granted access to the fund with notify enabled') do |category|
  @access_right = AccessRight.create!(entity: @investor_entity, owner: @fund, access_to_category: category, notify: true)
end

# Distinct from "...receives an access granted notification email for the fund" above: this
# access_to_category AccessRight's entity is @investor_entity (required for #users to resolve
# any recipient at all, see comment above), so AccessRightsMailer's subject — built from
# @access_right.entity.name — reads "by <investor entity name>" instead of "by <fund's own
# entity name>" like the user_id/access_to_investor_id paths.
Then('the investor\'s user receives an access granted notification email naming their own entity') do
  open_email(@investor_user.email)
  expect(current_email).not_to be_nil, "No email delivered to #{@investor_user.email}"
  expect(current_email.subject).to eq("Access Granted to Fund #{@fund.name} by #{@investor_entity.name}")
  clear_emails
end
