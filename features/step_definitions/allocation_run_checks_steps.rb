# Step definitions for features/fund/allocation_run_checks.feature -- a fund's own pre-run and
# post-run checks (FundFormulas with rule type PreRunCheck / PostRunCheck).
#
# Most scenarios run the checks directly through AccountEntryAllocation::RunChecks against entries
# built by hand, reusing the allocation run checker's steps ("the fund has folios", "there is a
# finished allocation run", "the run produced ...", "I check that allocation run") and its
# @allocation_run_checker cleanup hook. The end-to-end scenarios run the real engine through
# "the Allocation Run ... is created for the ..." instead.

### Helpers ####################################################################

def arcc_formula!(name)
  FundFormula.find_by!(fund_id: @fund.id, name: name)
end

def arcc_result!(name)
  result = Array(@arcc_results).find { |r| r["name"] == name }
  expect(result).not_to be_nil, "No check result named #{name.inspect}; got #{Array(@arcc_results).pluck('name').inspect}"
  result
end

def arcc_text(result)
  ([result["summary"]] + Array(result["rows"]).flatten.map(&:to_s)).join(" ")
end

def arcc_run_checks(kind, allocation_run:, start_date:, end_date:)
  rule_type = AccountEntryAllocation::RunChecks::KINDS.fetch(kind.to_sym)
  formulas = FundFormula.where(fund_id: @fund.id, rule_type:).order(:sequence).to_a
  @arcc_results = AccountEntryAllocation::RunChecks.new(formulas, kind: kind.to_sym, fund: @fund,
                                                                  start_date:, end_date:, allocation_run:).call
end

### Check formulas #############################################################

Given('a {string} fund formula {string} without an entry type') do |rule_type, name|
  @arcc_formula = FundFormula.new(fund: @fund, entity_id: @fund.entity_id, name:, rule_type:,
                                  formula: "true", rule_for: "accounting", enabled: true)
end

Given('the check formula has generate_ytd_qtly and roll_up enabled') do
  @arcc_formula.generate_ytd_qtly = true
  @arcc_formula.roll_up = true
end

Then('the check formula should be valid') do
  expect(@arcc_formula.valid?).to be(true), @arcc_formula.errors.full_messages.inspect
end

Then('the check formula should be invalid on {string}') do |attribute|
  expect(@arcc_formula.valid?).to be(false)
  expect(@arcc_formula.errors[attribute.to_sym]).to be_present, @arcc_formula.errors.full_messages.inspect
end

Then('the check formula should be invalid on {string} and {string}') do |first, second|
  expect(@arcc_formula.valid?).to be(false)
  [first, second].each do |attribute|
    expect(@arcc_formula.errors[attribute.to_sym]).to be_present, @arcc_formula.errors.full_messages.inspect
  end
end

Given('the fund has a {string} check {string} with formula:') do |rule_type, name, formula|
  FundFormula.create!(fund: @fund, entity_id: @fund.entity_id, name:, rule_type:, formula: formula.strip,
                      rule_for: "accounting", enabled: true)
end

Given('the fund has a {string} formula {string}') do |rule_type, name|
  FundFormula.create!(fund: @fund, entity_id: @fund.entity_id, name:, rule_type:, formula: "0",
                      entry_type: "Allocated #{name}", rule_for: "accounting", enabled: true)
end

# Same as above; "an" reads better before a vowel ("an AllocateAccountEntry-Name formula").
Given('the fund has an {string} formula {string}') do |rule_type, name|
  step %(the fund has a "#{rule_type}" formula "#{name}")
end

Given('the fund has an {string} formula {string} with formula:') do |rule_type, name, formula|
  FundFormula.create!(fund: @fund, entity_id: @fund.entity_id, name:, rule_type:, formula: formula.strip,
                      entry_type: "Allocated #{name}", rule_for: "accounting", enabled: true)
end

Then('the dependency graph should list only {string}') do |name|
  graph = FundFormulaDependencyGraph.new(FundFormula.where(fund_id: @fund.id).order(:sequence))
  expect(graph.formulas.map(&:name)).to eq([name])
end

Then("the allocation engine's formulas should be only {string}") do |name|
  ctx = { fund: @fund, rule_for: nil, tag_list: nil }
  formulas = AccountEntryAllocation::RunFormulas.allocate.send(:get_formulas, ctx)
  expect(formulas.map(&:name)).to eq([name])
end

### Data #######################################################################

# Columns: name, entry_type, amount (amount_cents), reporting_date, generated, and optionally
# folio (a folio from "the fund has folios"; blank = fund level), parent ("portfolio investment",
# "portfolio company" or blank) and custom_fields ("key=value,key=value"; a blank value is kept
# as an empty string, which counts as missing).
Given('these account entries were uploaded:') do |table|
  table.hashes.each do |row|
    folio_id = row["folio"].presence
    commitment = folio_id && @arc_commitments.fetch(folio_id)
    parent = case row["parent"].to_s.strip
             when "portfolio investment" then @portfolio_investment
             when "portfolio company" then @portfolio_investment.portfolio_company
             end
    json_fields = row["custom_fields"].to_s.split(",").to_h do |pair|
      key, value = pair.split("=", 2)
      [key.strip, value.to_s.strip]
    end

    AccountEntry.create!(entity_id: @fund.entity_id, fund_id: @fund.id, name: row["name"], entry_type: row["entry_type"],
                         amount_cents: BigDecimal(row["amount"]), reporting_date: Date.parse(row["reporting_date"]),
                         generated: row["generated"] == "true", cumulative: false,
                         capital_commitment_id: commitment&.id, folio_id:,
                         parent_type: parent&.class&.name, parent_id: parent&.id, parent_name: parent&.to_s,
                         json_fields:)
  end
