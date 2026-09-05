# Step definitions for features/fund/allocation_run_checker.feature.
#
# The allocation engine is never run here. Every scenario builds the account entries the
# engine would have produced by hand, which is the only way to make a run that is deliberately
# WRONG — the point of most of these checks. Cucumber uses the :inline ActiveJob adapter, so
# AllocationRunReportJob finishes before the next step.
#
# features/support/env.rb excludes `allocation_runs` from DatabaseCleaner's truncation for
# suite-wide speed, so rows there survive between scenarios and can collide with a later
# scenario's fund (MySQL's TRUNCATE resets auto-increment on the tables it does clean, so a
# fund id is reused). The same applies to `account_entries`, which check 2.2 reads from
# inception and would otherwise pick up an earlier scenario's rows. Clean up both here rather
# than touching the shared exclusion list the whole suite relies on.
After('@allocation_run_checker') do
  next if @fund.nil?

  AllocationRunReport.where(fund_id: @fund.id).delete_all
  AccountEntry.where(fund_id: @fund.id).delete_all
  AllocationRun.where(fund_id: @fund.id).delete_all
end

### Helpers ####################################################################

# "key=value;key=value" -> hash, with booleans and blanks coerced.
def arc_attrs(args)
  args.split(";").each_with_object({}) do |pair, h|
    k, v = pair.split("=", 2)
    v = v.to_s.strip
    h[k.strip.to_sym] = case v
                        when "true" then true
                        when "false" then false
                        when "" then nil
                        else v
                        end
  end
end

def arc_date(value)
  value.is_a?(Date) ? value : Date.parse(value.to_s)
end

def arc_commitment!(folio_id)
  @arc_commitments.fetch(folio_id)
end

# One account entry, defaulted to the shape the engine gives a folio-level, non-cumulative,
# generated entry for the run under test.
def arc_entry(attrs)
  AccountEntry.create!({ entity_id: @fund.entity_id, fund_id: @fund.id, entry_type: "Fee",
                         generated: true, cumulative: false,
                         reporting_date: @allocation_run.end_date }.merge(attrs))
end

# Runs the checks the way the controller does — a Pending report, then the job.
def arc_check!(user: @user)
  @report = AllocationRunReport.find_or_initialize_by(allocation_run: @allocation_run)
  @report.assign_attributes(entity_id: @allocation_run.entity_id, fund_id: @allocation_run.fund_id,
                            user: user, status: "Pending", message: nil, checked_at: nil, json_fields: {})
  @report.save!
  AllocationRunReportJob.perform_now(@report.id)
  @report.reload
end

def arc_finding!(code)
  finding = @report.findings.find { |f| f["code"] == code }
  expect(finding).not_to be_nil, "No finding #{code}; got #{@report.findings.map { |f| f['code'] }.inspect}"
  finding
end

### Setup ######################################################################

# A commitment needs an investor, a fund close and a unit type the fund actually offers, so
# each folio gets its own holder. folio_currency matches the fund's so AccountEntry's
# set_folio_amount callback is a straight pass-through and no exchange rate is needed.
Given('the fund has folios {string}') do |folio_ids|
  @arc_commitments = {}
  unit_type = @fund.unit_types.to_s.split(",").first&.strip
  folio_ids.split(",").map(&:strip).each_with_index do |folio_id, index|
    holder = FactoryBot.create(:entity, name: "Folio #{folio_id} Holder", entity_type: "Investment Fund")
    investor = Investor.create!(entity: @entity, investor_entity: holder,
                                investor_name: "Folio #{folio_id} Holder",
                                primary_email: "folio#{folio_id}@example.com",
                                category: "Co-Investor")
    @arc_commitments[folio_id] = CapitalCommitment.create!(
      entity: @entity, fund: @fund, investor: investor,
      folio_id: folio_id, folio_currency: @fund.currency,
      unit_type: unit_type, fund_close: "First Close",
      # Dated well before every period used in this feature, so check 1.3 always expects them.
      commitment_date: Date.new(2023, 4, 1) + index.days,
      folio_committed_amount_cents: 1_000_000
    )
  end
