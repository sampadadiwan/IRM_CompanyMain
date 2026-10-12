# Step definitions for features/fund/financial_statements/*.feature — fund financial statements
# built from account entries. Worked examples (H/E/X) are listed in
# openspec/changes/fund-financial-statements/design.md#worked-examples
#
# Amounts in tables and steps are in currency units ("45,200", "(1,150)" or "-1,150"); the models
# store cents.

# "45,200" / "(1,150)" / "-1,150" -> cents
def fs_cents(text)
  text = text.to_s.strip
  negative = text.start_with?("-") || (text.start_with?("(") && text.end_with?(")"))
  value = text.delete("(),-").to_d * 100
  negative ? -value : value
end

# Waits for a background request (redirect after a click) to land before a database assertion
def fs_eventually(timeout: 8)
  deadline = Time.current + timeout
  begin
    yield
  rescue RSpec::Expectations::ExpectationNotMetError, ActiveRecord::RecordNotFound
    raise if Time.current > deadline

    sleep 0.2
    retry
  end
end

def fs_date(text)
  Date.parse(text.to_s)
end

def fs_account(name)
  FinancialStatementAccount.find_by!(fund_id: @fund.id, name:)
end

def fs_preview!
  @fs_result = FinancialStatementCalculator.call(fund: @fund, start_date: @fs_start, end_date: @fs_end)
end

def fs_check(key_label)
  key = FinancialStatementCalculator::CHECK_LABELS.key(key_label) || key_label
  checks = @fs_statement ? @fs_statement.reload.checks_list : @fs_result.checks
  check = checks.find { |c| c["key"] == key }
  expect(check).not_to be_nil, "No check #{key_label}; got #{checks.pluck('key').inspect}"
  check
end

# A statement set's rendered statement by name (FinancialStatementPresenter shape)
def fs_rendered(statement_name, source: nil)
  statements = (source || @fs_statement.reload).statements
  statement = statements.find { |s| s["name"] == statement_name }
  expect(statement).not_to be_nil, "No statement #{statement_name}; got #{statements.pluck('name').inspect}"
  statement
end

def fs_row(statement, label)
  row = statement["rows"].find { |r| r["label"] == label }
  expect(row).not_to be_nil, "No row #{label} in #{statement['name']}; got #{statement['rows'].pluck('label').inspect}"
  row
end

def fs_create_entries(table, folio: nil)
  table.hashes.each do |row|
    AccountEntry.create!(entity_id: @fund.entity_id, fund: @fund, entry_type: row["entry_type"], name: row["name"],
                         reporting_date: fs_date(row["date"]), amount_cents: fs_cents(row["amount"]),
                         cumulative: row["cumulative"].to_s.strip == "yes",
                         capital_commitment: folio, folio_id: folio&.folio_id)
  end
end

### Setup ######################################################################

# Shared setup of design.md#worked-examples: Alpha Capital, Meera (company admin), Alpha Fund I in
# USD, set up for statements with a January financial year
Given('Alpha Fund I is set up for financial statements') do
  steps %(
    Given there is a user "first_name=Meera;last_name=Admin" for an entity "name=Alpha Capital;entity_type=Investment Fund;currency=USD"
    Given the user has role "company_admin"
    Given there is a fund "name=Alpha Fund I;currency=USD;unit_types=A1" for the entity
  )
  @meera = @user
  FinancialStatementSetup.ensure!(@fund)
  @fund.financial_statement_setting.update!(fiscal_year_start_month: 1)
end

Given('Alpha Fund I is not set up for financial statements') do
  steps %(
    Given there is a user "first_name=Meera;last_name=Admin" for an entity "name=Alpha Capital;entity_type=Investment Fund;currency=USD"
    Given the user has role "company_admin"
    Given there is a fund "name=Alpha Fund I;currency=USD;unit_types=A1" for the entity
  )
  @meera = @user
end

# | name | type | behaviour | flip | — accounts are placed on their default statement, as the UI does
Given('the fund has statement accounts:') do |table|
  setup = FinancialStatementSetup.new(@fund)
  table.hashes.each do |row|
    account = FinancialStatementAccount.create!(fund: @fund, entity_id: @fund.entity_id, name: row["name"], account_type: row["type"],
                                                behaviour: row["behaviour"].presence, flip_sign: row["flip"].to_s.strip == "yes")
    setup.place_account(account) unless row["placed"].to_s.strip == "no"
  end
end

# | entry_type | name | account |   (account "Excluded" excludes; blank name = any name)
Given('the mapping rules:') do |table|
  table.hashes.each do |row|
    excluded = row["account"] == "Excluded"
    FinancialStatementMappingRule.create!(fund: @fund, entity_id: @fund.entity_id, entry_type: row["entry_type"], name: row["name"].to_s,
                                          excluded:, account: excluded ? nil : fs_account(row["account"]))
  end
end

# | entry_type | name | date | amount | cumulative |
Given('fund-level entries:') do |table|
  fs_create_entries(table)
end

Given('folio {string} has entries:') do |folio_id, table|
  fs_create_entries(table, folio: @arc_commitments.fetch(folio_id))
end

Given('the financial year starts in month {int}') do |month|
  @fund.financial_statement_setting.update!(fiscal_year_start_month: month)
end

