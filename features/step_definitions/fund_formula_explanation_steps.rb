# Step definitions for features/fund/fund_formula_explanation.feature
#
# These tests exercise parse_statement and reparse_and_save at the model level —
# no browser or login required. A minimal FundFormula instance (not saved) is used
# for parse_statement; reparse_and_save needs a persisted AccountEntry.

# ─── Helpers ────────────────────────────────────────────────────────────────

# Creates a clean binding on a throwaway Object with the given instance variables.
# Uses Object.new so the binding context is free of Cucumber World noise.
def build_formula_binding(**ivars)
  ctx = Object.new
  ivars.each { |k, v| ctx.instance_variable_set("@#{k}", v) }
  ctx.instance_eval { binding }
end

# Parses "key=value;key2=value2" into a symbol-keyed Hash.
# Attempts Integer, then Float, then leaves as String.
def parse_binding_string(str)
  return {} if str.blank?
  str.split(";").to_h do |pair|
    k, v = pair.strip.split("=", 2)
    parsed = Integer(v.strip) rescue (Float(v.strip) rescue v.strip)
    [k.strip.to_sym, parsed]
  end
end

# Runs eval(formula, binding) to populate any local variables the formula
# assigns before we call parse_statement, mirroring what the allocation engine
# does (via safe_eval) before CreateAccountEntry calls parse_statement.
def run_parse(formula, **ivars)
  @parsed_formula = formula
  @fund_formula   = FundFormula.new(
    name:       "Test Formula",
    formula:    formula,
    rule_type:  "GenerateAccountEntry",
    entry_type: "Accounting",
    rule_for:   "accounting"
  )
  @formula_binding = build_formula_binding(**ivars)
  # rubocop:disable Security/Eval
  eval(formula, @formula_binding)           # Step 1: populate locals defined inside the formula
  # rubocop:enable Security/Eval
  @breakdown = @fund_formula.parse_statement(@formula_binding, external_formula: formula)
end


# ─── Given steps ────────────────────────────────────────────────────────────

Given("a formula {string} with bindings {string}") do |formula, bindings_str|
  @setup_formula  = formula
  @setup_bindings = parse_binding_string(bindings_str)
end

Given("a formula {string} with no bindings") do |formula|
  @setup_formula  = formula
  @setup_bindings = {}
end

Given("a multi-statement formula with bindings {string}:") do |bindings_str, formula|
  @setup_formula  = formula.strip
  @setup_bindings = parse_binding_string(bindings_str)
end

Given("a multi-statement formula with no bindings:") do |formula|
  @setup_formula  = formula.strip
  @setup_bindings = {}
end

# reparse_and_save setup — builds a minimal persisted AccountEntry.
# We rely on the existing @entity / @fund if available, otherwise create them.
Given("an account entry exists with formula {string}") do |formula|
  @reparse_formula = formula

  # Reuse entity and fund from a prior Background step if present, otherwise build minimal ones
  entity = @entity || FactoryBot.create(:entity, name: "Formula Test Entity", entity_type: "Investment Fund")
  fund   = @fund   || Fund.new(name: "Formula Test Fund", currency: "USD", entity: entity)
  fund.save(validate: false) unless fund.persisted?

  fund_formula = FundFormula.new(
    name:       "Formula Test Rule",
    formula:    formula,
    rule_type:  "GenerateAccountEntry",
    entry_type: "Accounting",
    rule_for:   "accounting",
    fund:       fund,
    entity:     entity
  )
  fund_formula.save(validate: false)

  ae = AccountEntry.new(
    name:           "Formula Test Entry",
    entry_type:     "Accounting",
    fund:           fund,
    entity:         entity,
    fund_formula:   fund_formula,
    reporting_date: Date.new(2025, 3, 31),
    period:         "Q1-2025",   # set explicitly since save(validate:false) skips setup_defaults
    amount_cents:   0,
    rule_for:       "accounting",
    generated:      true
  )
  ae.explanation = [formula, ""]
  ae.save(validate: false)

  @reparse_account_entry = ae
end

Given("the account entry has amount_cents {int}") do |cents|
  @reparse_account_entry.update_columns(amount_cents: cents)
end

Given("the account entry has bindings {string}") do |bindings_str|
  @reparse_bindings = parse_binding_string(bindings_str)
end


# ─── When steps ─────────────────────────────────────────────────────────────

