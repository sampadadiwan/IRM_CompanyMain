# Step definitions for features/fund/fund_formula_multiple.feature
#
# Model-level steps exercise FundFormula's GenerateAccountEntryMultiple helpers
# (multiple_entry_names / multiple_entry_prefix / formula_for_entry_name) and
# validations without a browser or a fund. The engine-level steps run a full
# AccountEntryAllocationJob against seeded commitments and account entries.

# ─── Model-level Given steps ────────────────────────────────────────────────

Given("a multiple fund formula with formula:") do |formula|
  # Unsaved instance is enough — the helpers only parse the formula text
  @multiple_fund_formula = FundFormula.new(
    name: "Multiple Test Formula",
    formula: formula.strip,
    rule_type: "GenerateAccountEntryMultiple",
    entry_type: "Reporting",
    rule_for: "reporting"
  )
end

Given("the multiple fund formula has meta_data {string}") do |meta_data|
  @multiple_fund_formula.meta_data = meta_data
end

Given("the multiple fund formula has generate_ytd_qtly enabled") do
  @multiple_fund_formula.generate_ytd_qtly = true
end

# ─── Model-level Then steps ─────────────────────────────────────────────────

Then("the multiple entry names should be {string}") do |names|
  expect(@multiple_fund_formula.multiple_entry_names).to eq(names.split(",").map(&:strip))
end

# Compared stripped — Gherkin Examples table cells cannot carry the trailing
# space that the real prefixes ("Quarterly ") have.
Then("the multiple entry prefix should be {string}") do |prefix|
  expect(@multiple_fund_formula.multiple_entry_prefix.strip).to eq(prefix.strip)
end

# Exact comparison including trailing spaces, for override / empty prefix cases
Then("the multiple entry prefix should be exactly {string}") do |prefix|
  expect(@multiple_fund_formula.multiple_entry_prefix).to eq(prefix)
end

Then("the formula for entry name {string} should be:") do |name, expected_formula|
  expect(@multiple_fund_formula.formula_for_entry_name(name)).to eq(expected_formula.strip)
end

When("I validate the multiple fund formula") do
  @multiple_fund_formula.validate
end

Then("the multiple fund formula should be valid") do
  expect(@multiple_fund_formula).to be_valid
end

Then("the multiple fund formula should be invalid with a formula error containing {string}") do |message|
  expect(@multiple_fund_formula.validate).to be(false)
  expect(@multiple_fund_formula.errors[:formula].join).to include(message)
end

Then("the multiple fund formula should be invalid with a generate_ytd_qtly error containing {string}") do |message|
  expect(@multiple_fund_formula.validate).to be(false)
  expect(@multiple_fund_formula.errors[:generate_ytd_qtly].join).to include(message)
end

# ─── Engine-level steps ─────────────────────────────────────────────────────

# Seeds identical account entries on every commitment of the fund — these are the
# raw entries the period helpers sum over during the run. generated defaults to
# false; an optional "generated" column sets it (the incremental copy trims only
# generated rows).
Given("the commitments have the following seed account entries:") do |table|
  @fund.capital_commitments.find_each do |capital_commitment|
    table.hashes.each do |row|
      AccountEntry.create!(
        name: row["name"],
        entry_type: "Reporting",
        amount_cents: row["amount_cents"].to_i,
        reporting_date: Date.parse(row["reporting_date"]),
        capital_commitment: capital_commitment,
        fund: @fund,
        entity: @fund.entity,
        investor: capital_commitment.investor,
        folio_id: capital_commitment.folio_id,
        generated: row["generated"] == "true",
        cumulative: false
      )
    end
  end
end

Given("the fund has a GenerateAccountEntryMultiple formula {string} with entry type {string} and formula:") do |name, entry_type, formula|
  fund_formula = @fund.fund_formulas.build(
    name: name,
    formula: formula.strip,
    rule_type: "GenerateAccountEntryMultiple",
    entry_type: entry_type,
    rule_for: "reporting",
    enabled: true,
    roll_up: false
  )
  fund_formula.save!
  puts "\n####FundFormula####\n"
  puts fund_formula.to_json
end