Given('the NAV entry is {string} {string}') do |entry_type, name|
  @fund.financial_statement_setting.update!(nav_entry_type: entry_type, nav_entry_name: name)
end

Given('the partners\' capital entry is {string} {string}') do |entry_type, name|
  @fund.financial_statement_setting.update!(capital_entry_type: entry_type, capital_entry_name: name)
end

### Preview (calculator) ######################################################

When('I preview from {string} to {string}') do |from, to|
  @fs_start = fs_date(from)
  @fs_end = fs_date(to)
  fs_preview!
end

Then('the preview of {string} for {string} is {string}') do |account, figure, amount|
  value = @fs_result.figures.dig(fs_account(account).id, figure)
  expect(value.to_d).to eq(fs_cents(amount)), "#{account} #{figure}: expected #{amount}, got #{value.to_d / 100}"
end

Then('the check {string} is {string}') do |label, status|
  expect(fs_check(label)["status"]).to eq(status)
end

Then('the check {string} fails by {string}') do |label, amount|
  check = fs_check(label)
  expect(check["status"]).to eq("failed")
  expect(check["diff"].to_d.abs).to eq(fs_cents(amount))
end

Then('the check {string} is skipped with {string}') do |label, note|
  check = fs_check(label)
  expect(check["status"]).to eq("skipped")
  expect(check["note"]).to include(note)
end

Then('there is a {string} warning mentioning {string}') do |label, text|
  checks = @fs_statement ? @fs_statement.reload.checks_list : @fs_result.checks
  key = FinancialStatementCalculator::CHECK_LABELS.key(label)
  warning = checks.find { |c| c["status"] == "warning" && c["key"] == key && c["note"].include?(text) }
  expect(warning).not_to be_nil, "No #{label} warning mentioning #{text}; got #{checks.select { |c| c['status'] == 'warning' }.inspect}"
end

Then('there are no warnings') do
  expect(@fs_result.checks.select { |c| c["status"] == "warning" }).to be_empty
end

Then('{string} {string} is unmapped with {string} this period') do |entry_type, name, amount|
  row = @fs_result.unmapped.find { |u| u["entry_type"] == entry_type && u["name"] == name }
  expect(row).not_to be_nil, "Not unmapped: #{entry_type} · #{name}; unmapped: #{@fs_result.unmapped.inspect}"
  expect(row["period"].to_d).to eq(fs_cents(amount))
end

Then('{string} {string} is not unmapped') do |entry_type, name|
  expect(@fs_result.unmapped.any? { |u| u["entry_type"] == entry_type && u["name"] == name }).to be(false)
end

Then('nothing is unmapped') do
  expect(@fs_result.unmapped).to be_empty
end

# Rendered statement of a preview (no record), e.g. the Changes statement's Distributions row
Then('the previewed {string} shows {string} of {string} for {string}') do |statement_name, label, amount, column|
  preview = FinancialStatementPreview.new(fund: @fund, start_date: @fs_start, end_date: @fs_end)
  row = fs_row(fs_rendered(statement_name, source: preview), label)
  expect(row["values"][column].to_d).to eq(fs_cents(amount))
end

### Browser: login and pages ##################################################

Given('I am logged in as Meera') do
  @user = @meera
  steps %(
    And I am signed in as the current user
  )
end

When('I open the Mapping tab for {string} to {string}') do |from, to|
  visit financial_statement_mappings_path(fund_id: @fund.id, period_start: from, period_end: to)
  expect(page).to have_css("#fs_tabs")
end

When('I open the Layout tab for {string}') do |statement_name|
  definition = FinancialStatementDefinition.find_by!(fund_id: @fund.id, name: statement_name)
  visit financial_statement_definitions_path(fund_id: @fund.id, definition_id: definition.id)
  expect(page).to have_css("#fs_layout_rows")
end

When('I add the account {string} of type {string}') do |name, type_label|
  visit new_financial_statement_account_path(fund_id: @fund.id)
  fill_in "Account name", with: name
  select type_label, from: "Type"
  click_on "Add account"
end

Then('I do not see {string}') do |text|
  expect(page).to have_no_content(text)
end

Then('the account {string} is a {string} {string} account') do |name, type, behaviour|
  fs_eventually do
    account = fs_account(name)
    expect([account.account_type, account.behaviour]).to eq([type, behaviour])
  end
end

Then('the fund has its statement formula') do
  fs_eventually do
    formula = FundFormula.find_by(fund_id: @fund.id, rule_type: "GenerateFinancialStatementLines")
    expect(formula).to be_present
    expect(formula.enabled).to be(true)
    expect(formula.tag_list).to eq([FundFormula::FINANCIAL_STATEMENTS_TAG])
  end
end

Then('the fund has the core statements {string}') do |names|
  fs_eventually do
    expect(FinancialStatementDefinition.where(fund_id: @fund.id).where.not(kind: "schedule").ordered.pluck(:name)).to eq(names.split(" | "))
  end
end