end

Given('there is a finished allocation run {string}') do |args|
  attrs = arc_attrs(args)
  attrs[:start_date] = arc_date(attrs[:start_date])
  attrs[:end_date] = arc_date(attrs[:end_date])
  # "status=" in the scenario means "the run never reported one".
  attrs[:status] = "Success" unless attrs.key?(:status)
  @allocation_run = WithValidationRules.skip do
    AllocationRun.create!({ entity_id: @fund.entity_id, fund: @fund, user: @user,
                            run_allocations: true }.merge(attrs))
  end
end

Given('there is a locked allocation run {string}') do |args|
  attrs = arc_attrs(args)
  WithValidationRules.skip do
    AllocationRun.create!(entity_id: @fund.entity_id, fund: @fund, user: @user,
                          start_date: arc_date(attrs[:start_date]), end_date: arc_date(attrs[:end_date]),
                          status: "Success", run_allocations: true, locked: true)
  end
end

Given('there is an enabled fund formula {string}') do |name|
  FundFormula.create!(entity_id: @fund.entity_id, fund: @fund, name: name, entry_type: "Expense",
                      enabled: true, rule_type: "GenerateAccountEntry", formula: "0")
end

### The entries a run produced ##################################################

Given('the run produced {string} of {string} for folio {string} and {string} for folio {string}') do |name, amount_a, folio_a, amount_b, folio_b|
  { folio_a => amount_a, folio_b => amount_b }.each do |folio_id, amount|
    arc_entry(name: name, amount_cents: BigDecimal(amount), folio_id: folio_id,
              capital_commitment_id: arc_commitment!(folio_id).id,
              allocation_run_id: @allocation_run.id)
  end
end

Given('the run produced {string} of {string} for folio {string}') do |name, amount, folio_id|
  arc_entry(name: name, amount_cents: BigDecimal(amount), folio_id: folio_id,
            capital_commitment_id: arc_commitment!(folio_id).id,
            allocation_run_id: @allocation_run.id)
end

# RollupAsFundAccountEntry writes the fund total as a cumulative entry with no commitment.
Given('the run produced a fund total of {string} for {string}') do |amount, name|
  arc_entry(name: name, amount_cents: BigDecimal(amount), cumulative: true,
            capital_commitment_id: nil, rule_for: "reporting",
            allocation_run_id: @allocation_run.id)
end

Given('the run produced cumulative entries matching the folio entries for {string}') do |name|
  @arc_commitments.each do |folio_id, commitment|
    total = AccountEntry.where(fund_id: @fund.id, name: name, cumulative: false,
                               capital_commitment_id: commitment.id).sum(:amount_cents)
    arc_entry(name: name, amount_cents: total, cumulative: true, folio_id: folio_id,
              capital_commitment_id: commitment.id, rule_for: "reporting")
  end
end

Given('the run produced a cumulative of {string} for folio {string} for {string}') do |amount, folio_id, name|
  commitment = arc_commitment!(folio_id)
  arc_entry(name: name, amount_cents: BigDecimal(amount), cumulative: true, folio_id: folio_id,
            capital_commitment_id: commitment.id, rule_for: "reporting")
end

Given('the run produced percentages of {string} for folio {string} and {string} for folio {string}') do |pct_a, folio_a, pct_b, folio_b|
  { folio_a => pct_a, folio_b => pct_b }.each do |folio_id, pct|
    arc_entry(name: "Setup Fee Percentage", entry_type: "Percentage", amount_cents: BigDecimal(pct),
              folio_id: folio_id, capital_commitment_id: arc_commitment!(folio_id).id,
              allocation_run_id: @allocation_run.id)
  end
end

