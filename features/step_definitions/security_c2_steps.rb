# Step definitions for features/security/formula_sandbox.feature (C2 — allowlist-checked formula
# evaluation, plus N1 — KPI formulas folded as numbers).
# docs/security/security_review_2026_10.md "C2 — Formula engine: allowlist-checked evaluation"
#
# Reused from elsewhere: "there is a user … for an entity …" (features/common.rb), "there is a fund …
# for the entity" (fund.rb), the call-fee steps "a commitment … with no fund unit settings", "a call fee
# … with formula …", "the call fee formula is calculated …", "the call fee formula result should be …"
# and "… should fail with a FormulaError containing …" (call_fee_formula_errors_steps.rb), and the
# allocation import / run / compare steps (fund.rb, account_entries.rb).
#
# Nothing here evaluates stored text outside the code paths under test.

# A binding with no locals of its own (a method with no locals), for steps that need a formula binding
# carrying exactly the locals they set
class C2BindingHost
  def self.fresh
    new.instance_eval { binding }
  end
end

# The mode is an ENV value read on every evaluation; each scenario sets it and the After hook restores it
Given("the formula sandbox mode is {string}") do |mode|
  @c2_previous_mode = ENV.fetch("FORMULA_SANDBOX", nil) unless @c2_mode_set
  @c2_mode_set = true
  ENV["FORMULA_SANDBOX"] = mode
  # Fresh cache and "logged once" set, so this scenario's log lines are its own
  FormulaSandbox.reset!
end

# Swap the Rails logger for one writing to a string; the After hook puts the original back
Given("formula sandbox log lines are captured") do
  @c2_log = StringIO.new
  @c2_saved_logger ||= Rails.logger
  Rails.logger = ActiveSupport::Logger.new(@c2_log)
end

After do
  # Restore the mode this scenario changed (unset if it was unset)
  if @c2_mode_set
    @c2_previous_mode.nil? ? ENV.delete("FORMULA_SANDBOX") : ENV["FORMULA_SANDBOX"] = @c2_previous_mode
    FormulaSandbox.reset!
  end
  # Restore the logger and any EXECUTE flag the audit steps set
  Rails.logger = @c2_saved_logger if @c2_saved_logger
  ENV.delete("EXECUTE") if @c2_execute_set
end

##############################################################################
# Fund formulas: save and audit
##############################################################################

# C2-1 / C2-X2 / C2-X3 — a fund formula saved through the model, so every validation runs
When("I save a {string} fund formula {string}") do |rule_type, formula|
  @fund_formula = FundFormula.new(fund: @fund, entity_id: @fund.entity_id, name: "C2 #{rule_type}", rule_type:,
                                  entry_type: "Expense", rule_for: "accounting", enabled: true, formula:)
  @fund_formula_saved = @fund_formula.save
end

Then("the fund formula is refused by the formula sandbox with {string}") do |reason|
  @fund_formula_saved.should be(false)
  @fund_formula.errors[:formula].join(" ").should include("uses something formulas may not use")
  @fund_formula.errors[:formula].join(" ").should include(reason)
end

Then("the fund formula is saved") do
  @fund_formula_saved.should be(true), @fund_formula.errors.full_messages.join(", ")
end

Then("the fund formula is refused with {string}") do |message|
  @fund_formula_saved.should be(false)
  @fund_formula.errors[:formula].join(" ").should include(message)
end

Then("the fund formula has no formula sandbox error") do
  @fund_formula.errors[:formula].join(" ").should_not include("uses something formulas may not use")
end

# C2-7 / C2-X12 — a formula already in the table; created in off mode, as a pre-sandbox row would be
Given("the fund has a stored {string} formula {string}") do |rule_type, formula|
  @fund_formula = FundFormula.create!(fund: @fund, entity_id: @fund.entity_id, name: "C2 stored #{rule_type}", rule_type:,
                                      entry_type: "Expense", rule_for: "accounting", enabled: true, formula:)
end

# Runs the rake task in-process, capturing what it prints
def c2_run_audit(execute:)
  Rails.application.load_tasks unless Rake::Task.task_defined?("formula_sandbox:audit")
  @c2_execute_set = true
  execute ? ENV["EXECUTE"] = "1" : ENV.delete("EXECUTE")
  # Note the backups that exist before the run, so the step can find the one this run wrote
  @c2_backups_before = Rails.root.glob("tmp/formula_sandbox_backup_*.jsonl").map(&:to_s)
  output = StringIO.new
  saved_stdout = $stdout
  $stdout = output
  begin
    Rake::Task["formula_sandbox:audit"].reenable
    Rake::Task["formula_sandbox:audit"].invoke
  ensure
    $stdout = saved_stdout
  end
  @c2_audit_output = output.string