Then('{string} is on the {string} under {string}') do |account_name, statement_name, heading|
  definition = FinancialStatementDefinition.find_by!(fund_id: @fund.id, name: statement_name)
  rows = fs_eventually { definition.layout_rows.reload.to_a.tap { |r| expect(r.map(&:financial_statement_account_id)).to include(fs_account(account_name).id) } }
  account_row = rows.find { |r| r.financial_statement_account_id == fs_account(account_name).id }
  expect(account_row).not_to be_nil, "#{account_name} is not on #{statement_name}"
  heading_row = rows[0...rows.index(account_row)].rfind { |r| r.row_type == "heading" }
  expect(heading_row&.label).to eq(heading)
end

Then('the Unmapped list shows {string} {string} with {string}') do |entry_type, name, amount|
  within("#fs_unmapped_table") do
    row = find("tr", text: name)
    expect(row).to have_content(entry_type)
    expect(row).to have_content(amount)
  end
end

Then('the Unmapped list is empty') do
  expect(page).to have_css("#fs_unmapped_none")
end

When('I click Map on {string}') do |name|
  within("#fs_unmapped_table") { find("tr", text: name).click_on("Map") }
end

When('I send it to {string}') do |account_name|
  select account_name, from: "Goes to"
  click_on "Save rule"
end

Then('the Mapping preview of {string} this period is {string}') do |account_name, amount|
  within("#fs_account_#{fs_account(account_name).id}") { expect(find(".fs-preview-period")).to have_content(amount) }
end

When('I change the rule for {string} {string} to {string}') do |entry_type, name, target|
  rule = FinancialStatementMappingRule.find_by!(fund_id: @fund.id, entry_type:, name:)
  within("#fs_rule_#{rule.id}") { click_on "Edit" }
  select target, from: "Goes to"
  click_on "Save rule"
end

When('I delete the account {string}') do |name|
  within("#fs_account_#{fs_account(name).id}") { click_on "Delete" }
  within("#confirmModal") { click_on "Proceed" }
end

When('I rename the statement to {string}') do |name|
  click_on "Rename"
  fill_in "Name", with: name
  click_on "Save"
end

When('I add a schedule {string} for a period') do |name|
  visit financial_statement_definitions_path(fund_id: @fund.id)
  click_on "+ Add schedule"
  fill_in "Name", with: name
  select "For a period (this period, year to date, last year) — like the P&L", from: "Columns"
  click_button "Add schedule", exact: true
end

When('I move {string} up') do |label|
  within("#fs_layout_rows") { find("tr", text: label).click_on("↑") }
end

Then('the layout of {string} lists {string} before {string}') do |statement_name, first, second|
  definition = FinancialStatementDefinition.find_by!(fund_id: @fund.id, name: statement_name)
  fs_eventually do
    labels = definition.layout_rows.reload.map(&:display_label)
    expect(labels.index(first)).to be < labels.index(second)
  end
end

Then('the previewed {string} shows {string} of {string} for {string} with rows:') do |statement_name, label, amount, column, _table|
  step %(the previewed "#{statement_name}" shows "#{label}" of "#{amount}" for "#{column}")
end

# | label | subtotal_of |   (subtotal_of: labels joined with " + ")
Given('the {string} has a subtotal {string} of {string}') do |statement_name, label, parts|
  definition = FinancialStatementDefinition.find_by!(fund_id: @fund.id, name: statement_name)
  ids = parts.split(" + ").map { |part| definition.layout_rows.find { |r| r.display_label == part }.id }
  definition.layout_rows.create!(fund: @fund, entity_id: @fund.entity_id, row_type: "subtotal", label:, subtotal_of: ids,
                                 position: definition.layout_rows.maximum(:position) + 1)
end

Then('destroying the core statement {string} is refused with {string}') do |name, message|
  definition = FinancialStatementDefinition.find_by!(fund_id: @fund.id, name:)
  expect(definition.destroy).to be(false)
  expect(definition.errors.full_messages.to_sentence).to include(message)
  expect(FinancialStatementDefinition.exists?(definition.id)).to be(true)
end

Given('a statements run wrote {string} lines for {string}') do |account_name, date|
  formula = FundFormula.find_by!(fund_id: @fund.id, rule_type: "GenerateFinancialStatementLines")
  AccountEntry.create!(entity_id: @fund.entity_id, fund: @fund, entry_type: FinancialStatementCalculator::FS_ENTRY_TYPE,
                       name: "#{FinancialStatementCalculator::FS_NAME_PREFIX}#{account_name}",
                       reporting_date: fs_date(date), amount_cents: 123_400, generated: true, fund_formula_id: formula.id,
                       json_fields: { "fs_account_id" => fs_account(account_name).id, "column" => "period" })
end

### Generation (statements run) ###############################################

def fs_fs_entries
  AccountEntry.where(fund_id: @fund.id, entry_type: FinancialStatementCalculator::FS_ENTRY_TYPE, deleted_at: nil)
end

Given('a successful accounting run from {string} to {string}') do |from, to|
  @accounting_run = AllocationRun.create!(entity_id: @fund.entity_id, fund: @fund, user: @meera, start_date: fs_date(from), end_date: fs_date(to),
                                          run_allocations: true, status: "Success")
end

Given('a locked successful accounting run from {string} to {string}') do |from, to|
  step %(a successful accounting run from "#{from}" to "#{to}")
  @accounting_run.update!(locked: true)
end

Given('an allocation run is in progress on the fund') do
  AllocationRun.create!(entity_id: @fund.entity_id, fund: @fund, user: @meera, start_date: Date.new(2026, 4, 1), end_date: Date.new(2026, 6, 30),
                        run_allocations: true, status: "Pending")
