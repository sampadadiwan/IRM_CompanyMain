# Step definitions for features/fund/incremental_allocation_ui.feature -- support previews and applies
# incremental allocation (and recomputing tracking starting values) through FundFormulaOperation.
#
# Operations are started and applied through the same model methods the controller calls
# (FundFormulaOperation.start! / #start_apply!); Cucumber's :inline ActiveJob adapter runs
# FundFormulaOperationJob before the next step. Page-level scenarios use an integration session signed
# in as the user, as internal_docs_steps.rb does, rather than the Playwright browser.
#
# Reuses the allocation run checker's "the fund has folios" and its @allocation_run_checker cleanup hook.

### Helpers ####################################################################

def iau_formula!(name)
  FundFormula.find_by!(fund_id: @fund.id, name:)
end

def iau_plan
  AccountEntryAllocation::IncrementalMigration::Plan.from_h(@operation.reload.plan)
end

def iau_session_for(user)
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.post "/users/sign_in", params: { user: { email: user.email, password: "password" } }
  session
end

def iau_generate!(name, formula, enabled: true)
  FundFormula.create!(fund: @fund, entity_id: @fund.entity_id, name:, rule_type: "GenerateAccountEntry", entry_type: "Reporting",
                      formula:, rule_for: "accounting", enabled:)
end