end

# What AllocateEntry writes: one generated, non-cumulative entry per folio, carrying the formula's
# id and entry type and the fund-level entry's name.
Given('the run allocated {string} of {string} to folio {string} and {string} to folio {string} by formula {string}') do |name, amount_a, folio_a, amount_b, folio_b, formula_name|
  formula = arcc_formula!(formula_name)
  { folio_a => amount_a, folio_b => amount_b }.each do |folio_id, amount|
    arc_entry(name:, entry_type: formula.entry_type, amount_cents: BigDecimal(amount), folio_id:,
              capital_commitment_id: arc_commitment!(folio_id).id, allocation_run_id: @allocation_run.id,
              fund_formula_id: formula.id)
  end
end

# What AllocatePortfolioInvestments writes: one entry per folio per investment, named after the
# formula and parented on the investment. The share is split across the folios so the total is
# exactly percent of the investment's amount.
Given('the run allocated {string} of the portfolio investment amount to the folios by formula {string}') do |percent, formula_name|
  formula = arcc_formula!(formula_name)
  pi = @portfolio_investment.reload
  # A factory investment can come out with no amount; the comparison needs a non-zero one.
  pi.update_column(:amount_cents, 1_000_000) if pi.amount_cents.to_d.zero?
  total = (pi.amount_cents.to_d * BigDecimal(percent.delete("%")) / 100).round(2)
  first_share = (total / 2).round(2)
  shares = [first_share, total - first_share]

  @arc_commitments.values.first(2).zip(shares).each do |commitment, share|
    arc_entry(name: formula.name, entry_type: formula.entry_type, amount_cents: share,
              folio_id: commitment.folio_id, capital_commitment_id: commitment.id,
              allocation_run_id: @allocation_run.id, fund_formula_id: formula.id,
              parent_type: "PortfolioInvestment", parent_id: pi.id, parent_name: pi.to_s)
  end
end

# Results as RunFormulas#persist_check_results stores them.
Given('the run stored these check results:') do |table|
  results = table.hashes.map do |row|
    { "kind" => row["kind"], "formula_id" => nil, "sequence" => nil, "name" => row["name"],
      "result" => row["result"], "summary" => row["summary"], "columns" => [], "rows" => [],
      "filters" => [], "truncated" => 0, "duration_ms" => 1 }
  end
  AllocationRunReport.create!(allocation_run: @allocation_run, entity_id: @allocation_run.entity_id,
                              fund_id: @allocation_run.fund_id, user: @user, status: "Pending",
                              json_fields: { "run_checks" => results })
end

Given("I remember the fund's account entries") do
  @arcc_entries_before = AccountEntry.where(fund_id: @fund.id).order(:id, :reporting_date).pluck(:id, :amount_cents)
  expect(@arcc_entries_before).not_to be_empty
end

### Running the checks ##########################################################

When('the {string} checks are run for that allocation run') do |kind|
  arcc_run_checks(kind, allocation_run: @allocation_run, start_date: @allocation_run.start_date, end_date: @allocation_run.end_date)
end

When('the {string} checks are run without an allocation run for {string} to {string}') do |kind, start_date, end_date|
  arcc_run_checks(kind, allocation_run: nil, start_date: Date.parse(start_date), end_date: Date.parse(end_date))
end

### Assertions ##################################################################

Then('check {string} should have result {string} mentioning {string}') do |name, result, text|
  check = arcc_result!(name)
  expect(check["result"]).to eq(result), "#{name} was #{check['result']}: #{check['summary']}"
  expect(arcc_text(check)).to include(text)
end

Then('check {string} should mention {string}') do |name, text|
  expect(arcc_text(arcc_result!(name))).to include(text)
end

Then('check {string} should not mention {string}') do |name, text|
  # A report finding (code like "1.6.2") or a check result from RunChecks (a check's name).
  if name.match?(/\A\d+(\.\d+)*\z/)
    finding = arc_finding!(name)
    expect(([finding["summary"]] + finding["rows"].flatten.map(&:to_s)).join(" ")).not_to include(text)
  else
    expect(arcc_text(arcc_result!(name))).not_to include(text)
  end
end

Then('the latest allocation run status should start with {string}') do |prefix|
  @allocation_run = AllocationRun.where(fund_id: @fund.id).order(:id).last
  expect(@allocation_run.status.to_s).to start_with(prefix)
end

Then("the fund's account entries should be unchanged") do
  after = AccountEntry.where(fund_id: @fund.id).order(:id, :reporting_date).pluck(:id, :amount_cents)
  expect(after).to eq(@arcc_entries_before)
end

Then('the latest allocation run should have a report') do
  @allocation_run = AllocationRun.where(fund_id: @fund.id).order(:id).last
  @report = AllocationRunReport.find_by(allocation_run_id: @allocation_run.id)
  expect(@report).to be_present, "Expected a report for allocation run #{@allocation_run.id} (status #{@allocation_run.status.inspect})"
  expect(@report.run_checks).to be_present
end

Then('the latest allocation run should have no report') do
  allocation_run = AllocationRun.where(fund_id: @fund.id).order(:id).last
  expect(AllocationRunReport.where(allocation_run_id: allocation_run.id)).not_to exist
end