end

Given('the statement formula is disabled') do
  FundFormula.find_by!(fund_id: @fund.id, rule_type: "GenerateFinancialStatementLines").update!(enabled: false)
end

# Generates (the statements run runs inline in test); a refusal is kept for the Then steps
When('statements are generated for {string} to {string}') do |from, to|
  @fs_refusal = nil
  @fs_statement = FinancialStatementGenerate.call(fund: @fund, start_date: fs_date(from), end_date: fs_date(to), user: @meera)
rescue FinancialStatementGenerate::Refused => e
  @fs_refusal = e.message
end

# X11: the engine's failure propagates out of the inline job; the run and the set record it
When('statements are generated for {string} to {string} and the run fails') do |from, to|
  allow(FinancialStatementCalculator).to receive(:call).and_raise(StandardError, "mapping exploded")
  begin
    FinancialStatementGenerate.call(fund: @fund, start_date: fs_date(from), end_date: fs_date(to), user: @meera)
  rescue StandardError => e
    Rails.logger.info("X11 expected failure: #{e.message}")
  end
  @fs_statement = FinancialStatement.find_by!(fund_id: @fund.id, start_date: fs_date(from), end_date: fs_date(to))
  allow(FinancialStatementCalculator).to receive(:call).and_call_original
end

Then('generation is refused with {string}') do |message|
  expect(@fs_refusal).to include(message)
end

Then('the statement set is {string}') do |state|
  expect(@fs_statement.reload.state).to eq(state)
end

Then('the statement set was built from the accounting run') do
  expect(@fs_statement.reload.accounting_allocation_run_id).to eq(@accounting_run.id)
end

Then('the statements run covers only {string}') do |date|
  run = @fs_statement.reload.statements_allocation_run
  expect([run.start_date, run.end_date]).to eq([fs_date(date), fs_date(date)])
  expect(run.tag_list).to eq(FundFormula::FINANCIAL_STATEMENTS_TAG)
end

Then('the statement lines include {string} of {string} dated {string}') do |name, amount, date|
  entry = fs_fs_entries.find_by(name:, reporting_date: fs_date(date))
  expect(entry).not_to be_nil, "No Financial Statement entry #{name}; got #{fs_fs_entries.pluck(:name).inspect}"
  expect(entry.amount_cents.to_d).to eq(fs_cents(amount))
  expect(entry.capital_commitment_id).to be_nil
end

Then('there are {int} statement lines') do |count|
  expect(fs_fs_entries.count).to eq(count)
end

Then('there are no folio statement lines') do
  expect(fs_fs_entries.where.not(capital_commitment_id: nil)).to be_empty
end

Given('I remember the fund\'s accounting entries') do
  @fs_remembered = AccountEntry.where(fund_id: @fund.id).where.not(entry_type: FinancialStatementCalculator::FS_ENTRY_TYPE).order(:id).pluck(:id, :amount_cents)
end

Then('the fund\'s accounting entries are unchanged') do
  current = AccountEntry.where(fund_id: @fund.id).where.not(entry_type: FinancialStatementCalculator::FS_ENTRY_TYPE).order(:id).pluck(:id, :amount_cents)
  expect(current).to eq(@fs_remembered)
end

Given('I remember the statement lines') do
  @fs_remembered_lines = fs_fs_entries.order(:id).pluck(:id, :amount_cents)
end

Then('the statement lines are unchanged') do
  expect(fs_fs_entries.order(:id).pluck(:id, :amount_cents)).to eq(@fs_remembered_lines)
end

Then('the statement lines were replaced') do
  ids = fs_fs_entries.pluck(:id)
  expect(ids & @fs_remembered_lines.map(&:first)).to be_empty
end

# E12: an ordinary (untagged) allocation run, exactly as the allocate screen starts one
When('an ordinary allocation run is run for {string} to {string}') do |from, to|
  run = AllocationRun.create!(entity_id: @fund.entity_id, fund: @fund, user: @meera, start_date: fs_date(from), end_date: fs_date(to), run_allocations: true)
  AccountEntryAllocationJob.perform_now(@fund.id, fs_date(from), fs_date(to), rule_for: "", tag_list: nil, run_allocations: true, explain: true,
                                                                              user_id: @meera.id, generate_soa: false, fund_ratios: false, sample: false, allocation_run_id: run.id)
end

Then('there is one statement set for {string} to {string}') do |from, to|
  expect(FinancialStatement.where(fund_id: @fund.id, start_date: fs_date(from), end_date: fs_date(to)).count).to eq(1)
end

When('the statement set is locked by Meera') do
  FinancialStatementLock.call(@fs_statement.reload, user: @meera)
end

When('the statements run is locked from the allocation runs list') do
  @fs_statement.reload.statements_allocation_run.update!(locked: true)
end

# X4: the allocate screen's lock check is unchanged — a locked accounting run still blocks an ordinary run
Then('an ordinary run for {string} to {string} is still blocked by the locked accounting run') do |from, to|
  expect(AllocationRun.locked_and_overlapping(@fund.id, fs_date(from), fs_date(to))).to be_present
end