# Plain single-name formula — used to reproduce interactions between the old
# GenerateAccountEntry path (incl. generate_ytd_qtly) and Multiple formulas
# running later in the same allocation run
Given("the fund has a GenerateAccountEntry formula {string} with entry type {string} and formula:") do |name, entry_type, formula|
  @fund.fund_formulas.create!(
    name: name,
    formula: formula.strip,
    rule_type: "GenerateAccountEntry",
    entry_type: entry_type,
    rule_for: "reporting",
    enabled: true,
    roll_up: false
  )
end

# Modifier steps for the formula built above — key_values can't be used for
# meta_data because its value itself contains "=" (e.g. name_prefix=Custom )
Given("the fund formula {string} has roll_up enabled") do |name|
  @fund.fund_formulas.find_by!(name: name).update!(roll_up: true)
end

Given("the fund formula {string} has generate_ytd_qtly enabled") do |name|
  @fund.fund_formulas.find_by!(name: name).update!(generate_ytd_qtly: true)
end

Given("the fund formula {string} has meta_data {string}") do |name, meta_data|
  @fund.fund_formulas.find_by!(name: name).update!(meta_data: meta_data)
end

Then("each commitment should have a generated account entry {string} with amount cents {string}") do |name, cents|
  @fund.capital_commitments.find_each do |capital_commitment|
    ae = AccountEntry.where(
      capital_commitment_id: capital_commitment.id,
      name: name,
      generated: true,
      cumulative: false
    ).last
    expect(ae).to be_present, "expected generated entry '#{name}' for commitment #{capital_commitment.folio_id}"
    expect(ae.amount_cents).to eq(cents.to_i)
  end
end

# Entry-type-scoped variant — needed when the old generate_ytd_qtly path and a
# Multiple formula generate same-named entries with different entry types in
# one run (e.g. "Quarterly Management Fees" as Expense and as Reporting)
Then("each commitment should have a generated account entry {string} of type {string} with amount cents {string}") do |name, entry_type, cents|
  @fund.capital_commitments.find_each do |capital_commitment|
    ae = AccountEntry.where(
      capital_commitment_id: capital_commitment.id,
      name: name,
      entry_type: entry_type,
      generated: true,
      cumulative: false
    ).last
    expect(ae).to be_present, "expected generated entry '#{name}' (#{entry_type}) for commitment #{capital_commitment.folio_id}"
    expect(ae.amount_cents).to eq(cents.to_i)
  end
end

# Fund-level rollups created by RollupAsFundAccountEntry have no commitment and
# are cumulative — one per generated entry name.
Then("the fund should have a cumulative fund level entry {string} with amount cents {string}") do |name, cents|
  ae = AccountEntry.fund_entries.where(
    fund_id: @fund.id,
    name: name,
    generated: true,
    cumulative: true
  ).last
  expect(ae).to be_present, "expected fund level rollup entry '#{name}'"
  expect(ae.amount_cents).to eq(cents.to_i)
end

# Commitment-level cumulative rollups created by BulkInsertData when the
# formula has roll_up enabled — one per commitment per prefixed name.
Then("each commitment should have a cumulative rollup entry {string} with amount cents {string}") do |name, cents|
  @fund.capital_commitments.find_each do |capital_commitment|
    ae = AccountEntry.where(
      capital_commitment_id: capital_commitment.id,
      name: name,
      generated: true,
      cumulative: true
    ).last
    expect(ae).to be_present, "expected cumulative rollup entry '#{name}' for commitment #{capital_commitment.folio_id}"
    expect(ae.amount_cents).to eq(cents.to_i)
  end
end

# Exact-count assertion — catches duplicated entries after a re-run, which the
# .last-based amount assertions above would silently mask.
Then("there should be exactly {string} generated entries named {string}") do |count, name|
  expect(AccountEntry.where(fund_id: @fund.id, name: name, generated: true, cumulative: false).count).to eq(count.to_i)
end

# The explanation's first element is the formula that was eval'ed — for
# GenerateAccountEntryMultiple this must be the per-name substituted formula.
Then("the generated account entry {string} explanation should contain:") do |name, expected_formula|
  ae = AccountEntry.where(fund_id: @fund.id, name: name, generated: true, cumulative: false).last
  expect(ae).to be_present, "expected generated entry '#{name}'"
  expect(ae.explanation.first).to include(expected_formula.strip)
end
