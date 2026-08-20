# Step definitions for features/misc/investor_notice_item_authorization.feature
#
# Covers InvestorNoticeItemPolicy (new — the controller previously had no
# authorize/policy_scope calls at all) and InvestorNoticeEntryPolicy#index?
# being tightened to require company_admin.
#
# Reuses the generic 'the user {string} should be allowed/denied {string} on
# the record' steps from access_rights_models_steps.rb, which check
# Pundit.policy(user, @record).send("#{action}?") — @record is set below to
# the InvestorNoticeItem created for the scenario.

Given('there is an investor notice item titled {string} for the entity {string}') do |title, entity_kv|
  entity = Entity.find_by!(name: entity_kv.split('=').last)
  notice = InvestorNotice.create!(
    entity: entity,
    title: "Notice for #{title}",
    start_date: Time.zone.today,
    end_date: Time.zone.today + 1.month,
    active: true
  )
  # InvestorNoticeItem has no `entity` association, only entity_id (set by its
  # own before_save :set_entity_id callback from investor_notice.entity_id) —
  # don't pass entity: here, it isn't attr-assignable.
  @record = InvestorNoticeItem.create!(
    investor_notice: notice,
    title: title,
    details: "Some details"
  )
end

Then('the user {string} should be allowed to list investor notice items') do |email|
  user = User.find_by!(email: email)
  expect(Pundit.policy(user, InvestorNoticeItem).index?).to be true
end

Then('the user {string} should be denied to list investor notice items') do |email|
  user = User.find_by!(email: email)
  expect(Pundit.policy(user, InvestorNoticeItem).index?).to be false
end

Then('the user {string} should be allowed to list investor notice entries') do |email|
  user = User.find_by!(email: email)
  expect(Pundit.policy(user, InvestorNoticeEntry).index?).to be true
end

Then('the user {string} should be denied to list investor notice entries') do |email|
  user = User.find_by!(email: email)
  expect(Pundit.policy(user, InvestorNoticeEntry).index?).to be false
end
