# One allocation run per fund at a time (features/fund/one_allocation_run_per_fund.feature).
# Why: runs 3499/3500 of fund 316 ran together on 2026-11-10 and corrupted October -- see
# docs/modules/allocation/allocation_process.md, "One run per fund at a time".
#
# "That run" is @run throughout. The engine's real work (RunFormulas) is stubbed where a scenario is
# about whether a run may start rather than what it computes.

# Engine results as the engine reads them: failure? decides between the error and success branches
def oar_success_result
  double("RunFormulasResult", failure?: false, success?: true, :[] => nil)
end

# A run that already exists, saved without validation: it stands for a run that started earlier (and
# may still be running), which the one-run-per-fund check would rightly refuse to create now.
# `ago` is "<n> minutes|hours"; status "" means the run never wrote one.
def oar_create_run(ago, status, run_allocations: true)
  amount, unit = ago.split
  run = AllocationRun.new(entity_id: @fund.entity_id, fund: @fund, user: @user, start_date: Date.new(2026, 10, 1),
                          end_date: Date.new(2026, 10, 31), run_allocations:, status: status.presence,
                          created_at: amount.to_i.public_send(unit).ago)
  run.save!(validate: false)
  run
end

Given('an allocation run on the fund started {string} ago with status {string}') do |ago, status|
  @run = oar_create_run(ago, status)
end

Given('an allocation run on the fund that runs no formulas, started {string} ago with status {string}') do |ago, status|
  @run = oar_create_run(ago, status, run_allocations: false)
end

# An engine holds the fund's lock (on some Sidekiq thread, process or box): seen by held?, and a
# second engine cannot take it. SQLite has no named locks, so this is stubbed.
Given('an allocation engine is running on the fund') do
  allow(AllocationFundLock).to receive(:held?).and_return(true)
  allow(AllocationFundLock).to receive(:hold).and_yield(false)
end

Given('that run is marked as crashed') do
  expect(@run.mark_crashed!(@user)).to be(true)
end

# Previous Runs' icon-only action buttons carry their name in aria-label; Capybara's enable_aria_label
# is off in this suite, so they are located by that attribute rather than by have_button
def oar_action_button_css(label)
  %(button[aria-label="#{label}"])
end

# Counts calls into the formula operation and answers success, so a scenario can tell whether the
# engine got as far as running formulas
Given('the allocation formulas are stubbed to succeed') do
  @formula_runs = 0
  allow(AccountEntryAllocation::RunFormulas).to receive(:wtf?) do
    @formula_runs += 1
    oar_success_result
  end
end

Given('the allocation formulas will raise {string}') do |message|
  allow(AccountEntryAllocation::RunFormulas).to receive(:wtf?).and_raise(RuntimeError, message)
end

When('I start an allocation run on the Allocate screen') do
  # About whether a run may start, not what it computes: the queued job is not run
  allow(AccountEntryAllocationJob).to receive(:perform_later)
  @runs_before = AllocationRun.where(fund_id: @fund.id).count
  visit allocate_form_fund_path(@fund.id, run_allocations: true)
  click_on("Submit")
end

When('I mark that run as crashed under Previous Runs') do
  # Clicks on the page already open when it is Previous Runs: E5 loads it while the run looks crashed,
  # then an engine starts, and the click must still reach the server (which refuses it)
  visit allocate_form_fund_path(@fund.id) unless page.current_path == allocate_form_fund_path(@fund.id)
  # rack_test ignores the confirm popup's Stimulus action, so the click submits the button's own form
  within("#allocation_run_#{@run.id}") { find(oar_action_button_css("Mark as crashed")).click }
end

When('the allocation job of that run runs') do
  AccountEntryAllocationJob.perform_now(@fund.id, @run.start_date, @run.end_date, user_id: @user.id,
                                                                                  run_allocations: @run.run_allocations, explain: true, allocation_run_id: @run.id)
rescue StandardError => e
  # Kept for "the job failed with": an exception must still end the run with a status
  @job_error = e
end

When('that run is re-run') do
  @rerun_error = nil
  begin
    @run.rerun!
  rescue ArgumentError => e
    @rerun_error = e
  end
end

When('another run on the fund, which finished, is re-run') do
  @other_run = oar_create_run("1 hours", "Success")
  @rerun_error = nil
  begin
    @other_run.rerun!
  rescue ArgumentError => e
    @rerun_error = e
  end
end

Then('a new allocation run is created for the fund') do
  expect(AllocationRun.where(fund_id: @fund.id).count).to eq(@runs_before + 1)
end

Then('no new allocation run is created for the fund') do
  expect(AllocationRun.where(fund_id: @fund.id).count).to eq(@runs_before)
end

Then('Previous Runs shows {string} for that run') do |text|
  visit allocate_form_fund_path(@fund.id)
  within("#allocation_run_#{@run.id}") { expect(page).to have_content(text) }
end

Then('Previous Runs offers {string} for that run') do |label|
  visit allocate_form_fund_path(@fund.id)
  within("#allocation_run_#{@run.id}") { expect(page).to have_css(oar_action_button_css(label)) }
end

Then('Previous Runs does not offer {string} for that run') do |label|
  visit allocate_form_fund_path(@fund.id)
  within("#allocation_run_#{@run.id}") { expect(page).to have_no_css(oar_action_button_css(label)) }
end

Then("that run's status is {string}") do |status|
  expect(@run.reload.status.to_s).to eq(status)
end

Then("that run's status starts with {string}") do |prefix|
  expect(@run.reload.status.to_s).to start_with(prefix)
end

Then('no formulas ran') do
  expect(@formula_runs).to eq(0)
end

Then('the formulas ran once') do
  expect(@formula_runs).to eq(1)
end

Then('the job failed with {string}') do |message|
  expect(@job_error&.message).to eq(message)
end

Then('the re-run is refused with {string}') do |text|
  expect(@rerun_error&.message).to include(text)
end

Then('the re-run is accepted') do
  expect(@rerun_error).to be_nil
end

Then('two runs of the same fund get different scratch files') do
  first = AccountEntryAllocation::RunFormulas.scratch_key([@fund.id], 3499)
  second = AccountEntryAllocation::RunFormulas.scratch_key([@fund.id], 3500)
  expect(first).not_to eq(second)
  # The process id stays in the name: parallel cucumber workers repeat run ids, one DB each
  expect(first).to end_with("_#{Process.pid}")
end
