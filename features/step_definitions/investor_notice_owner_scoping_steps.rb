# Step definitions for features/misc/investor_notice_owner_scoping.feature
#
# Covers InvestorNoticeJob/InvestorNotice#investors owner-scoping (a
# Fund/SecondarySale-owned notice targets only that owner's granted-access
# investors, not every investor of the GP) and the expiry sweep in
# InvestorNoticeJob#expire_ended_notices.
#
# Reuses @entity/@fund/@investors from access_rights_cache_steps.rb's
# "there is an entity"/"there is a fund"/"there is an investor ... with
# investor_entity ..." steps, and the "I grant ... access to the fund for
# investor ..." step for AccessRight setup.

Given('there is an investor notice titled {string} owned by the fund with generate enabled') do |title|
  @investor_notices ||= {}
  @investor_notices[title] = InvestorNotice.create!(
    entity: @entity,
    owner: @fund,
    title: title,
    start_date: Time.zone.today,
    end_date: Time.zone.today + 1.month,
    active: true,
    generate: true
  )
end

Given('there is an entity-wide investor notice titled {string} with generate enabled') do |title|
  @investor_notices ||= {}
  @investor_notices[title] = InvestorNotice.create!(
    entity: @entity,
    owner: nil,
    title: title,
    start_date: Time.zone.today,
    end_date: Time.zone.today + 1.month,
    active: true,
    generate: true
  )
end

Given('the investor notice {string} ended yesterday') do |title|
  # update_columns bypasses callbacks/validations — we only want to backdate
  # end_date, not trigger update_investors or re-run the generate callback.
  @investor_notices[title].update_columns(end_date: Time.zone.yesterday)
end

When('the investor notice job runs for {string}') do |title|
  # Mirrors how the model's after_commit callback enqueues it (InvestorNoticeJob.perform_later)
  InvestorNoticeJob.perform_now(@investor_notices[title].id)
end

When('a new investor {string} is added to the entity') do |investor_name|
  investor = (@investors || {})[investor_name] || Investor.find_by!(investor_name: investor_name)
  InvestorAddedJob.perform_now(investor.id)
end

When('the investor notice expiry job runs') do
  # perform_now with no id takes the expire_ended_notices branch (see InvestorNoticeJob#perform)
  InvestorNoticeJob.perform_now
end

Then('the investor notice {string} should have an entry for {string}') do |title, investor_name|
  investor = (@investors || {})[investor_name] || Investor.find_by!(investor_name: investor_name)
  notice = @investor_notices[title]
  # be_truthy (not `be true, "msg"`) — `be true, "msg"` mis-parses as
  # be(true, "msg") since `be` already opened a command call on `true`.
  expect(notice.investor_notice_entries.exists?(investor_id: investor.id)).to be_truthy,
    "expected an InvestorNoticeEntry for #{investor_name} on notice #{title.inspect}, found none"
end

Then('the investor notice {string} should not have an entry for {string}') do |title, investor_name|
  investor = (@investors || {})[investor_name] || Investor.find_by!(investor_name: investor_name)
  notice = @investor_notices[title]
  expect(notice.investor_notice_entries.exists?(investor_id: investor.id)).to be_falsey,
    "expected no InvestorNoticeEntry for #{investor_name} on notice #{title.inspect}, but one exists"
end

Then('the investor notice {string} should be inactive') do |title|
  expect(@investor_notices[title].reload.active).to be false
end
