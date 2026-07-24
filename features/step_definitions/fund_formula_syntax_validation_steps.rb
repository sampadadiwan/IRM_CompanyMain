# Step definitions for features/fund/fund_formula_syntax_validation.feature
#
# Exercises FundFormula's model validations (formula_syntax_valid?) directly —
# no browser, no persistence required, since the check runs on #valid?.

Given("a fund formula with formula {string}") do |formula|
  @fund_formula = FundFormula.new(
    name:       "Test Formula",
    formula:    formula,
    rule_type:  "GenerateAccountEntry",
    entry_type: "Accounting",
    rule_for:   "accounting"
  )
end

Given("a fund formula with formula:") do |formula|
  @fund_formula = FundFormula.new(
    name:       "Test Formula",
    formula:    formula.strip,
    rule_type:  "GenerateAccountEntry",
    entry_type: "Accounting",
    rule_for:   "accounting"
  )
end

When("I validate the fund formula") do
  @fund_formula.valid?
end

Then("the fund formula should be valid") do
  expect(@fund_formula.errors[:formula]).to be_empty,
    "Expected no formula errors, got: #{@fund_formula.errors[:formula].inspect}"
end

Then("the fund formula should be invalid") do
  expect(@fund_formula.errors[:formula]).not_to be_empty,
    "Expected formula errors, got none"
end

Then("the fund formula should be invalid with a formula error containing {string}") do |text|
  expect(@fund_formula.errors[:formula].any? { |msg| msg.include?(text) }).to be(true),
    "Expected a formula error containing #{text.inspect}, got: #{@fund_formula.errors[:formula].inspect}"
end

Then("the fund formula should not have a syntax error") do
  expect(@fund_formula.errors[:formula].any? { |msg| msg.include?("invalid Ruby syntax") }).to be(false),
    "Expected no syntax error, got: #{@fund_formula.errors[:formula].inspect}"
end