Then('the {string} statement shows {string} of {string} for {string}') do |statement_name, label, amount, column|
  row = fs_row(fs_rendered(statement_name), label)
  expect(row["values"][column].to_d).to eq(fs_cents(amount))
end

Given('{string} is also placed on {string}') do |account_name, statement_name|
  definition = FinancialStatementDefinition.find_by(fund_id: @fund.id, name: statement_name) ||
               FinancialStatementDefinition.create!(fund: @fund, entity_id: @fund.entity_id, name: statement_name, kind: "schedule",
                                                    column_style: "for_period", position: 10)
  definition.layout_rows.create!(fund: @fund, entity_id: @fund.entity_id, row_type: "account", financial_statement_account_id: fs_account(account_name).id,
                                 position: (definition.layout_rows.maximum(:position) || 0) + 1)
end

### Statement set: view, lock, drift, comparatives, downloads ##################

Given('Priya has read-only access to the fund') do
  @priya = FactoryBot.create(:user, entity: @fund.entity, first_name: "Priya", last_name: "Viewer")
  @priya.add_role :employee
  access = AccessRight.new(entity_id: @fund.entity_id, owner: @fund, user_id: @priya.id)
  access.permissions.set(:read)
  access.save!
end

Given('Omar works for another entity') do
  other = FactoryBot.create(:entity, name: "Other Capital", entity_type: "Investment Fund")
  @omar = FactoryBot.create(:user, entity: other, first_name: "Omar")
  @omar.add_role :company_admin
end

Given('I am logged in as Priya') do
  @user = @priya
  steps %(
    And I am signed in as the current user
  )
end

When('I open the statement set') do
  visit financial_statement_path(@fs_statement)
  expect(page).to have_css("#fs_period")
end

When('I open the statement set on {string}') do |statement_name|
  definition = FinancialStatementDefinition.find_by!(fund_id: @fund.id, name: statement_name)
  visit financial_statement_path(@fs_statement, definition_id: definition.id)
  expect(page).to have_css("#fs_statement_title", text: statement_name)
end

When('I lock the statement set') do
  click_on "Lock"
  expect(page).to have_css("#confirmModal", visible: true)
  @fs_popup_text = find("#confirmModal").text
  within("#confirmModal") { click_on "Proceed" }
end

Then('the popup said {string}') do |text|
  expect(@fs_popup_text).to include(text)
end

Then('the statement set shows {string}') do |text|
  expect(page).to have_content(text)
end

Then('the statement set is locked with a frozen copy') do
  @fs_statement.reload
  expect(@fs_statement.status).to eq("locked")
  expect(@fs_statement.frozen_data["figures"]).to be_present
  expect(@fs_statement.frozen_data["statements"]).to be_present
  expect(@fs_statement.statements_allocation_run.locked).to be(true)
  expect(@fs_statement.locked_by).to eq(@meera)
end

Then('Lock is disabled with {string}') do |reason|
  expect(page).to have_css("#fs_lock_disabled[data-bs-title*='#{reason}']")
end