When("parse_statement is run on the formula") do
  run_parse(@setup_formula, **@setup_bindings)
  puts "\n--- Breakdown for: #{@setup_formula.truncate(80)} ---"
  @breakdown.each { |k, v| puts "  #{k.inspect} => #{v.inspect}" }
end

When("reparse_and_save is called on the account entry") do
  # reparse_and_save builds its own binding using `binding` on the FundFormula
  # instance. We set the test ivars directly on the instance so they are
  # captured in that binding, mirroring what the allocation engine does via
  # create_instance_variables (which sets @fund, @start_date, @end_date, etc.).
  ff = @reparse_account_entry.fund_formula
  (@reparse_bindings || {}).each { |k, v| ff.instance_variable_set("@#{k}", v) }

  @reparse_breakdown = ff.reparse_and_save(@reparse_account_entry)
  @reparse_result_key = @reparse_breakdown.max_by { |k, _| k.length }&.first
  puts "\n--- reparse_and_save breakdown for: #{@reparse_formula.truncate(80)} ---"
  @reparse_breakdown.each { |k, v| puts "  #{k.inspect} => #{v.inspect}" }
  puts "  result key: #{@reparse_result_key.inspect}"
end


# ─── Then steps ─────────────────────────────────────────────────────────────

Then("the breakdown includes the key {string} with numeric value {float}") do |key, value|
  expect(@breakdown).to have_key(key), "Expected breakdown to include key #{key.inspect}. Keys present: #{@breakdown.keys.inspect}"
  expect(@breakdown[key].to_f).to eq(value), "Expected #{key.inspect} => #{value}, got #{@breakdown[key].inspect}"
end

Then("the breakdown includes the key {string} with string value {string}") do |key, value|
  expect(@breakdown).to have_key(key), "Expected breakdown to include key #{key.inspect}. Keys present: #{@breakdown.keys.inspect}"
  expect(@breakdown[key].to_s).to eq(value), "Expected #{key.inspect} => #{value.inspect}, got #{@breakdown[key].inspect}"
end

Then("the breakdown includes the key {string}") do |key|
  expect(@breakdown).to have_key(key), "Expected breakdown to include key #{key.inspect}. Keys present: #{@breakdown.keys.inspect}"
end

Then("the breakdown does not include the key {string}") do |key|
  expect(@breakdown).not_to have_key(key), "Expected breakdown NOT to include key #{key.inspect}"
end

Then("the last breakdown key is {string}") do |key|
  actual_last = @breakdown.keys.last
  expect(actual_last).to eq(key),
    "Expected last breakdown key #{key.inspect}, got #{actual_last.inspect}. " \
    "All keys: #{@breakdown.keys.inspect}"
end

Then("the breakdown does not include the key {string} with string value {string}") do |key, value|
  # Either the key is absent, OR it has a different value (the filter worked)
  absent_or_different = !@breakdown.key?(key) || @breakdown[key].to_s != value
  expect(absent_or_different).to be(true),
    "Expected key #{key.inspect} to be absent or have a different value, but found #{@breakdown[key].inspect}"
end

Then("the breakdown does not include any bare numeric literal keys") do
  # Bare numeric literals (integers, floats on their own) should never appear as keys —
  # they are not captured by find_expressions (:int and :float nodes are unhandled).
  numeric_keys = @breakdown.keys.select { |k| k.to_s.strip.match?(/\A-?\d+(\.\d+)?\z/) }
  expect(numeric_keys).to be_empty, "Expected no bare numeric keys, found: #{numeric_keys.inspect}"
end

Then("the saved breakdown result key has numeric value {float}") do |expected|
  expect(@reparse_result_key).to be_present, "Expected a result key in the breakdown"
  saved_breakdown = JSON.parse(@reparse_account_entry.reload.explanation[2])
  expect(saved_breakdown[@reparse_result_key].to_f).to eq(expected),
    "Expected result key #{@reparse_result_key.inspect} => #{expected} numerically, " \
    "got #{saved_breakdown[@reparse_result_key].inspect}"
end

Then("the live formula would evaluate to {float}") do |expected|
  # Verifies that reparse_and_save *would* have produced a different value if it
  # hadn't pinned the result to amount_cents — confirming the pinning matters.
  bdg = build_formula_binding(**@reparse_bindings)
  # rubocop:disable Security/Eval
  live_result = eval(@reparse_formula, bdg)
  # rubocop:enable Security/Eval
  expect(live_result.to_f).to eq(expected),
    "Expected live formula result #{expected}, got #{live_result.inspect}"
end