# An entry dated into a period that is already closed — the cumulative at the period end no
# longer accounts for it, which is exactly what check 2.2 exists to catch.
Given('someone back-dates a {string} entry of {string} for folio {string} into {string}') do |name, amount, folio_id, date|
  arc_entry(name: name, amount_cents: BigDecimal(amount), folio_id: folio_id,
            capital_commitment_id: arc_commitment!(folio_id).id,
            reporting_date: arc_date(date))
end

When('the fund total for {string} is corrected to {string}') do |name, amount|
  AccountEntry.where(fund_id: @fund.id, name: name, cumulative: true, capital_commitment_id: nil)
              .update_all(amount_cents: BigDecimal(amount))
end

### Running the checks ##########################################################

# Backdates the run itself. What the checker can look at depends on when the run was made:
# entries only carry a run id from 2025-03-29, and runs only carry a status from 2024-07-28.
Given('that run was made on {string}') do |date|
  @allocation_run.update_column(:created_at, arc_date(date).to_time)
  @allocation_run.reload
end

When('I check that allocation run') do
  @arc_entries_before = AccountEntry.where(fund_id: @fund.id).order(:id, :reporting_date).pluck(:id, :amount_cents)
  arc_check!
end

Given('that allocation run has been checked') do
  arc_check!
end

Given('there is another employee without rights on the fund') do
  @arc_other_user = FactoryBot.create(:user, entity: @entity)
  @arc_other_user.add_role :employee
end

When('that employee tries to check the allocation run') do
  report = AllocationRunReport.new(entity_id: @fund.entity_id, fund_id: @fund.id,
                                   user: @arc_other_user, allocation_run: @allocation_run)
  @arc_permitted = AllocationRunReportPolicy.new(@arc_other_user, report).create?
end

Then('the check should be refused') do
  expect(@arc_permitted).to be false
end

### Assertions ##################################################################

Then('the report status should be {string}') do |status|
  expect(@report.status).to eq(status),
                            "Expected #{status}, got #{@report.status}: #{@report.findings.map { |f| [f['code'], f['severity'], f['summary']] }.inspect}"
end

Then('check {string} should be {string}') do |code, severity|
  finding = arc_finding!(code)
  expect(finding["severity"]).to eq(severity), "#{code} was #{finding['severity']}: #{finding['summary']}"
end

Then('check {string} should be {string} mentioning {string}') do |code, severity, text|
  finding = arc_finding!(code)
  expect(finding["severity"]).to eq(severity), "#{code} was #{finding['severity']}: #{finding['summary']}"
  haystack = ([finding["summary"]] + finding["rows"].flatten).join(" ")
  expect(haystack).to include(text)
end

Then('the allocation run should still be unlocked') do
  expect(@allocation_run.reload.locked).to be_falsey
end

Then('no account entry should have been created or changed by the check') do
  after = AccountEntry.where(fund_id: @fund.id).order(:id, :reporting_date).pluck(:id, :amount_cents)
  expect(after).to eq(@arc_entries_before)
end

Then('the summary should say nothing was checked') do
  expect(@report.nothing_checked?).to be(true),
                                      "Expected a report where nothing was verified, got #{@report.status} with #{@report.count_at('pass')} passing checks"
end

Then('the allocation run should have exactly one report') do
  expect(AllocationRunReport.where(allocation_run_id: @allocation_run.id).count).to eq(1)
end

### UI ##########################################################################

When('I visit the allocation screen of the fund') do
  visit allocate_form_fund_path(@fund, run_allocations: true)
  expect(page).to have_content("Previous Runs")
end

When('I press the check button for that allocation run') do
  # Icon-only button; Capybara's :button locator matches on the title attribute.
  click_button("Check this allocation run", match: :first)
end

Then('I should be on the report page') do
  expect(page).to have_content("Allocation Run Check", wait: 10)
end

When('I open the report page') do
  visit allocation_run_report_path(@report)
  expect(page).to have_content("Allocation Run Check")
end

When('I click the report tab {string}') do |tab_name|
  click_link tab_name
end

Then('I should see the report badge {string} for that allocation run') do |status|
  within("table.jqDataTable") do
    expect(page).to have_link(status)
  end
end
