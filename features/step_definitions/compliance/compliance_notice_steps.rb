# Notifications, digest and export steps — business-rules.md (group 6)

Given('a needs-review result is stored for {string} on {string}') do |fund_name, date|
  fp = cmp_fund_pack(fund_name)
  run = ComplianceRun.create!(entity_id: fp.entity_id, fund_id: fp.fund_id, run_date: cmp_date(date), trigger: "run_now", status: "succeeded", finished_at: Time.current)
  ComplianceResult.create!(entity_id: fp.entity_id, compliance_run: run, fund_compliance_pack: fp, compliance_pack_version: fp.compliance_pack_version,
                           check_key: "sebi_investor_group_review", outcome: "needs_review", working: { "message" => "Needs review" })
end

When('the compliance digest is sent on {string}') do |date|
  travel_to(ActiveSupport::TimeZone[ComplianceWorld::IST].parse("#{date} 08:05")) do
    setup = cmp_setup
    setup.update_columns(last_digest_on: cmp_date(date) - 1.day) if setup.last_digest_on.nil?
    ComplianceDigestJob.perform_now(horizon.id, date)
  end
end

def cmp_digests(user)
  Noticed::Event.where(type: "ComplianceNotifier").joins(:notifications)
                .where(noticed_notifications: { recipient_type: "User", recipient_id: user.id })
                .select { |e| e.params[:kind].to_s == "digest" }
end

Then('{string} got a digest saying {string}') do |name, text|
  expect(cmp_digests(cmp_user(name)).map { |e| e.params[:message] }).to include(text)
end

Then('{string} got {int} compliance digest(s)') do |name, count|
  expect(cmp_digests(cmp_user(name)).size).to eq(count)
end

Then('an email went to {string} about {string}') do |name, text|
  user = cmp_user(name)
  mails = ActionMailer::Base.deliveries.select { |m| Array(m.to).include?(user.email) && m.subject.to_s.include?(text) }
  expect(mails).not_to be_empty
end

When('{string} exports the register from {string} to {string}') do |user, from, to|
  @export = ComplianceRegisterExport.new(cmp_user(user), cmp_date(from), cmp_date(to), []).rows_for_test
  @export_bytes = ComplianceRegisterExport.call(user: cmp_user(user), from: cmp_date(from), to: cmp_date(to))
end

Then('the export has results for {string}') do |fund_name|
  expect(@export[:results].map(&:first)).to include(fund_name)
  expect(@export_bytes.bytesize).to be > 0
end

Then('the export has register items for {string}') do |fund_name|
  expect(@export[:items].map(&:first)).to include(fund_name)
end

Then('the export has no rows for {string}') do |fund_name|
  expect(@export[:results].map(&:first) + @export[:items].map(&:first)).not_to include(fund_name)
end

Then('the export states {string}') do |text|
  expect(@export[:basis]).to eq(text)
end

Then('the export shows {string} for an approval') do |label|
  expect(@export[:items].map(&:last)).to include(label)
end
