# Step definitions for features/fund/fund_totals_tie_out.feature.
#
# Shares its Background and its run/entry steps with
# features/step_definitions/allocation_run_checker.rb — the allocation engine is never run
# here, entries are built by hand, which is the only way to make a run that is deliberately
# wrong. Assertions go against AllocationRunTieOut rather than the rendered page: the sheet's
# arithmetic is what these scenarios are about, and the page is one partial over it.
#
# features/support/env.rb excludes `allocation_runs` and `account_entries` from
# DatabaseCleaner's truncation, so rows there survive between scenarios and are cleaned up
# here rather than by touching the shared exclusion list.
After('@tie_out') do
  next if @fund.nil?

  TieOutFigure.where(fund_id: @fund.id).delete_all
  AccountEntry.where(fund_id: @fund.id).delete_all
  AllocationRun.where(fund_id: @fund.id).delete_all
end

### Helpers ####################################################################

# A fresh sheet: the report's aggregate pass is re-run so each assertion sees current entries.
def tie_out_sheet
  report = AccountEntryReport.new(fund: @fund, start_date: @allocation_run.start_date,
                                  end_date: @allocation_run.end_date,
                                  allocation_run_id: @allocation_run.id)
  AllocationRunTieOut.new(report: report, fund: @fund, allocation_run: @allocation_run, with_figures: true)
end

def tie_out_row!(name)
  row = tie_out_sheet.rows.find { |r| r.name == name }
  expect(row).not_to be_nil, "No row for #{name.inspect}; got #{tie_out_sheet.rows.map(&:name).inspect}"
  row
end

# Writes a figure exactly as TieOutFiguresController does, so the scenarios exercise the same
# upsert-or-delete the screen performs.
def tie_out_save!(name, typed)
  figure = TieOutFigure.find_or_initialize_by(
    fund_id: @fund.id, entity_id: @fund.entity_id, as_of_date: @allocation_run.end_date,
    capital_commitment_id: nil, name: name, entry_type: nil
  )
  cents = TieOutFigure.parse_amount_cents(typed)
  if cents.nil?
    figure.destroy if figure.persisted?
  else
    figure.update!(amount_cents: cents, user: @user)
  end
end

### Setup ######################################################################

Given('there is an enabled fund formula {string} at sequence {string}') do |name, sequence|
  FundFormula.create!(entity_id: @fund.entity_id, fund: @fund, name: name, entry_type: "Expense",
                      enabled: true, rule_type: "GenerateAccountEntry", formula: "0",
                      sequence: sequence.to_i)
end

Given('there is a fund formula {string} at sequence {string} computing {string}') do |name, sequence, formula|
  FundFormula.create!(entity_id: @fund.entity_id, fund: @fund, name: name, entry_type: "Expense",
                      enabled: true, rule_type: "GenerateAccountEntry", formula: formula,
                      sequence: sequence.to_i)
end

Given('there is an investor user on the entity') do
  @tie_out_investor = FactoryBot.create(:user, entity: @entity)
  @tie_out_investor.add_role :investor
end

### Actions ####################################################################

When('I open the tie-out sheet for that run') do
  @tie_out = tie_out_sheet
end

When("I enter {string} as the fund's figure for {string} on that run") do |typed, name|
  tie_out_save!(name, typed)
end

When("I clear the fund's figure for {string} on that run") do |name|
  tie_out_save!(name, "")
end

When("the fund's figure {string} is read") do |typed|
  @tie_out_parsed = TieOutFigure.parse_amount_cents(typed)
end

# A re-run is a NEW AllocationRun over the same period; the previous attempt's entries are
# hard-deleted by the engine, which is why figures are keyed to the period and not the run.
When('the same period is run again') do
  AccountEntry.where(fund_id: @fund.id, allocation_run_id: @allocation_run.id).delete_all
  @allocation_run = WithValidationRules.skip do
    AllocationRun.create!(entity_id: @fund.entity_id, fund: @fund, user: @user,
                          start_date: @allocation_run.start_date, end_date: @allocation_run.end_date,
                          status: "Success", run_allocations: true)
  end
end

When('I open the folios behind {string} for that run') do |name|
  @tie_out_folios = tie_out_sheet.folios(name)
end

When('that investor tries to record a figure') do
  figure = TieOutFigure.new(entity_id: @fund.entity_id, fund: @fund, as_of_date: @allocation_run.end_date,
                            name: "Setup Fee", amount_cents: 0, user: @tie_out_investor)
  @tie_out_permitted = TieOutFigurePolicy.new(@tie_out_investor, figure).create?
end

When('the company admin tries to record a figure') do
  figure = TieOutFigure.new(entity_id: @fund.entity_id, fund: @fund, as_of_date: @allocation_run.end_date,
                            name: "Setup Fee", amount_cents: 0, user: @user)
  @tie_out_permitted = TieOutFigurePolicy.new(@user, figure).create?
end

### Assertions #################################################################

# Always two decimals, the way the screen shows money. BigDecimal#to_s drops trailing zeros
# ("400.0") and by default prints scientific notation ("0.5e2").
def tie_out_money(cents) = format("%.2f", (cents.to_d / 100).round(2))

Then('the tie-out row {string} should show our total as {string}') do |name, major_units|
  expect(tie_out_money(tie_out_row!(name).system_cents)).to eq(major_units)
end

Then('the tie-out row {string} should be {string}') do |name, state|
  expected = state.tr(" ", "_").to_sym
  expect(tie_out_row!(name).state).to eq(expected)
end

Then('the tie-out row {string} should show a difference of {string}') do |name, major_units|
  expect(tie_out_money(tie_out_row!(name).difference_cents)).to eq(major_units)
end

Then('the tie-out sheet should have a row for {string}') do |name|
  expect(tie_out_sheet.rows.map(&:name)).to include(name)
end

Then('the tie-out rows should be in the order {string}') do |names|
  expected = names.split(",").map(&:strip)
  actual = tie_out_sheet.rows.map(&:name).select { |name| expected.include?(name) }
  expect(actual).to eq(expected)
end

Then('it should be understood as {string}') do |cents|
  expect(@tie_out_parsed&.to_i&.to_s.to_s).to eq(cents)
end

Then('there should be no stored figure for {string}') do |name|
  expect(TieOutFigure.where(fund_id: @fund.id, name: name)).to be_none
end

Then('the tie-out sheet should count {int} entered, {int} matching and {int} differing') do |entered, matching, differing|
  sheet = tie_out_sheet
  expect([sheet.entered_count, sheet.match_count, sheet.differs_count]).to eq([entered, matching, differing])
end

Then('the folio list should name {string} before {string}') do |first, second|
  folio_ids = @tie_out_folios[:rows].map(&:first)
  expect(folio_ids.index(first)).to be < folio_ids.index(second)
end

Then('the folio list should report {int} folios in total') do |count|
  expect(@tie_out_folios[:total_count]).to eq(count)
end

Then('recording the figure should be refused') do
  expect(@tie_out_permitted).to be false
end

Then('recording the figure should be allowed') do
  expect(@tie_out_permitted).to be true
end

Then('the row {string} should be built from {string}') do |name, dependencies|
  expect(tie_out_row!(name).dependencies.map(&:name)).to eq(dependencies.split(",").map(&:strip))
end

Then('the row {string} should be top-level') do |name|
  expect(tie_out_row!(name).top).to be(true)
end

Then('the row {string} should have no dependencies') do |name|
  row = tie_out_row!(name)
  expect(row.dependencies).to be_empty, "Expected none, got #{row.dependencies.map(&:name).inspect}"
end
