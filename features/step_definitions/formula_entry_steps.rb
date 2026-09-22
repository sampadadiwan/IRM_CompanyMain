# Shared set-up for the formula-explanation features: entries built the way CreateAccountEntry
# writes them, and the formula scanner's own steps. The explanation steps themselves are in
# entry_explanation_steps.rb.
#
# features/support/env.rb excludes `allocation_runs` and `account_entries` from DatabaseCleaner's
# truncation, so they are cleaned up here.
After('@entry_explanation') do
  next if @fund.nil?

  AccountEntry.where(fund_id: @fund.id).delete_all
  AllocationRun.where(fund_id: @fund.id).delete_all
end

### Helpers ####################################################################

def dt_commitment!(folio_id)
  @arc_commitments.fetch(folio_id)
end

# An entry shaped the way CreateAccountEntry writes one: explanation[0] is the formula text it
# evaluated, and the trailing JSON is the breakdown of intermediate values (only written when
# the run had "Explain Formulas" on).
def dt_entry(name:, amount:, folio_id:, formula: nil, breakdown: nil, **extra)
  explanation = []
  explanation << formula if formula
  explanation << breakdown.to_json if breakdown
  AccountEntry.create!({ entity_id: @fund.entity_id, fund_id: @fund.id, name: name,
                         entry_type: "Fee", generated: true, cumulative: false,
                         reporting_date: @allocation_run.end_date,
                         amount_cents: BigDecimal(amount), folio_id: folio_id,
                         capital_commitment_id: folio_id ? dt_commitment!(folio_id).id : nil,
                         allocation_run_id: @allocation_run.id,
                         explanation: explanation.presence }.merge(extra))
end

def dt_find!(name, folio_id)
  entry = AccountEntry.where(fund_id: @fund.id, name: name,
                             capital_commitment_id: dt_commitment!(folio_id).id).first
  expect(entry).not_to be_nil, "No #{name.inspect} entry for folio #{folio_id}"
  entry
end

# Always two decimals, as the screen shows money; BigDecimal#to_s drops trailing zeros.
def dt_money(cents) = format("%.2f", (cents.to_d / 100).round(2))

### Reading a formula ##########################################################

When('the formula {string} is read') do |formula|
  @dt_scan = FormulaReferenceScanner.new(formula).call
end

# One step for every kind the scanner reports, so "unresolved" cannot also match a more
# general pattern and leave Cucumber with an ambiguous choice.
Then('its {string} should be {string}') do |kind, expected|
  actual = case kind
           when "fields" then @dt_scan.field_names.join(",")
           when "inputs" then @dt_scan.input_names.join(",")
           when "helper names" then @dt_scan.helper_calls.map(&:name).compact.join(",")
           when "helper types" then @dt_scan.helper_calls.map(&:entry_type).compact.join(",")
           when "name filters" then @dt_scan.name_filters.join(",")
           when "unresolved" then @dt_scan.unresolved.size.to_s
           else raise "unknown kind #{kind}"
           end
  expect(actual).to eq(expected)
end

Then('reading it should report that it could not be read') do
  expect(@dt_scan.parse_error).to be_present
end

### The entries a run produced #################################################

Given('the run produced {string} of {string} for folio {string} computed by {string}') do |name, amount, folio_id, formula|
  # A real run records every @reference it read; these scenarios get the same, taken from the
  # entries already present, so the breakdown agrees with the ledger unless a scenario says it
  # should not.
  breakdown = FormulaReferenceScanner.new(formula).call.field_names.to_h do |field|
    sibling = AccountEntry.where(fund_id: @fund.id, capital_commitment_id: dt_commitment!(folio_id).id,
                                 reporting_date: @allocation_run.end_date).find do |entry|
      FundFormula.to_varable_name(entry.name) == field
    end
    ["@#{field}", sibling&.amount_cents.to_s]
  end
  dt_entry(name: name, amount: amount, folio_id: folio_id, formula: formula, breakdown: breakdown)
end

Given('the run produced {string} of {string} for folio {string} computed by {string} recording {string} as {string}') do |name, amount, folio_id, formula, key, value|
  dt_entry(name: name, amount: amount, folio_id: folio_id, formula: formula, breakdown: { key => value })
end

Given('the run produced {string} of {string} for folio {string} computed by {string} with no breakdown') do |name, amount, folio_id, formula|
  dt_entry(name: name, amount: amount, folio_id: folio_id, formula: formula)
end

Given('an earlier {string} entry of {string} for folio {string} dated {string}') do |name, amount, folio_id, date|
  dt_entry(name: name, amount: amount, folio_id: folio_id, reporting_date: Date.parse(date),
           allocation_run_id: nil)
end

Given('the run produced a fund-level {string} entry of {string}') do |name, amount|
  dt_entry(name: name, amount: amount, folio_id: nil)
end

Given('the run produced a fund-level {string} entry of {string} computed by {string}') do |name, amount, formula|
  dt_entry(name: name, amount: amount, folio_id: nil, formula: formula, breakdown: {})
end

# The case that broke: the tree walks the fund-level parent first, so whatever it caches for
# that date must not be handed back as the folio's own entries.
Given('the run produced {string} of {string} for folio {string} allocated from the fund level computed by {string}') do |name, amount, folio_id, formula|
  source = AccountEntry.where(fund_id: @fund.id, name: name, capital_commitment_id: nil).first
  dt_entry(name: name, amount: amount, folio_id: folio_id, formula: formula, breakdown: {},
           parent_type: "AccountEntry", parent_id: source.id)
end

Given('an uploaded {string} entry of {string} for folio {string}') do |name, amount, folio_id|
  dt_entry(name: name, amount: amount, folio_id: folio_id, generated: false, allocation_run_id: nil)
end

Given('the run produced {string} of {string} for folio {string} allocated from that fund total') do |name, amount, folio_id|
  source = AccountEntry.where(fund_id: @fund.id, name: name, capital_commitment_id: nil).first
  dt_entry(name: name, amount: amount, folio_id: folio_id,
           parent_type: "AccountEntry", parent_id: source.id)
end

# As the engine writes it: a generated entry carries the id of the formula that produced it.
Given('the run produced {string} of {string} for folio {string} from the fund formula {string}') do |name, amount, folio_id, formula_name|
  formula = FundFormula.find_by!(fund_id: @fund.id, name: formula_name)
  dt_entry(name: name, amount: amount, folio_id: folio_id, formula: formula.formula,
           breakdown: {}, fund_formula_id: formula.id)
end
