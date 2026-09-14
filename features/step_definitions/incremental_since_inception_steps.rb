# Step definitions for features/fund/incremental_since_inception.feature
# The fund setup, seed, formula, run and amount steps are shared with
# fund_formula_multiple_steps.rb and account_entries.rb.

# Opts the fund in to the trimmed scratch copy + carry-forward since_inception, and pins the
# financial year to April so the copy floor does not depend on the geo default.
Given("the fund allocates incrementally") do
  @fund.update_column(:json_fields, @fund.json_fields.to_h.merge("incremental_since_inception" => true, "month_offset_for_fy" => "3"))
end

Given("the fund has an April financial year") do
  @fund.update_column(:json_fields, @fund.json_fields.to_h.merge("month_offset_for_fy" => "3"))
end

# Same run as 'the Allocation Run {string} is created for the {string}' (account_entries.rb), but a
# formula error propagates out of AccountEntryAllocationJob.perform_now, so expect it here.
Then("running the Allocation Run {string} for the {string} should fail with {string}") do |args, fund_name, message|
  fund = Fund.find_by(name: fund_name)
  key_val = args.split(";").to_h { |kv| kv.split("=") }
  start_date = Date.local_parse(key_val["start_date"])
  end_date = Date.local_parse(key_val["end_date"])
  allocation_run = AllocationRun.create!(fund: fund, entity_id: fund.entity_id, start_date: start_date, end_date: end_date, run_allocations: true, user_id: User.first.id)

  expect do
    AccountEntryAllocationJob.perform_now(fund.id, start_date, end_date, rule_for: "", tag_list: nil, run_allocations: true, explain: true, user_id: User.first.id,
                                                                         generate_soa: false, template_id: nil, fund_ratios: false, sample: false, allocation_run_id: allocation_run.id)
  end.to raise_error(RuntimeError, /#{Regexp.escape(message)}/)
end
