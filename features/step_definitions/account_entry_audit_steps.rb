# Step definitions for features/fund/account_entry_audit.feature.
# Funds, the "Alpha Fee" entry and its commitment come from account_entries_index_query_steps.rb;
# "I delete the entry" from account_entries_default_fund_steps.rb; the portfolio investment from
# validation_rules.rb.

def aea_entry!(name)
  AccountEntry.with_deleted.find_by!(name: name)
end

# The audits of an entry by action, oldest first
def aea_audits(entry, action)
  Audit.where(auditable_type: "AccountEntry", auditable_id: entry.id, action: action).order(:id)
end

# Runs the purge task with the given ENV, recording a refusal (the task aborts) instead of failing the step
def aea_run_purge(env)
  Rails.application.load_tasks unless Rake::Task.task_defined?("audits:purge_account_entry")
  env.each { |k, v| ENV[k] = v }
  @aea_purge_refused = false
  Rake::Task["audits:purge_account_entry"].reenable
  Rake::Task["audits:purge_account_entry"].invoke
rescue SystemExit
  @aea_purge_refused = true
ensure
  env.each_key { |k| ENV.delete(k) }
end

# A fresh export path under tmp/, removed after the scenario
def aea_export_path
  @aea_export_path ||= Rails.root.join("tmp", "aea_audits_#{SecureRandom.hex(6)}.jsonl.gz").to_s
end

After("@account_entry_audit") do
  FileUtils.rm_f(@aea_export_path) if @aea_export_path
end

### Screen ######################################################################

# The shared fixture builds generated entries, which AccountEntryPolicy#update? does not let anyone edit
Given('the entry {string} was made by hand') do |name|
  aea_entry!(name).update_column(:generated, false)
end

When('I change the notes of the entry {string} to {string} on the screen') do |name, notes|
  page.driver.submit :patch, account_entry_path(aea_entry!(name)), { account_entry: { notes: notes } }
end

When('I create the entry {string} for fund {string} on the screen') do |name, fund_name|
  fund = aeiq_fund!(fund_name)
  page.driver.submit :post, account_entries_path,
                     { account_entry: { entity_id: fund.entity_id, fund_id: fund.id, name: name, entry_type: "Fee",
                                        reporting_date: aeiq_reporting_date.to_s, amount: "100" } }
end

Then('the entry {string} should have {string} {string} audit by the current user') do |name, count, action|
  audits = aea_audits(aea_entry!(name), action)
  expect(audits.count).to eq(count.to_i)
  expect(audits.pluck(:user_id).uniq).to eq([@user.id])
end

Then('its latest audit should record only the columns {string}') do |columns|
  audit = Audit.where(auditable_type: "AccountEntry").order(:id).last
  expect(audit.audited_changes.keys).to match_array(columns.split(",").map(&:strip))
end

Then('the entry {string} should be soft-deleted') do |name|
  expect(aea_entry!(name).deleted_at).to be_present
end

### Outside the screen (as allocation runs, imports and jobs do) ###############

# Audit.as_user is how ApplicationJob attributes a job's writes, so these carry a user like a job would
When('the system creates the entry {string} for fund {string} as the current user') do |name, fund_name|
  Audit.as_user(@user) { aeiq_entry(aeiq_fund!(fund_name), name: name) }
end

When('the system changes the notes of the entry {string} to {string} as the current user') do |name, notes|
  Audit.as_user(@user) { aea_entry!(name).update!(notes: notes) }
end

When('the system deletes the entry {string} as the current user') do |name|
  Audit.as_user(@user) { aea_entry!(name).destroy }
end

Then('there should be no audits for account entries') do
  expect(Audit.where(auditable_type: "AccountEntry")).not_to exist
end

### Portfolio investment ########################################################

# Saved through the model, as a valuation recompute saves them; no save callback recomputes these
When('the computed values of the portfolio investment change') do
  @pi_audit_count = @portfolio_investment.audits.count
  @portfolio_investment.reload.update!(fmv_cents: 123_456, unrealized_gain_cents: 23_456, cost_of_remaining_cents: 100_000)
  # The values really changed, so "no audit" is down to the exclusion, not to an unchanged save
  expect(@portfolio_investment.reload.fmv_cents).to eq(123_456)
end

When('the notes of the portfolio investment change to {string} along with its computed values') do |notes|
  @pi_audit_count = @portfolio_investment.audits.count
  @portfolio_investment.reload.update!(notes: notes, fmv_cents: 654_321, unrealized_gain_cents: 54_321)
end

Then('the portfolio investment should have no new audit') do
  expect(@portfolio_investment.audits.count).to eq(@pi_audit_count)
end

Then('the portfolio investment should have {string} new {string} audit recording only the columns {string}') do |count, action, columns|
  new_audits = @portfolio_investment.audits.order(:id).offset(@pi_audit_count)
  expect(new_audits.count).to eq(count.to_i)
  expect(new_audits.last.action).to eq(action)
  expect(new_audits.last.audited_changes.keys).to match_array(columns.split(",").map(&:strip))
end

### Purge task ##################################################################

# Written the way the May 2024 burst was: create and destroy audits of entries, with no user
Given('there are {string} old audits for account entries') do |count|
  entry = aea_entry!("Alpha Fee")
  count.to_i.times do |i|
    Audit.create!(auditable_type: "AccountEntry", auditable_id: entry.id, action: i.even? ? "create" : "destroy",
                  audited_changes: { "name" => "Alpha Fee", "amount_cents" => 10_000 }, created_at: Time.zone.local(2024, 5, 10))
  end
  # Everything else in the table (the fund's, the commitment's, …) must survive the purge
  @aea_other_audit_ids = Audit.where.not(auditable_type: "AccountEntry").pluck(:id)
  expect(@aea_other_audit_ids).not_to be_empty
end

Given('the export file already exists') do
  File.write(aea_export_path, "an earlier copy")
end

When('support runs the account entry audit purge without EXECUTE') do
  aea_run_purge({})
end

When('support runs the account entry audit purge with EXECUTE and an export file') do
  aea_run_purge("EXECUTE" => "1", "EXPORT" => aea_export_path, "SLEEP" => "0")
end

When('support runs the account entry audit purge with EXECUTE but no export file') do
  aea_run_purge("EXECUTE" => "1", "SLEEP" => "0")
end

Then('there should be {string} audits for account entries') do |count|
  expect(Audit.where(auditable_type: "AccountEntry").count).to eq(count.to_i)
end

Then('the audits of other records should remain') do
  expect(Audit.where(id: @aea_other_audit_ids).count).to eq(@aea_other_audit_ids.size)
end

Then('the export file should hold {string} audits for account entries') do |count|
  rows = Zlib::GzipReader.open(aea_export_path) { |gz| gz.each_line.map { |line| JSON.parse(line) } }
  expect(rows.size).to eq(count.to_i)
  expect(rows.pluck("auditable_type").uniq).to eq(["AccountEntry"])
end

Then('the purge should have been refused') do
  expect(@aea_purge_refused).to be(true)
  # A refused run leaves an existing file as it was (R5)
  expect(File.read(aea_export_path)).to eq("an earlier copy") if File.exist?(aea_export_path)
end
