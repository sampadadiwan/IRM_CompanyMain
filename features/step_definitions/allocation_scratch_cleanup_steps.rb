require "open3"
require "tmpdir"

# DELETEs the allocation issues against account_entries filtered by allocation_run_id alone,
# i.e. the scratch DB cleanup in RunFormulas#load_sqlite_db (not the primary-DB cleanup, which
# filters by fund, period and formula).
RUN_ID_CLEANUP_SQL = /\ADELETE FROM "account_entries" WHERE "account_entries"\."allocation_run_id" = /i

Given('SQL statements are being recorded') do
  @recorded_sql = []
  @sql_subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
    @recorded_sql << payload[:sql].to_s
  end
end

# The scratch copy is kept between runs only in development. Point the scratch dir at a throwaway
# directory so this never touches (or deletes) a developer's real tmp/allocation/*_dev copies.
Given('the scratch database is reused between runs like in development') do
  allow_any_instance_of(AccountEntryAllocation::RunFormulas).to receive(:reuse_scratch_db?).and_return(true)
  @previous_scratch_dir = ENV.fetch("ALLOCATION_SCRATCH_DIR", nil)
  @scratch_dir = Dir.mktmpdir("allocation_scratch")
  ENV["ALLOCATION_SCRATCH_DIR"] = @scratch_dir
end

Given('the load script fails') do
  failed = double("status", success?: false, exitstatus: 1)
  allow(Open3).to receive(:capture2e).and_return(["boom", failed])
end

Given('the account entries of {string} are recorded') do |fund_name|
  fund = Fund.find_by!(name: fund_name)
  @recorded_entry_count = AccountEntry.where(fund_id: fund.id).count
  @recorded_entry_sum = AccountEntry.where(fund_id: fund.id).sum(:amount_cents)
  expect(@recorded_entry_count).to be_positive
end

Given('the {word} formula of {string} is disabled') do |position, fund_name|
  fund = Fund.find_by!(name: fund_name)
  formulas = FundFormula.where(fund_id: fund.id).order(:sequence)
  formula = position == "last" ? formulas.last : formulas.first
  formula.update_columns(enabled: false)
end

When('the last Allocation Run is re-run') do
  AllocationRun.last.rerun!(now: true)
end

Then('the account entries of {string} are unchanged') do |fund_name|
  fund = Fund.find_by!(name: fund_name)
  expect(AccountEntry.where(fund_id: fund.id).count).to eq(@recorded_entry_count)
  expect(AccountEntry.where(fund_id: fund.id).sum(:amount_cents)).to eq(@recorded_entry_sum)
end

Then('no scratch cleanup by allocation run id was issued') do
  expect(@recorded_sql.grep(RUN_ID_CLEANUP_SQL)).to be_empty
end

Then('a scratch cleanup by allocation run id was issued') do
  expect(@recorded_sql.grep(RUN_ID_CLEANUP_SQL)).not_to be_empty
end

Then('the AllocationRun status starts with {string}') do |prefix|
  expect(AllocationRun.last.status).to start_with(prefix)
end

After do
  ActiveSupport::Notifications.unsubscribe(@sql_subscriber) if @sql_subscriber
  if @scratch_dir
    FileUtils.rm_rf(@scratch_dir)
    ENV["ALLOCATION_SCRATCH_DIR"] = @previous_scratch_dir
    ENV.delete("ALLOCATION_SCRATCH_DIR") if @previous_scratch_dir.nil?
  end
end