end

When("I run the formula sandbox audit") do
  c2_run_audit(execute: false)
end

When("I run the formula sandbox audit with EXECUTE=1") do
  c2_run_audit(execute: true)
end

Then("the audit output includes {string}") do |text|
  @c2_audit_output.should include(text)
end

Then("the stored formula is still {string}") do |formula|
  expect(@fund_formula.reload.formula).to eq(formula)
end

# C2-X12 — the JSONL backup holds the row's text from before the rewrite; the file is removed afterwards
Then("the audit backup holds the formula before {string}") do |formula|
  written = Rails.root.glob("tmp/formula_sandbox_backup_*.jsonl").map(&:to_s) - @c2_backups_before
  expect(written.size).to eq(1)
  rows = File.readlines(written.first).map { |line| JSON.parse(line) }
  expect(rows.find { |row| row["id"] == @fund_formula.id }["formula_before"]).to eq(formula)
  FileUtils.rm_f(written)
end

##############################################################################
# Call fees (the shared call-fee steps build and evaluate the fee)
##############################################################################

# C2-2 / C2-3 / C2-6 — the refusal is the sandbox's, raised as itself (not wrapped in FormulaError)
Then("the call fee formula is refused by the formula sandbox with {string}") do |reason|
  @formula_error.should be_a(FormulaSandbox::Rejected)
  @formula_error.should be_a(ApplicationRecord::UnsafeEvalError)
  @formula_error.message.should include(reason)
end

Then("the formula sandbox logged {string}") do |text|
  @c2_log.string.should include("[formula_sandbox] #{text}")
end

Then("the formula sandbox logged nothing") do
  @c2_log.string.should_not include("[formula_sandbox]")
end

##############################################################################
# Calculation custom fields
##############################################################################

# C2-4 — the save-time check on a Calculation field
When("I validate a Calculation custom field with meta_data {string}") do |meta_data|
  @c2_field = FormCustomField.new(name: "c2_calc", field_type: "Calculation", meta_data:)
  @c2_field.validate
end

Then("the custom field is refused by the formula sandbox with {string}") do |reason|
  @c2_field.errors[:meta_data].join(" ").should include(reason)
end

# C2-4 / C2-H6 — WithCustomField#perform_custom_calculation on an unsaved commitment
When("the Calculation {string} is evaluated on a commitment of {string}") do |meta_data, args|
  commitment = CapitalCommitment.new
  key_values(commitment, args)
  field = FormCustomField.new(name: "c2_calc", field_type: "Calculation", meta_data:)
  begin
    @c2_value = commitment.perform_custom_calculation(field)
    @c2_error = nil
  rescue StandardError => e
    @c2_error = e
  end
end

Then("the custom field evaluation is refused by the formula sandbox") do
  @c2_error.should be_a(FormulaSandbox::Rejected)
end

# Numbers compare as numbers: committed_amount_cents is a decimal column, so results are BigDecimals
def c2_number(value)
  BigDecimal(value.to_s)
end

Then("the custom field value is {string}") do |value|
  @c2_error.should be_nil
  expect(c2_number(@c2_value)).to eq(c2_number(value))
end

##############################################################################
# Run checks
##############################################################################

# C2-5 / C2-H4 — AccountEntryAllocation::CheckContext#evaluate for an unsaved fund
When("the run check {string} is evaluated for an unsaved fund") do |formula|
  context = AccountEntryAllocation::CheckContext.new(fund: Fund.new(name: "C2 Fund"), start_date: Date.new(2026, 1, 1),
                                                     end_date: Date.new(2026, 3, 31), allocation_run: nil)
  begin
    @c2_value = context.evaluate(formula, label: "C2 run check")
    @c2_error = nil
  rescue StandardError => e
    @c2_error = e
  end
end

Then("the run check is refused by the formula sandbox with {string}") do |reason|
  @c2_error.should be_a(FormulaSandbox::Rejected)
  @c2_error.message.should include(reason)
end

Then("the run check result is {string}") do |value|
  @c2_error.should be_nil
  expect(@c2_value.to_s).to eq(value)
end

Then("the run check failed with {string}") do |message|
  @c2_error.should be_a(AccountEntryAllocation::CheckFailed)
  expect(@c2_error.message).to eq(message)
end

##############################################################################
# The allocation engine and the explain breakdown
##############################################################################