Then('locking directly is refused with {string}') do |message|
  expect { FinancialStatementLock.call(@fs_statement.reload, user: @meera) }.to raise_error(FinancialStatementLock::Refused, /#{Regexp.escape(message)}/)
  expect(@fs_statement.reload.status).to eq("draft")
end

When('the {string} {string} entry of {string} is changed to {string}') do |entry_type, name, date, amount|
  AccountEntry.find_by!(fund_id: @fund.id, entry_type:, name:, reporting_date: fs_date(date)).update!(amount_cents: fs_cents(amount))
end

Then('there is no drift banner') do
  expect(page).to have_no_css("#fs_drift_banner")
end

Then('the drift banner lists {string}') do |text|
  within("#fs_drift_banner") { expect(page).to have_content(text) }
end

Then('the statement set\'s PDF shows {string}') do |text|
  html = FinancialStatementPdf.new(@fs_statement.reload).html
  expect(ActionView::Base.full_sanitizer.sanitize(html)).to include(text)
end

Then('the {string} column of {string} reads {string} for {string}') do |column, statement_name, amount, label|
  statement = fs_rendered(statement_name)
  expect(fs_row(statement, label)["values"][column].to_d).to eq(fs_cents(amount))
end

Then('the {string} column of {string} is headed with {string}') do |column, statement_name, note|
  statement = fs_rendered(statement_name)
  heading = statement["columns"].find { |c| c["key"] == column }
  expect(heading["note"]).to include(note)
end

When('the allocation runs for the period are unlocked by Meera') do
  @fs_demoted = FinancialStatementUnlockGuard.demote!(FinancialStatementUnlockGuard.affected(@fund, @fs_statement.start_date, @fs_statement.end_date), user: @meera)
end

Then('the frozen copy shows {string} of {string} for {string}') do |account_name, amount, figure|
  value = @fs_statement.reload.frozen_data.dig("figures", fs_account(account_name).id.to_s, figure)
  expect(value.to_d).to eq(fs_cents(amount))
end

Then('the Excel download has the sheets {string}') do |names|
  stream = FinancialStatementXlsx.new(@fs_statement.reload).to_stream
  path = Rails.root.join("tmp/fs_test_#{SecureRandom.hex(4)}.xlsx")
  File.binwrite(path, stream.read)
  expect(Roo::Spreadsheet.open(path.to_s).sheets).to eq(names.split(" | "))
ensure
  FileUtils.rm_f(path) if path
end

Then('every page of the PDF download says {string}') do |text|
  pdf = FinancialStatementPdf.new(@fs_statement.reload).render
  reader = PDF::Reader.new(StringIO.new(pdf))
  expect(reader.page_count).to be >= 1
  reader.pages.each { |page| expect(page.text).to include(text) }
end

Then('Priya sees no Generate, Lock or editing buttons') do
  expect(page).to have_no_css("#fs_lock_btn")
  expect(page).to have_no_css("#fs_lock_disabled")
  expect(page).to have_no_css("#fs_regenerate_btn")
  expect(page).to have_css("#fs_excel_btn")
end

Then('Priya cannot lock the statement set') do
  expect(Pundit.policy(@priya, @fs_statement).lock?).to be(false)
  expect(Pundit.policy(@priya, @fs_statement).show?).to be(true)
end

Then('Omar cannot find the statement set') do
  scope = FinancialStatementPolicy::Scope.new(@omar, FinancialStatement).resolve
  expect(scope.exists?(@fs_statement.id)).to be(false)
  expect(Pundit.policy(@omar, @fs_statement).show?).to be(false)
end

### Unlock guard ###############################################################

Given('Ravi is tagged FundAccounting') do
  @ravi = FactoryBot.create(:user, entity: @fund.entity, first_name: "Ravi", last_name: "Iyer", tag_list: "FundAccounting")
  @ravi.add_role :company_admin
end

Given('statements for {string} to {string} are generated and locked') do |from, to|
  steps %(
    Given a successful accounting run from "#{from}" to "#{to}"
    When statements are generated for "#{from}" to "#{to}"
    And the statement set is locked by Meera
  )
  @fs_locked_sets ||= []
  @fs_locked_sets << @fs_statement
  @accounting_run.update!(locked: true)
end

# Unlock all is a support action (AllocationRunPolicy#unlock_all?)
Given('Meera also has the support role') do
  @meera.add_role :support
end

When('I open the fund\'s allocation runs') do
  visit allocate_form_fund_path(@fund, run_allocations: true)
  expect(page).to have_css("#allocation_run_#{@accounting_run.id}")
end

When('I click Unlock on the accounting run') do
  within("#allocation_run_#{@accounting_run.id}") { find("button[aria-label='Unlock']").click }
end

Then('the unlock popup says {string}') do |text|
  within("#confirmModal") { expect(page).to have_content(text) }
end

When('I confirm the unlock') do
  within("#confirmModal") { click_on "Proceed" }
end

When('I cancel the unlock') do
  within("#confirmModal") { click_on "Cancel" }
end

When('I click Unlock all') do
  click_on "Unlock All"
end

Then('the accounting run is {string}') do |state|
  fs_eventually { expect(@accounting_run.reload.locked).to eq(state == "locked") }
end

Then('the locked statement sets are {string}') do |status|
  fs_eventually { @fs_locked_sets.each { |s| expect(s.reload.status).to eq(status) } }
end

Then('the statement set keeps its frozen copy') do
  @fs_locked_sets.each { |s| expect(s.reload.frozen_data["figures"]).to be_present }
end

Then('Ravi gets {int} financial statement notification(s)') do |count|
  fs_eventually do
    expect(Noticed::Notification.where(recipient: @ravi, type: "FinancialStatementNotifier::Notification").count).to eq(count)
  end
end

Then('Ravi\'s notification lists {string}') do |text|
  notification = Noticed::Notification.where(recipient: @ravi, type: "FinancialStatementNotifier::Notification").last
  expect(notification.message).to include(text)
end

Then('Ravi gets an email {string}') do |subject|
  fs_eventually do
    email = ActionMailer::Base.deliveries.rfind { |m| m.to.include?(@ravi.email) }
    expect(email).not_to be_nil
    expect(email.subject).to include(subject)
  end
end

Then('the plain unlock confirmation is used') do
  within("#allocation_run_#{@accounting_run.id}") do
    expect(page).to have_css("button[aria-label='Unlock'][data-confirm]")
  end
end

# The existing Unlock button carries a plain data-confirm; accept the browser dialog if one appears
When('I unlock the accounting run accepting the plain confirmation') do
  accept_confirm(wait: 2) { within("#allocation_run_#{@accounting_run.id}") { find("button[aria-label='Unlock']").click } }
rescue Capybara::ModalNotFound
  Rails.logger.info("E8: no browser confirm dialog shown; the click submitted directly")
end

### AI draft (LLM stubbed) #####################################################

# Writes a PDF whose text is the given lines (rendered by wkhtmltopdf, so pdftotext can read it back)
Given('a statements PDF {string} printing:') do |filename, text|
  html = "<html><body><pre style='font-size:14px'>#{ERB::Util.html_escape(text)}</pre></body></html>"
  @fs_upload_path = Rails.root.join("tmp/#{filename}")
  File.binwrite(@fs_upload_path, FerrumPdf.render_pdf(html:))
end

# X18: a PDF with no text layer
Given('a scanned PDF {string} with no text') do |filename|
  @fs_upload_path = Rails.root.join("tmp/#{filename}")
  File.binwrite(@fs_upload_path, FerrumPdf.render_pdf(html: "<html><body><div style='width:300px;height:300px;background:#333'></div></body></html>",
                                                      pdf_options: { print_background: true }))
end

Given('a Word file {string}') do |filename|
  @fs_upload_path = Rails.root.join("tmp/#{filename}")
  File.write(@fs_upload_path, "not a statement")
end

Given('the AI answers:') do |json|
  answer = Struct.new(:content).new(json)
  allow(LlmService).to receive(:ruby_llm_chat).and_return(double("chat", ask: answer))
end

Given('the AI is unavailable') do
  allow(LlmService).to receive(:ruby_llm_chat).and_raise(StandardError, "LLM unavailable")
end

# Creates the suggestion and runs the job, as the upload form does (the job is inline in test)
When('Meera asks for a draft from it as at {string} with the P&L from {string}') do |as_at, period_start|
  @fs_suggestion = FinancialStatementMappingSuggestion.new(fund: @fund, entity_id: @fund.entity_id, user: @meera, as_at_date: fs_date(as_at),
                                                           period_start: fs_date(period_start), file: File.open(@fs_upload_path))
  @fs_suggestion_saved = @fs_suggestion.save
  FinancialStatementMappingSuggestJob.perform_now(@fs_suggestion.id) if @fs_suggestion_saved
end

Then('the draft is {string}') do |status|
  expect(@fs_suggestion.reload.status).to eq(status)
end

Then('the draft fails with {string}') do |message|
  expect(@fs_suggestion.reload.status).to eq("failed")
  expect(@fs_suggestion.error).to include(message)
end

Then('the upload is refused with {string}') do |message|
  expect(@fs_suggestion_saved).to be(false)
  expect(@fs_suggestion.errors.full_messages.to_sentence).to include(message)
end

def fs_draft_line(label)
  line = @fs_suggestion.reload.lines.find { |l| l["label"] == label }
  expect(line).not_to be_nil, "No draft line #{label}; got #{@fs_suggestion.lines.pluck('label').inspect}"
  line
end

Then('the draft line {string} is {string} against the existing mapping') do |label, change|
  expect(fs_draft_line(label)["change"]).to eq(change)
end

Then('the draft dropped {string} {string} because {string}') do |entry_type, name, reason|
  dropped = Array(@fs_suggestion.reload.proposal["dropped"])
  expect(dropped).to include(hash_including("entry_type" => entry_type, "name" => name, "reason" => reason))
end

When('Meera moves {string} {string} to the draft line {string}') do |entry_type, name, label|
  @fs_suggestion.reload.move!(entry_type, name, fs_draft_line(label)["key"])
end

When('Meera discards the draft') do
  @fs_suggestion.reload.discard!
end

When('Meera approves the draft') do
  @fs_suggestion.reload.approve!(@meera)
end

Then('the fund has {int} statement account(s)') do |count|
  expect(FinancialStatementAccount.where(fund_id: @fund.id).count).to eq(count)
end

Then('the fund has a rule {string} {string} to {string}') do |entry_type, name, account_name|
  rule = FinancialStatementMappingRule.find_by!(fund_id: @fund.id, entry_type:, name:)
  expect(rule.account&.name).to eq(account_name)
end

Then('the {string} statement is named {string}') do |kind, name|
  expect(FinancialStatementDefinition.find_by!(fund_id: @fund.id, kind:).name).to eq(name)
end

# Browser upload of the same file through the form
When('I upload it on the Suggest page') do
  visit new_financial_statement_mapping_suggestion_path(fund_id: @fund.id)
  attach_file "Statements (PDF or Excel, up to 20 MB)", @fs_upload_path.to_s
  click_on "Read the statements"
  expect(page).to have_css("#fs_suggestion_actions")
  @fs_suggestion = FinancialStatementMappingSuggestion.where(fund_id: @fund.id).order(:id).last
end

When('I approve the draft on screen') do
  click_on "Approve draft"
  within("#confirmModal") { click_on "Proceed" }
  expect(page).to have_content("Mapping saved from the draft.")
end

Given('FinancialStatementSetup has run for the fund') do
  FinancialStatementSetup.ensure!(@fund)
end

### Statements tab and Settings tab (browser) ##################################

When('I generate statements on the Statements tab for {string} to {string}') do |from, to|
  visit financial_statements_path(fund_id: @fund.id)
  # The locale date inputs: type into the visible field, the controller fills the hidden ISO one
  find("#financial_statement_start_date").set(from)
  find("#financial_statement_end_date").set(to)
  click_on "Generate statements"
  # The action-summary popup comes first; its text is kept for the Then steps
  expect(page).to have_css("#confirmModal", visible: true)
  @fs_popup_text = find("#confirmModal").text
  within("#confirmModal") { click_on "Proceed" }
  expect(page).to have_css("#fs_period")
  @fs_statement = FinancialStatement.where(fund_id: @fund.id).order(:id).last
end

Then('the Statements tab lists the set as {string}') do |status|
  visit financial_statements_path(fund_id: @fund.id)
  within("#financial_statement_#{@fs_statement.id}") { expect(page).to have_content(status) }
end

When('I set the NAV entry to {string} {string} on the Settings tab') do |entry_type, name|
  visit edit_financial_statement_setting_path(@fund.financial_statement_setting)
  fill_in "financial_statement_setting_nav_entry_type", with: entry_type
  fill_in "financial_statement_setting_nav_entry_name", with: name
  click_on "Save settings"
  expect(page).to have_content("Settings saved.")
  @fund.financial_statement_setting.reload
end

### Statements preview page (own browser tab) ###################################

When('I open the statements preview for {string} to {string}') do |from, to|
  visit preview_financial_statement_mappings_path(fund_id: @fund.id, period_start: from, period_end: to)
  expect(page).to have_css("#fs_preview_statement_tabs")
end

When('I open the {string} preview tab') do |statement_name|
  within("#fs_preview_statement_tabs nav") { click_on statement_name }
  @fs_preview_pane = find("#fs_preview_statement_tabs .tab-pane.active")
  expect(@fs_preview_pane).to have_css("table.fs-statement[data-statement='#{statement_name}']")
end

Then('the preview tab shows {string} with {string}') do |label, amount|
  within(@fs_preview_pane) { expect(find("table.fs-statement tr", text: label)).to have_content(amount) }
end

Then('the preview tab lists the account {string} fed by {string}') do |account, entry|
  within(@fs_preview_pane.find("table.fs-preview-accounts")) { expect(find("tr", text: account)).to have_content(entry) }
end

Then('the preview tab does not list the account {string}') do |account|
  within(@fs_preview_pane.find("table.fs-preview-accounts")) { expect(page).to have_no_css("td", text: /\A#{Regexp.escape(account)}/) }
end

Then('the Balance Sheet line reads {string} and balances for {string}') do |text, column|
  statement = @fs_statement.reload.statements.find { |st| st["kind"] == "balance_sheet" }
  line = statement["balance_line"][column]
  assets, liabilities, capital = text.split(/ = | \+ /).map { |v| fs_cents(v) }
  expect([line["assets"].to_d, line["liabilities"].to_d, line["capital"].to_d]).to eq([assets, liabilities, capital])
  expect(line["balanced"]).to be(true)
end

# E31: there is no real fund entry named "Professional fees", so any folio entry by that name would
# have come from the statement line
Then('no folio entry {string} was allocated') do |name|
  expect(AccountEntry.where(fund_id: @fund.id, name:).where.not(capital_commitment_id: nil)).not_to exist
end

# Stored statement lines all carry the "FS · " prefix, so none shares a name with an account (or with
# the fund's own entries named like one)
Then('no statement line is named like an account') do
  names = fs_fs_entries.distinct.pluck(:name)
  # Plain Ruby: `all` here is Capybara's finder, not the RSpec matcher
  unprefixed = names.reject { |n| n.start_with?(FinancialStatementCalculator::FS_NAME_PREFIX) }
  expect(unprefixed).to be_empty, "Statement lines without the prefix: #{unprefixed.inspect}"
  expect(names & FinancialStatementAccount.where(fund_id: @fund.id).pluck(:name)).to be_empty
end

Then('the statement set offers {string}') do |label|
  expect(page).to have_link(label)
end

Then('the Settings tab says {string}') do |text|
  within("#fs_nav_status") { expect(page).to have_content(text) }
end

When('I open How checks work') do
  find("#fs_checks_help_link").click
  expect(page).to have_css("#fs_checks_help", visible: true)
end

Then('the checks explanation says {string}') do |text|
  within("#fs_checks_help") { expect(page).to have_content(text) }
  within("#fs_checks_help") { find("button.btn-close").click }
end

Then('the draft line {string} is a {string} row') do |label, role|
  expect(fs_draft_line(label)["role"]).to eq(role)
end

Then('the draft line {string} is not sign-flipped') do |label|
  expect(fs_draft_line(label)["flip_sign"]).to be(false)
end

# Mapping-only review (no amounts): what feeds a line, unused entries, the page's badges
Then('the draft line {string} is fed by {string} and {string}') do |label, first, second|
  view = ApplicationController.new.view_context
  entries = view.fs_draft_line_entries(@fs_suggestion.reload, fs_draft_line(label))
  expect(entries).to include(first, second)
end

Then('the draft lists {string} {string} as not used') do |entry_type, name|
  view = ApplicationController.new.view_context
  unused = view.fs_draft_entries_overview(@fs_suggestion.reload).select { |e| e[:state] == :unused }.map { |e| [e[:entry_type], e[:name]] }
  expect(unused).to include([entry_type, name])
end

Then('the draft lists no unused entries') do
  view = ApplicationController.new.view_context
  expect(view.fs_draft_entries_overview(@fs_suggestion.reload).select { |e| e[:state] == :unused }).to be_empty
end

Then('the draft did not drop {string} {string}') do |entry_type, name|
  dropped = Array(@fs_suggestion.reload.proposal["dropped"]).map { |d| [d["entry_type"], d["name"]] }
  expect(dropped).not_to include([entry_type, name])
end

Then('the draft page shows the line {string} as {string}') do |label, status|
  line = fs_draft_line(label)
  within("#line-#{line['key']}") { expect(page).to have_css(".badge", text: status) }
end

Then('the draft page compares no amounts') do
  expect(page).to have_no_content("Printed amount")
  expect(page).to have_no_content("CapHive figure")
  expect(page).to have_content("amounts aren't compared")
end
