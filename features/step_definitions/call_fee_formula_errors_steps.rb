# Step definitions for features/fund/call_fee_formula_errors.feature
#
# Exercises CallFee#calculate_formula directly on unsaved records - no browser, no
# persistence. An unsaved Fund has no fund_unit_settings, so fund_unit_setting is nil
# for the commitment, which is the production failure being reproduced.

Given("a commitment {string} with no fund unit settings") do |args|
  # Unsaved fund: fund.fund_unit_settings.where(...) returns nothing
  @fund = Fund.new(name: "Formula Fund", currency: "INR")
  @capital_commitment = CapitalCommitment.new(fund: @fund)
  key_values(@capital_commitment, args)
end

Given("a call fee {string} with formula {string}") do |name, formula|
  @capital_call = CapitalCall.new(fund: @fund, name: "Formula Call")
  @call_fee = CallFee.new(id: 9001, name:, notes: formula, formula: true, fee_type: "Other Fees", capital_call: @capital_call)
end

Given("a call fee {string} saved without validation with formula {string}") do |name, formula|
  # Same unsaved record - calculate_formula never consults notes_kosher?, so this stands in
  # for a formula that bypassed validation (update_column, import, seed)
  @capital_call = CapitalCall.new(fund: @fund, name: "Formula Call")
  @call_fee = CallFee.new(id: 9001, name:, notes: formula, formula: true, fee_type: "Other Fees", capital_call: @capital_call)
end

When("the call fee formula is calculated for a remittance with call amount {int} cents") do |cents|
  remittance = CapitalRemittance.new(capital_call: @capital_call, capital_commitment: @capital_commitment, fund: @fund, call_amount_cents: cents)
  # Keep both outcomes so the Then steps can assert on either
  begin
    @formula_result = @call_fee.calculate_formula(remittance)
    @formula_error = nil
  rescue StandardError => e
    @formula_error = e
  end
end

Then("the call fee formula result should be {float}") do |expected|
  @formula_error.should be_nil
  @formula_result.should == expected
end

Then("the call fee formula should fail with a FormulaError containing {string}") do |text|
  @formula_error.should be_a(CallFee::FormulaError)
  @formula_error.message.should include(text)
end

Then("the call fee formula error should contain {string}") do |text|
  @formula_error.message.should include(text)
end

Then("the call fee formula error cause should be a {string}") do |klass|
  @formula_error.cause.class.name.should == klass
end

Then("the call fee formula should fail with an UnsafeEvalError") do
  @formula_error.should be_a(ApplicationRecord::UnsafeEvalError)
end