# Pattern B: several single-name since_inception totals added up
def iau_pattern_b(names)
  names.split(",").map(&:strip).map { |n| %(capital_commitment.since_inception(#{n.to_json},nil,@start_date,@end_date)) }.join(" + ")
end

def iau_page_body
  expect(@session.response.status).to eq(200)
  @session.response.body
end

def iau_folio_entry!(name:, folio:, amount:, date:, **attrs)
  commitment = arc_commitment!(folio)
  AccountEntry.create!({ entity_id: @fund.entity_id, fund_id: @fund.id, name:, entry_type: "Reporting",
                         amount_cents: BigDecimal(amount), reporting_date: Date.parse(date), generated: true, cumulative: false,
                         capital_commitment_id: commitment.id, folio_id: folio }.merge(attrs))
end

### Formulas ###################################################################

# Pattern B: several single-name since_inception totals added up. Its own total is stored for folio 101,
# so carry-forward has something to find.
Given('the fund has a formula {string} adding up the since-inception totals of {string}') do |name, names|
  iau_generate!(name, iau_pattern_b(names))
  iau_folio_entry!(name:, folio: "101", amount: "100", date: "2024-03-31")
end

Given('the fund has a disabled formula {string}') do |name|
  iau_generate!(name, %(capital_commitment.quarterly("Audit Fees",nil,@start_date,@end_date)), enabled: false)
end

Given('the fund has a post-run check that Since Inception totals match history') do
  FundFormula.create!(fund: @fund, entity_id: @fund.entity_id, name: "Post-run check: Since Inception totals match history",
                      rule_type: FundFormula::POST_RUN_CHECK, formula: 'since_inception_matches_history(["Apportioned Fees"])',
                      rule_for: "accounting", enabled: true)
end

# A hand edit after the switch: audited without the migration's comment, like any edit from the formula form
Given('the description of formula {string} is changed by hand to {string}') do |name, description|
  iau_formula!(name).update!(description:)
end

Given('formula {string} is changed by hand to add up the since-inception totals of {string}') do |name, names|
  iau_formula!(name).update!(formula: iau_pattern_b(names))
end

# A history read the migration cannot rewrite: a sum from inception with no stored value added
Given('the fund has a formula {string} summing {string} from inception') do |name, entry_name|
  iau_generate!(name, %(capital_commitment.account_entries.where(name: #{entry_name.to_json}, reporting_date: ..@end_date).sum(:amount_cents)))
end

# A tracking formula already bounded to the run's dates: its window plus its own stored previous value
Given('the fund has a tracking formula {string} totalling {string}') do |name, entry_name|
  iau_generate!(name, %(capital_commitment.account_entries.where(name: #{entry_name.to_json}, reporting_date: @start_date..@end_date).sum(:amount_cents) + capital_commitment.get_account_entry_or_zero(fund_formula.name, @start_date).amount_cents))
end

Given('folio {string} has {string} entries of {string} on {string} and {string} on {string}') do |folio, name, amount_a, date_a, amount_b, date_b|
  [[amount_a, date_a], [amount_b, date_b]].each { |amount, date| iau_folio_entry!(name:, folio:, amount:, date:) }
end

Given('formula {string} stored {string} for folio {string} on {string}') do |formula_name, amount, folio, date|
  formula = iau_formula!(formula_name)
  iau_folio_entry!(name: formula.name, folio:, amount:, date:, fund_formula_id: formula.id)
end

Given('formula {string} is edited after the preview') do |name|
  iau_formula!(name).update!(description: "Edited by someone else")
end

Given('an allocation run for the fund is still in progress') do
  WithValidationRules.skip do
    AllocationRun.create!(entity_id: @fund.entity_id, fund: @fund, user: @user, start_date: Date.new(2024, 1, 1),
                          end_date: Date.new(2024, 3, 31), run_allocations: true, status: "Pending")
  end
end

# What allocation:enable_incremental[fund,<id>] APPLY=true does, without the printing: no operation row
Given('the fund was switched on with the rake task') do
  outcome = AccountEntryAllocation::IncrementalMigration.new(@fund, out: StringIO.new).enable!(apply: true)
  expect(outcome).to eq(:enabled)
end

# The flag is the last write inside apply's transaction, after the formula edits
Given('writing the incremental flag will fail with {string}') do |message|
  allow_any_instance_of(AccountEntryAllocation::IncrementalMigration).to receive(:set_flag).and_raise(RuntimeError, message)
end

Given('a preview for the fund has been in progress for {int} hours') do |hours|
  @in_progress = FundFormulaOperation.create!(entity_id: @fund.entity_id, fund: @fund, operation: "enable_incremental",
                                              requested_by: @user, status: "previewing",
                                              created_at: hours.hours.ago, updated_at: hours.hours.ago)
end

# A finished suggestion set holding one addable suggestion, so an add that got through would create a formula
Given('a suggestion set exists for the fund') do
  suggestion = AccountEntryAllocation::RunCheckSuggestions::Suggestion.build(
    key: "rule:entries_allocated", source: "rule", rule_type: FundFormula::POST_RUN_CHECK,
    name: "Post-run check: Fund level entries allocated", description: "Every fund-level entry is allocated.",
    helper: "fund_entries_allocated", args: ""
  )
  suggestion["errors"] = []
  @operation = FundFormulaOperation.create!(entity_id: @fund.entity_id, fund: @fund, operation: "suggest_checks", requested_by: @user,
                                            status: "previewed", previewed_at: Time.current,
                                            plan: { "suggestions" => [suggestion.to_h], "ai_requested" => false, "rejected" => [] })
end

### Operations #################################################################

When('support previews {string}') do |operation|
  @operation = FundFormulaOperation.start!(fund: @fund, operation:, user: @user, params: {})
  @operation.reload
end

When('support previews recomputing starting values') do
  step 'support previews "reseed_carry_forward"'
end

When('support previews {string} while another preview is still running') do |operation|
  @in_progress = FundFormulaOperation.create!(entity_id: @fund.entity_id, fund: @fund, operation: "suggest_checks",
                                              requested_by: @user, status: "previewing")
  @operation = FundFormulaOperation.start!(fund: @fund, operation:, user: @user, params: {})
end

When('support applies the preview') do
  @refusal = @operation.reload.start_apply!(@user)
  @operation.reload
end

# A duplicate apply job (a retry, or a second request that got past the lock) for a finished operation
When('the apply job runs again for the operation') do
  FundFormulaOperationJob.perform_now(@operation.id, "apply")
end

### Assertions #################################################################

Then('the operation should be {string}') do |status|
  expect(@operation.reload.status).to eq(status), "#{@operation.status}: #{@operation.error}"
end

Then('the operation should be refused with {string}') do |text|
  expect([@refusal, @operation.reload.error].compact.join(" ")).to include(text)
end

Then('the preview should edit formula {string}') do |name|
  expect(iau_plan.edits.pluck("name")).to include(name)
end

Then('the preview should list a blocker mentioning {string}') do |text|
  expect(iau_plan.blockers.pluck("message").join(" ")).to include(text)
end

Then('the preview should warn {string}') do |text|
  expect(iau_plan.warnings.pluck("message").join(" ")).to include(text)
end

Then('the operation should record the error {string}') do |text|
  expect(@operation.reload.error.to_s).to include(text)
end

Then('the stale preview should be marked failed') do
  expect(@in_progress.reload.status).to eq("failed")
  expect(@in_progress.error).to include("Did not finish")
  expect(@operation.id).not_to eq(@in_progress.id)
end

Then('the preview should recompute {string} for folio {string} from {string} to {string}') do |formula_name, folio, old_amount, new_amount|
  reseed = iau_plan.reseeds.find { |r| r["name"] == formula_name }
  expect(reseed).to be_present, "No starting values for #{formula_name}: #{iau_plan.reseeds.pluck('name')}"
  value = reseed["values"].find { |v| v["capital_commitment_id"] == arc_commitment!(folio).id }
  expect(BigDecimal(value["old_cents"])).to eq(BigDecimal(old_amount))
  expect(BigDecimal(value["new_cents"])).to eq(BigDecimal(new_amount))
end

Then('no new preview should start') do
  expect(@operation.new_preview?).to be(false)
  expect(@operation.id).to eq(@in_progress.id)
  expect(FundFormulaOperation.where(fund_id: @fund.id).count).to eq(1)
end

Then('the fund should be on incremental allocation') do
  expect(CommitmentAccountEntry.incremental_since_inception?(@fund.reload)).to be(true)
end

Then('the fund should not be on incremental allocation') do
  expect(CommitmentAccountEntry.incremental_since_inception?(@fund.reload)).to be(false)
end

Then('formula {string} should carry forward its own total with a description') do |name|
  formula = iau_formula!(name)
  expect(formula.formula).to include("carry_forward_name: fund_formula.name")
  expect(formula.description).to include(AccountEntryAllocation::IncrementalMigration::DESCRIPTION_MARKER)
end

Then('formula {string} should add up single-name since-inception totals again with no description') do |name|
  formula = iau_formula!(name)
  expect(formula.formula).to start_with('capital_commitment.since_inception("')
  expect(formula.formula).not_to include("carry_forward_name")
  expect(formula.description).to be_blank
end

Then('formula {string} should be unchanged since the preview') do |name|
  edit = iau_plan.edits.find { |e| e["name"] == name }
  expect(iau_formula!(name).formula).to eq(edit["formula_before"])
end

Then('formula {string} should add up the since-inception totals of {string}') do |name, names|
  expect(iau_formula!(name).formula).to eq(iau_pattern_b(names))
end

Then('formula {string} should have description {string}') do |name, description|
  expect(iau_formula!(name).description).to eq(description)
end

Then('formula {string} should be enabled') do |name|
  expect(iau_formula!(name).enabled).to be(true)
end

Then('the fund should have no check formulas') do
  expect(@fund.fund_formulas.run_checks).not_to exist
end

Then('the stored {string} for folio {string} on {string} should be {string}') do |formula_name, folio, date, amount|
  entry = AccountEntry.find_by!(fund_id: @fund.id, fund_formula_id: iau_formula!(formula_name).id, capital_commitment_id: arc_commitment!(folio).id,
                                reporting_date: Date.parse(date))
  expect(entry.amount_cents).to eq(BigDecimal(amount))
end

Then('the fund formula operations history should list:') do |table|
  listed = FundFormulaOperation.where(fund_id: @fund.id).order(:id).map { |o| { "operation" => o.operation, "status" => o.status } }
  expect(listed).to eq(table.hashes)
end

# The rake task and the page render the same Plan through TextReport, so every line the page's plan
# prints must appear in the task's dry run.
Then('the rake dry run of {string} should print the same plan as the preview') do |task|
  Rails.application.load_tasks unless Rake::Task.task_defined?(task)
  expected = StringIO.new
  AccountEntryAllocation::IncrementalMigration::TextReport.new(@fund, expected).enable(iau_plan)
  printed = StringIO.new
  original = $stdout
  begin
    $stdout = printed
    Rake::Task[task].reenable
    Rake::Task[task].invoke("fund", @fund.id.to_s)
  ensure
    $stdout = original
  end
  expected.string.lines.each { |line| expect(printed.string).to include(line) }
end

### Pages ######################################################################

When('the user opens the fund formulas page') do
  @session = iau_session_for(@user)
  @session.get "/fund_formulas?fund_id=#{@fund.id}"
  expect(@session.response.status).to eq(200)
end

Then('the Actions menu should list {string}') do |item|
  body = @session.response.body
  expect(body).to match(/dropdown-toggle[^>]*>\s*Actions\s*</)
  expect(body).to include(item)
end

Then('the Actions menu should not list {string}') do |item|
  expect(@session.response.body).not_to include(item)
end

When('the user requests the incremental allocation page') do
  @session = iau_session_for(@user)
  @session.get "/fund_formula_operations?fund_id=#{@fund.id}"
end

When('the user posts a preview of {string}') do |operation|
  @session = iau_session_for(@user)
  @session.post "/fund_formula_operations", params: { fund_id: @fund.id, operation: }
end

Then('the request should be refused as unauthorized') do
  expect(@session.response).to be_redirect
  expect(@session.response.location).not_to include("fund_formula_operations")
end

Then('no fund formula operation should exist for the fund') do
  expect(FundFormulaOperation.where(fund_id: @fund.id)).not_to exist
end

Then('the incremental allocation page should show the recommended steps') do
  body = iau_page_body
  ["Add run checks", "before switching", "Preview and apply the switch", "after switching"].each { |text| expect(body).to include(text) }
end

Then('the incremental allocation page should say {string}') do |text|
  expect(iau_page_body).to include(text)
end

Then('the incremental allocation page should offer {string}') do |button|
  expect(iau_page_body).to include(button)
end

Then('the incremental allocation page should not offer {string}') do |button|
  expect(iau_page_body).not_to include(button)
end

# The "Done" badge index.html.erb renders next to a finished step
Then('the incremental allocation page should mark {int} steps done') do |count|
  expect(iau_page_body.scan("</i> Done</span>").size).to eq(count)
end

Then('the recommended steps {string} and {string} should be done') do |first, second|
  steps = IncrementalAllocationSteps.new(@fund.reload).steps.index_by { |s| s.key.to_s }
  [first, second].each { |key| expect(steps.fetch(key).done).to be(true), "#{key}: #{steps.fetch(key).detail}" }
end

Then('the next recommended step should be {string}') do |key|
  expect(IncrementalAllocationSteps.new(@fund.reload).next_step&.key.to_s).to eq(key)
end

Then('the recommended steps should show when the fund was switched on') do
  steps = IncrementalAllocationSteps.new(@fund.reload)
  expect(steps.switched_at).to be_present
  switch = steps.steps.find { |s| s.key == :switch }
  expect(switch.detail).to start_with("Switched on ")
  expect(switch.detail).not_to include("outside this page")
  expect(iau_page_body).to include(switch.detail)
end

When('the user chooses Enable All from the Actions menu') do
  @session = iau_session_for(@user)
  @session.patch "/fund_formulas/enable_formulas", params: { enable: true, fund_id: @fund.id }
  expect(@session.response).to be_redirect
end

# Every page and action of the controller, as a signed-in user without the support role
When('the user requests every operation page and action directly') do
  @session = iau_session_for(@user)
  key = @operation.suggestion_list.first.key
  requests = {
    "GET index" => -> { @session.get "/fund_formula_operations?fund_id=#{@fund.id}" },
    "GET suggestions" => -> { @session.get "/fund_formula_operations/suggestions?fund_id=#{@fund.id}" },
    "GET show" => -> { @session.get "/fund_formula_operations/#{@operation.id}" },
    "PATCH apply" => -> { @session.patch "/fund_formula_operations/#{@operation.id}/apply" },
    "POST add_suggestions" => -> { @session.post "/fund_formula_operations/#{@operation.id}/add_suggestions", params: { keys: [key] } },
    "POST download_suggestions" => -> { @session.post "/fund_formula_operations/#{@operation.id}/download_suggestions", params: { keys: [key] } }
  }
  @responses = requests.to_h { |label, request| request.call; [label, @session.response] }
end

Then('every request should be refused as unauthorized') do
  @responses.each do |label, response|
    expect(response).to be_redirect, "#{label} answered #{response.status}"
    expect(response.location).not_to include("fund_formula_operations"), "#{label} went to #{response.location}"
  end
end

When('the user starts an allocation run for the fund') do
  @runs_before = AllocationRun.where(fund_id: @fund.id).count
  @session = iau_session_for(@user)
  @session.patch "/funds/#{@fund.id}/allocate", params: { start_date: "2024-01-01", end_date: "2024-03-31", run_allocations: "true" }
end

Then('the allocation run should be refused because the formulas are being changed') do
  expect(@session.flash[:alert]).to include("formulas are being changed")
  expect(AllocationRun.where(fund_id: @fund.id).count).to eq(@runs_before)
end

Given('the preview is being applied') do
  @operation.reload.update!(status: "applying", applied_by: @user)
end