# C2-H3 — AllocationBaseOperation#safe_eval with a binding carrying only capital_commitment
When("the allocation engine evaluates {string} with profile {string} for a commitment of {string}") do |formula, profile, args|
  @c2_commitment = CapitalCommitment.new
  key_values(@c2_commitment, args)
  bdg = C2BindingHost.fresh
  bdg.local_variable_set(:capital_commitment, @c2_commitment)
  # allocate: the operation's own initialize (Trailblazer) is not needed to call one helper
  @c2_value = AccountEntryAllocation::GenerateCustomFields.allocate.safe_eval(formula, bdg, profile:)
end

Then("the allocation engine result is {string}") do |value|
  expect(c2_number(@c2_value)).to eq(c2_number(value))
end

Then("the commitment custom field {string} is {string}") do |name, value|
  expect(@c2_commitment.json_fields[name]).to eq(value)
end

# C2-H7 — the explanation as CreateAccountEntry / reparse_and_save build it: the formula runs first
# (so its locals exist), then each planned expression is evaluated in the same binding
When("the formula {string} is explained for a commitment of {string}") do |formula, args|
  commitment = CapitalCommitment.new
  key_values(commitment, args)
  bdg = C2BindingHost.fresh
  bdg.local_variable_set(:capital_commitment, commitment)
  fund_formula = FundFormula.new(name: "C2 explain", rule_type: "GenerateAccountEntry", formula:)
  FormulaSandbox.evaluate(formula, bdg, profile: fund_formula.sandbox_profile, context: "C2 explain")
  @c2_explanation = fund_formula.parse_statement(bdg)
end

When("I keep the explanation") do
  @c2_kept_explanation = @c2_explanation.to_json
end

Then("the explanation equals the kept one") do
  expect(@c2_explanation.to_json).to eq(@c2_kept_explanation)
end

Then("the explanation includes {string} with {string}") do |expression, value|
  expect(c2_number(@c2_explanation[expression])).to eq(c2_number(value))
end

##############################################################################
# Literals: widget metadata (C1) and the portfolio-numbers field map
##############################################################################

Then("the widget metadata {string} reads as {string}") do |metadata, json|
  expect(RubyLiteral.parse_hash(metadata).to_json).to eq(json)
end

# C2-X13 — GeneratePortfolioNumbersForFund#field_map on an unsaved formula
Then("the portfolio numbers field map {string} reads as {string}") do |formula, json|
  operation = AccountEntryAllocation::GeneratePortfolioNumbersForFund.allocate
  expect(operation.field_map(FundFormula.new(id: 1, formula:)).to_json).to eq(json)
end

Then("the portfolio numbers field map {string} is refused") do |formula|
  operation = AccountEntryAllocation::GeneratePortfolioNumbersForFund.allocate
  expect { operation.field_map(FundFormula.new(id: 1, formula:)) }.to raise_error(FormulaSandbox::Rejected)
end

##############################################################################
# N1 — KPI computed formulas
##############################################################################

Then("the KPI formula {string} folds to {string}") do |formula, value|
  expect(FormulaSandbox.numeric_fold(formula).to_s).to eq(value)
end

Then("the KPI formula {string} is refused as not numeric") do |formula|
  expect { FormulaSandbox.numeric_fold(formula) }.to raise_error(FormulaSandbox::NotNumeric)
end

##############################################################################
# The check itself (parse only)
##############################################################################

# locals: comma-separated names ("" for none)
def c2_locals(list)
  list.split(",").map(&:strip).reject(&:empty?).map(&:to_sym)
end

Then("the text {string} checked with profile {string} and locals {string} is refused with {string}") do |text, profile, locals, reason|
  FormulaSandbox.violations(text, profile:, locals: c2_locals(locals)).join("; ").should include(reason)
end

Then("the text {string} checked with profile {string} and locals {string} passes") do |text, profile, locals|
  expect(FormulaSandbox.violations(text, profile:, locals: c2_locals(locals))).to eq([])
end

Then("the formula sandbox mode in effect is {string}") do |mode|
  expect(FormulaSandbox.mode).to eq(mode)
end

##############################################################################
# is_erb notification bodies
##############################################################################

# C2-X11 — the body is rendered against a stand-in view holding @investor_kyc, as the KYC mailer's does
When("the is_erb body {string} is rendered for KYC {string}") do |body, full_name|
  ENV.delete("C2_X11")
  view = Object.new
  view.instance_variable_set(:@investor_kyc, Struct.new(:full_name).new(full_name))
  @c2_rendered = CustomNotification.new(body:, is_erb: true).render_erb_body(view)
end

Then("the rendered body includes {string}") do |text|
  @c2_rendered.to_s.should include(text)
end

Then("the ERB tag in the body was not run") do
  ENV["C2_X11"].should be_nil
end
