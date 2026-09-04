# frozen_string_literal: true

# Step definitions for features/ai/capital_remittance_reconciliation_agent.feature.
#
# Strategy: agent runs go through RemittanceReconciliationAgent.wtf?() directly,
# same as RtaReconciliationAgent's feature. Unlike RTA (which stubs the LLM entirely since
# extraction is AI-driven), this agent has no LLM step at all — narration parsing and matching
# are fully deterministic — so scenarios build a *real* xlsx workbook (via Axlsx) and attach it
# to a real Document, exercising the genuine Roo + BankDepositNarrationParser pipeline rather
# than stubbing it out. The summary email is asserted via ActionMailer::Base.deliveries
# (Cucumber runs the :inline ActiveJob adapter, and the agent uses deliver_now anyway).

# ── Helpers ────────────────────────────────────────────────────────────────────

def remit_call_report
  # latest: true (not plain find_by) — the idempotency scenario runs the agent twice, which
  # creates a new SupportAgentReport row per run, so a first-match-by-primary-key lookup
  # would silently return a stale report.
  SupportAgentReport.find_by(owner: @capital_call, support_agent: @remit_agent, latest: true)
end

def remit_report_json
  (remit_call_report&.json_fields || {}).deep_symbolize_keys
end

# ICICI-shape header: Sl No / Tran Id / Transaction Remarks / Withdrawal (Dr) / Deposit (Cr).
# withdrawal_amount and deposit_amount are mutually exclusive per row, same as a real
# statement — exactly one is populated, the other left blank. Tran Id is the bank's own
# transaction id ("TXN-<n>", deterministic so a scenario can refer to it) — the reference_no
# every payment applied from that row carries, which is what makes re-runs idempotent.
def icici_sheet_rows(deposits: [], withdrawals: [])
  header = ["Sl No", "Tran Id", "Transaction Remarks", "Withdrawal (Dr)", "Deposit (Cr)"]
  rows = deposits.each_with_index.map { |(narration, amount), i| [i + 1, "TXN-#{i + 1}", narration, nil, amount] }
  rows += withdrawals.each_with_index.map { |(narration, amount), i| [deposits.size + i + 1, "TXN-#{deposits.size + i + 1}", narration, amount, nil] }
  [header] + rows
end

# Axis-shape header: S.No / Particulars / Amount (INR) / Debit/Credit.
def axis_sheet_rows(deposits: [], withdrawals: [])
  header = ["S.No", "Particulars", "Amount (INR)", "Debit/Credit"]
  rows = deposits.each_with_index.map { |(narration, amount), i| [i + 1, narration, amount, "CR"] }
  rows += withdrawals.each_with_index.map { |(narration, amount), i| [deposits.size + i + 1, narration, amount, "DR"] }
  [header] + rows
end

# Builds a real xlsx workbook (via Axlsx) with one worksheet per entry in `sheet_specs` —
# each `{name:, ifsc:, table:}` — matching the real statement header shape (bank banner,
# "A/C No / IFSC" line, blank line, then the header + data rows) that
# BankDepositNarrationParser.detect_bank scans for. `ifsc: nil` omits the IFSC line
# entirely, simulating a bank the registry doesn't recognise.
def build_bank_statement_xlsx(sheet_specs)
  package = Axlsx::Package.new
  sheet_specs.each do |spec|
    package.workbook.add_worksheet(name: spec[:name]) do |sheet|
      sheet.add_row(["#{spec[:name]} Bank Account Statement"])
      sheet.add_row(spec[:ifsc] ? ["A/C No: 000000000000    IFSC: #{spec[:ifsc]}0000004    Branch: Test"] : ["A/C No: 000000000000"])
      sheet.add_row(["Statement Period: 01/06/2026 To 30/06/2026"])
      sheet.add_row([])
      spec[:table].each { |row| sheet.add_row(row) }
    end
  end
  tempfile = Tempfile.new(["bank_statement", ".xlsx"])
  package.serialize(tempfile.path)
  tempfile
end

# Attaches a freshly built workbook (one worksheet per `sheet_specs` entry) as a real Shrine
# file on a Document, the same way an operator's upload would arrive — @statement_doc is
# picked up by run_remit_agent below.
def attach_bank_statement(sheet_specs)
  tempfile = build_bank_statement_xlsx(sheet_specs)
  folder = FactoryBot.create(:folder, owner: @entity, entity: @entity)
  @statement_doc = Document.create!(
    name: "Bank Statement",
    entity: @entity,
    owner: @entity,
    folder: folder,
    user: @user,
    file: File.open(tempfile.path, "rb")
  )
end

# Accumulates one worksheet spec and rebuilds+reattaches the whole workbook — lets a scenario
# compose a multi-sheet statement one "Given the bank statement has/also has a ... sheet" step
# at a time (see the multi-sheet scenario), same shape as the RTA feature's multi-scheme
# composition via `@rta_extracted_json["schemes"] <<`.
def add_bank_statement_sheet(spec)
  @sheet_specs ||= []
  @sheet_specs << spec
  attach_bank_statement(@sheet_specs)
end

def run_remit_agent(bank_statement_document_id: :_use_doc)
  doc_id = bank_statement_document_id == :_use_doc ? @statement_doc&.id : bank_statement_document_id
  @remit_agent_result = RemittanceReconciliationAgent.wtf?(
    support_agent_id: @remit_agent.id,
    target: @capital_call,
    bank_statement_document_id: doc_id
  )
end

# An amount written with comma grouping ("10,49,763.03") is deliberately kept as a String so
# the workbook carries a text cell, the way some bank exports do — the parser must cope.
def parse_amount_table(table)
  table.hashes.map { |row| [row["narration"], row["amount"].include?(",") ? row["amount"] : row["amount"].to_f] }
end

# ── Background ─────────────────────────────────────────────────────────────────

Given('there is a RemittanceReconciliationAgent configured for the entity') do
  @remit_agent = FactoryBot.create(
    :support_agent,
    entity: @entity,
    agent_type: "RemittanceReconciliationAgent",
    name: "Remittance Reconciliation",
    enabled: true,
    llm_model: "gemini-3.7-flash",
    json_fields: {}
  )
end

Given('the RemittanceReconciliationAgent is disabled') do
  @remit_agent.update!(enabled: false)
end

Given("the agent's auto_apply_exact is {string}") do |value|
  @remit_agent.json_fields["auto_apply_exact"] = value
  @remit_agent.save!
end

Given("the agent's send_report is {string} and notify_email is {string}") do |send_report, email|
  @remit_agent.json_fields["send_report"] = send_report
  @remit_agent.json_fields["notify_email"] = email
  @remit_agent.save!
  ActionMailer::Base.deliveries.clear
end

# ── Given: remittance candidates ────────────────────────────────────────────────

# Builds one investor + CapitalCommitment (+ optional InvestorKyc) + CapitalRemittance under
# @capital_call. investor_kyc is assigned onto the commitment explicitly — CapitalCommitment
# belongs_to :investor_kyc is a real FK, not auto-resolved from the investor, so a KYC record
# floating unassociated would never be found by capital_remittance.investor_kyc.
def create_remittance_candidate(investor_name:, call_amount:, bank_account_number: nil, virtual_bank_account: nil, folio_currency: nil)
  investor_entity = FactoryBot.create(:entity, entity_type: "Individual", name: investor_name)
  investor = FactoryBot.create(:investor, entity: @entity, investor_entity: investor_entity)
  kyc = bank_account_number ? FactoryBot.create(:investor_kyc, entity: @entity, investor: investor, bank_account_number: bank_account_number) : nil
  commitment = FactoryBot.create(
    :capital_commitment, fund: @fund, entity: @entity, investor: investor, investor_kyc: kyc,
                         folio_id: "F-#{SecureRandom.hex(3)}", virtual_bank_account: virtual_bank_account,
                         folio_currency: folio_currency || @fund.currency
  )
  remittance = FactoryBot.build(
    :capital_remittance, capital_call: @capital_call, fund: @fund, entity: @entity,
                         investor: investor, capital_commitment: commitment, folio_id: commitment.folio_id,
                         call_amount: call_amount, collected_amount: 0, status: "Pending"
  )
  remittance.save(validate: false)
  # Tracked by investor name so later steps (building a fixture report, or UI assertions) can
  # look a remittance back up without needing their own instance variable per scenario.
  @remittances_by_investor ||= {}
  @remittances_by_investor[investor_name] = remittance
  remittance
end

Given('there is a remittance under the capital call for investor {string} with call amount {float}') do |investor_name, call_amount|
  create_remittance_candidate(investor_name: investor_name, call_amount: call_amount)
end

Given('there is a remittance under the capital call for investor {string} with call amount {float} and KYC bank account {string}') do |investor_name, call_amount, account|
  create_remittance_candidate(investor_name: investor_name, call_amount: call_amount, bank_account_number: account)
end

Given('there is a remittance under the capital call for investor {string} with call amount {float} and virtual bank account {string}') do |investor_name, call_amount, account|
  create_remittance_candidate(investor_name: investor_name, call_amount: call_amount, virtual_bank_account: account)
end

Given('there is a remittance under the capital call for investor {string} with call amount {float} and KYC bank account {string} and virtual bank account {string}') do |investor_name, call_amount, kyc_account, virtual_account|
  create_remittance_candidate(investor_name: investor_name, call_amount: call_amount,
                              bank_account_number: kyc_account, virtual_bank_account: virtual_account)
end

# A second commitment (and remittance) for an investor already set up above — same investor
# record and same KYC, a new folio — for the "which folio?" ambiguity case.
Given('there is a second remittance under the capital call for the same investor {string} with call amount {float}') do |investor_name, call_amount|
  original = @remittances_by_investor.fetch(investor_name)
  commitment = FactoryBot.create(
    :capital_commitment, fund: @fund, entity: @entity, investor: original.investor, investor_kyc: original.investor_kyc,
                         folio_id: "F-#{SecureRandom.hex(3)}", folio_currency: @fund.currency
  )
  remittance = FactoryBot.build(
    :capital_remittance, capital_call: @capital_call, fund: @fund, entity: @entity,
                         investor: original.investor, capital_commitment: commitment, folio_id: commitment.folio_id,
                         call_amount: call_amount, collected_amount: 0, status: "Pending"
  )
  remittance.save(validate: false)
end

# call_amount stays in fund currency (that is what the bank statement deposit is compared to);
# only the commitment's folio currency differs, so the payment's folio amount has to be derived
# through the fund's exchange rate.
Given('there is a remittance under the capital call for investor {string} with call amount {float} and KYC bank account {string} in folio currency {string}') do |investor_name, call_amount, account, folio_currency|
  create_remittance_candidate(investor_name: investor_name, call_amount: call_amount, bank_account_number: account, folio_currency: folio_currency)
end

# Test entities come with default exchange rates seeded (dated years back), so "no rate on
# file" has to be made true explicitly.
Given('there is no exchange rate from {string} to {string} for the entity') do |from, to|
  ExchangeRate.where(entity: @entity, from: from, to: to).delete_all
end

# Simulates the same statement having already been run against a different call of the same
# fund: a second CapitalCall with its own remittance for the same commitment, and a payment
# carrying the bank transaction id in question applied there.
Given('the deposit with tran id {string} was already recorded against another capital call of the fund for investor {string}') do |tran_id, investor_name|
  original = @remittances_by_investor[investor_name]
  other_call = FactoryBot.build(:capital_call, fund: @fund, entity: @entity, name: "Other Call #{SecureRandom.hex(2)}")
  other_call.save(validate: false)
  other_remittance = FactoryBot.build(
    :capital_remittance, capital_call: other_call, fund: @fund, entity: @entity,
                         investor: original.investor, capital_commitment: original.capital_commitment, folio_id: original.folio_id,
                         call_amount: original.call_amount, collected_amount: 0, status: "Pending"
  )
  other_remittance.save(validate: false)
  outcome = RemittanceDepositPaymentApplier.call(
    deposit: { "amount" => original.call_amount.to_f, "value_date" => Time.zone.today.iso8601,
               "sheet" => "ICICI", "row" => 1, "raw_narration" => "RTGS-OTHER-CALL", "tran_id" => tran_id },
    capital_remittance: other_remittance, fund: @fund
  )
  expect(outcome[:status]).to eq(:created), "fixture payment on the other call failed: #{outcome[:error]}"
end

# ── Given: bank statement setup ─────────────────────────────────────────────────

Given('the bank statement has an ICICI sheet with deposit rows:') do |table|
  add_bank_statement_sheet(name: "ICICI", ifsc: "ICIC", table: icici_sheet_rows(deposits: parse_amount_table(table)))
end

Given('the bank statement also has an Axis sheet with deposit rows:') do |table|
  add_bank_statement_sheet(name: "Axis", ifsc: "UTIB", table: axis_sheet_rows(deposits: parse_amount_table(table)))
end

Given('the bank statement has an Axis sheet with deposit rows:') do |table|
  add_bank_statement_sheet(name: "Axis", ifsc: "UTIB", table: axis_sheet_rows(deposits: parse_amount_table(table)))
end

Given('the bank statement has an ICICI sheet with a withdrawal row {string} amount {float}') do |narration, amount|
  add_bank_statement_sheet(name: "ICICI", ifsc: "ICIC", table: icici_sheet_rows(withdrawals: [[narration, amount]]))
end

Given('the bank statement has a sheet for an unrecognized bank with deposit rows:') do |table|
  add_bank_statement_sheet(name: "UnknownBank", ifsc: nil, table: icici_sheet_rows(deposits: parse_amount_table(table)))
end

# ── When ───────────────────────────────────────────────────────────────────────

When('the RemittanceReconciliationAgent runs for the capital call') do
  run_remit_agent
end

When('the RemittanceReconciliationAgent runs for the capital call without a bank statement') do
  run_remit_agent(bank_statement_document_id: nil)
end

When('the RemittanceReconciliationAgent runs again for the capital call') do
  run_remit_agent
end

# ── Then ───────────────────────────────────────────────────────────────────────

Then('a capital-call-level SupportAgentReport is saved') do
  expect(remit_call_report).to be_present
end

Then('the reconciliation report has a blocking issue matching {string}') do |text|
  issues = remit_report_json[:issues] || []
  match  = issues.any? { |i| (i[:severity] || i["severity"]).to_s == "blocking" && (i[:message] || i["message"]).to_s.include?(text) }
  expect(match).to be(true), "Expected a blocking issue containing '#{text}', got: #{issues.map { |i| i[:message] || i['message'] }.join('; ')}"
end

Then('the reconciliation report has a warning issue matching {string}') do |text|
  issues = remit_report_json[:issues] || []
  match  = issues.any? { |i| (i[:severity] || i["severity"]).to_s == "warning" && (i[:message] || i["message"]).to_s.include?(text) }
  expect(match).to be(true), "Expected a warning issue containing '#{text}', got: #{issues.map { |i| i[:message] || i['message'] }.join('; ')}"
end

Then('the report deposit_count is {int}') do |count|
  expect(remit_report_json[:deposit_count]).to eq(count)
end

Then('the report internal_count is {int}') do |count|
  expect(remit_report_json[:internal_count]).to eq(count)
end

Then('the report payments_created is {int}') do |count|
  expect(remit_report_json[:payments_created]).to eq(count)
end

Then('the report payments_already_recorded is {int}') do |count|
  expect(remit_report_json[:payments_already_recorded]).to eq(count)
end

Then('the report lists a deposit with name {string} and account {string} and confidence {string}') do |name, account, confidence|
  deposits = remit_report_json[:deposits] || []
  match = deposits.find { |d| d[:name] == name }
  expect(match).to be_present, "No deposit found with name '#{name}', got: #{deposits.pluck(:name).join(', ')}"
  expect(match[:account_number]).to eq(account)
  expect(match[:confidence]).to eq(confidence)
end

Then('the report lists a deposit with name {string} and no account number') do |name|
  deposits = remit_report_json[:deposits] || []
  match = deposits.find { |d| d[:name] == name }
  expect(match).to be_present, "No deposit found with name '#{name}', got: #{deposits.pluck(:name).join(', ')}"
  expect(match[:account_number]).to be_nil
end

Then('the report lists an internal deposit with narration {string}') do |narration|
  deposits = remit_report_json[:deposits] || []
  match = deposits.find { |d| d[:raw_narration] == narration }
  expect(match).to be_present, "No deposit found with narration '#{narration}'"
  expect(match[:internal]).to be(true)
end

def find_deposit_by_narration(narration)
  deposits = remit_report_json[:deposits] || []
  match = deposits.find { |d| d[:raw_narration] == narration }
  expect(match).to be_present, "No deposit found with narration '#{narration}', got: #{deposits.pluck(:raw_narration).join(' | ')}"
  match
end

Then('the deposit with narration {string} is tiered {string}') do |narration, tier|
  deposit = find_deposit_by_narration(narration)
  expect(deposit[:tier]).to eq(tier), "Expected tier '#{tier}' for '#{narration}', got '#{deposit[:tier]}' (reasoning: #{deposit[:reasoning]})"
end

Then('the deposit with narration {string} has source_of_funds {string}') do |narration, source_of_funds|
  deposit = find_deposit_by_narration(narration)
  expect(deposit[:source_of_funds]).to eq(source_of_funds)
end

Then('the deposit with narration {string} has amount_status {string}') do |narration, amount_status|
  deposit = find_deposit_by_narration(narration)
  expect(deposit[:amount_status]).to eq(amount_status), "Expected amount_status '#{amount_status}', got '#{deposit[:amount_status]}' (reasoning: #{deposit[:reasoning]})"
end

Then('the deposit with narration {string} has a reasoning line matching {string}') do |narration, text|
  deposit = find_deposit_by_narration(narration)
  lines = Array(deposit[:reasoning])
  expect(lines.any? { |l| l.to_s.include?(text) }).to be(true), "No reasoning line containing '#{text}' — got: #{lines.join(' | ')}"
end

Then('the deposit with narration {string} has payment_status {string}') do |narration, status|
  deposit = find_deposit_by_narration(narration)
  expect(deposit[:payment_status]).to eq(status), "Expected payment_status '#{status}', got '#{deposit[:payment_status]}' (#{deposit[:payment_error]})"
end

Then('the deposit with narration {string} has no payment_id') do |narration|
  deposit = find_deposit_by_narration(narration)
  expect(deposit[:payment_id]).to be_nil
end

Then('the deposit with narration {string} has amount {float}') do |narration, amount|
  deposit = find_deposit_by_narration(narration)
  expect(deposit[:amount]).to be_within(0.001).of(amount)
end

Then('the report payments_recorded_elsewhere is {int}') do |count|
  expect(remit_report_json[:payments_recorded_elsewhere]).to eq(count)
end

Then('exactly {int} CapitalRemittancePayment exists on the fund with reference {string}') do |count, reference|
  expect(CapitalRemittancePayment.where(fund: @fund, reference_no: reference).count).to eq(count)
end

Then('the CapitalRemittancePayment for {string} has amount {float}') do |investor_name, amount|
  payment = CapitalRemittancePayment.find_by!(capital_remittance: @remittances_by_investor[investor_name])
  expect(payment.amount.to_f).to be_within(0.01).of(amount)
end

Then('the CapitalRemittancePayment for {string} has folio amount {float}') do |investor_name, amount|
  payment = CapitalRemittancePayment.find_by!(capital_remittance: @remittances_by_investor[investor_name])
  expect(payment.folio_amount.to_f).to be_within(0.01).of(amount)
end

def reconciliation_report_emails
  ActionMailer::Base.deliveries.select { |m| m.subject.to_s.start_with?("[RECON") }
end

Then('a reconciliation report email is sent to {string} with subject matching {string}') do |email, subject_fragment|
  mail = reconciliation_report_emails.find { |m| m.to.include?(email) }
  expect(mail).to be_present, "No reconciliation email to #{email}; deliveries: #{ActionMailer::Base.deliveries.map(&:subject).join(' | ')}"
  expect(mail.subject).to include(subject_fragment)
  @reconciliation_email = mail
end

Then('the reconciliation report email mentions {string}') do |text|
  body = @reconciliation_email.html_part&.body&.decoded || @reconciliation_email.body.decoded
  expect(body).to include(text)
end

Then('no reconciliation report email is sent') do
  expect(reconciliation_report_emails).to be_empty
end

# ── Statement generator (lib/remittance_reconciliation_statement_generator.rb) ────────────
#
# Runs the real generator against the scenario's call with the default output folder, so the
# folder the rake task writes to is the one under test. The file is removed again afterwards
# (see the After hook below) so a test run never leaves workbooks in public/.

When('the statement generator runs for the capital call with bank {string}') do |bank|
  require Rails.root.join("lib/remittance_reconciliation_statement_generator")
  @generator_output = StringIO.new
  RemittanceReconciliationStatementGenerator.new(@capital_call.id, bank: bank, output: @generator_output).call
  @generated_workbook = @generator_output.string[/^Statement: (.+)$/, 1]
  expect(@generated_workbook).to be_present, "generator printed no Statement: line:\n#{@generator_output.string}"
end

Then('the generated workbook exists under {string}') do |relative_dir|
  expect(File.exist?(@generated_workbook)).to be(true)
  expect(Pathname.new(@generated_workbook).dirname).to eq(Rails.root.join(relative_dir))
end

# Round-trips the file through the same parser registry the agent uses, so the generated
# layout is proven to be one the agent can read.
Then('the generated workbook parses as an ICICI statement with {int} deposits') do |count|
  xlsx = Roo::Spreadsheet.open(@generated_workbook)
  sheet = xlsx.sheet(xlsx.sheets.first)
  expect(BankDepositNarrationParser.detect_bank(sheet)).to eq(IciciNarrationParser)
  expect(BankDepositNarrationParser.each_deposit_narration(sheet).size).to eq(count)
end

After('@generator') do
  FileUtils.rm_f(@generated_workbook) if @generated_workbook
end

# ── Phase 4 (UI) ─────────────────────────────────────────────────────────────────
#
# These scenarios visit the real Capital Call page and click real buttons — unlike the
# scenarios above (which invoke the agent directly), the panel/Confirm/Undo pieces only exist
# as controller actions + views, so they need an actual signed-in page visit to exercise.

Given('the entity has the capital_remittance_reconciliation_agent flag enabled') do
  @entity.support_agents.set!(:capital_remittance_reconciliation_agent)
end

When('I visit the capital call page as the fund admin') do
  steps %(
    Given I am at the login page
    When I fill and submit the login page
  )
  visit capital_call_path(@capital_call)
end

# "I click {string}", "I should see {string}" and "I should not see {string}" come from
# features/common.rb — do not redefine them here (Cucumber::Ambiguous).

# The run trigger lives inside the capital call's Actions dropdown (closed on load), so it
# has to be opened before the button is visible to the Playwright driver.
When('I open the capital call actions menu') do
  # By id: the Remittances tab (active by default) renders a per-row "Actions" dropdown too,
  # so a plain click_on "Actions" is ambiguous.
  find("#capital_call_actions_btn").click
end

# Undo goes through the global confirm modal (layouts/_confirm): the button click only opens
# it, Proceed submits the intercepted form.
When('I proceed with the confirmation popup') do
  expect(page).to have_css("#confirmModal", visible: true)
  within("#confirmModal") { click_on "Proceed" }
end

# The panel lives in its own tab on the capital call page (show pages keep everything in
# tabs), so it has to be opened before any of its content is visible to Playwright.
When('I open the Reconciliation tab') do
  # exact: a substring match would also hit the "Run Reconciliation" buttons.
  click_link "Reconciliation", exact: true
end

# After a Confirm / Reassign / Undo the controller redirects with ?tab=reconciliation-tab and
# the tabs controller activates it — the reviewer must not have to click the tab again.
Then('the Reconciliation tab is already open') do
  expect(page).to have_css("a.nav-link.active", text: "Reconciliation", exact_text: true)
  expect(page).to have_css("#reconciliation-tab.active")
end

Then('I should see the reconciliation panel') do
  expect(page).to have_content("Remittance Reconciliation")
end

Then('I should not see the Reconciliation tab') do
  expect(page).not_to have_link("Reconciliation", exact: true)
end

Then('I should see the run reconciliation button') do
  expect(page).to have_button("Run Reconciliation")
end

# Button-based, not text-based: plain page text would also match e.g. a user named "UndoAdmin".
Then('there is no Undo button in the reconciliation table') do
  expect(page).not_to have_button("Undo")
end

Then('there is a Confirm button in the reconciliation table') do
  expect(page).to have_button("Confirm")
end

# A locked item is a non-clickable span carrying the lock icon, not a button.
Then('the run reconciliation menu item is locked') do
  expect(page).not_to have_button("Run Reconciliation")
  expect(page).to have_css("span.dropdown-item--locked", text: "Run Reconciliation")
end

Then('I should see the payment recorded confirmation') do
  expect(page).to have_content("Payment recorded")
end

# Builds a SupportAgentReport directly with a hand-built deposits array — bypasses running the
# real agent (already covered by the scenarios above) so these UI scenarios stay focused on
# the panel/controller behavior itself.
def build_reconciliation_report(deposits:)
  SupportAgentReport.create!(
    owner: @capital_call,
    support_agent: @remit_agent,
    status: "completed",
    latest: true,
    json_fields: {
      "run_at" => Time.current.iso8601,
      "deposits" => deposits,
      "tier_counts" => deposits.group_by { |d| d["tier"] }.transform_values(&:size),
      "issues" => []
    }
  )
end

# A report with no deposits at all — enough for the panel to render (it is hidden until a
# results report exists) without needing any remittance fixtures.
Given('there is an empty reconciliation report for the capital call') do
  @reconciliation_report = build_reconciliation_report(deposits: [])
end

Given('there is a reconciliation report for the capital call with a probable deposit matched to {string}') do |investor_name|
  remittance = @remittances_by_investor[investor_name]
  deposit = {
    "sheet" => "Axis", "row" => 1, "bank" => "AxisNarrationParser",
    "raw_narration" => "TRF/#{investor_name.upcase}/TRANSFER",
    "name" => investor_name.upcase, "account_number" => nil,
    "pattern" => "TRF", "confidence" => "medium", "internal" => false, "notes" => nil,
    "amount" => remittance.call_amount.to_f, "tran_id" => nil, "value_date" => Time.zone.today.iso8601,
    "tier" => "probable", "matched_remittance_id" => remittance.id,
    "matched_commitment_id" => remittance.capital_commitment_id, "matched_investor_name" => remittance.investor_name,
    "identity_via" => "name", "kyc_account_number" => nil, "due_amount" => remittance.call_amount.to_f,
    "amount_status" => "within_tolerance",
    "source_of_funds" => "unverifiable", "reasoning" => ["name similarity 1.0 to \"#{remittance.investor_name}\"", "amount within tolerance of due"]
  }
  @reconciliation_report = build_reconciliation_report(deposits: [deposit])
end

# Builds one deposit hash for an investor already set up via create_remittance_candidate.
def fixture_deposit_for(investor_name, tier:, row:)
  remittance = @remittances_by_investor.fetch(investor_name)
  kyc_account = remittance.investor_kyc&.bank_account_number
  base = {
    "sheet" => "ICICI", "row" => row, "bank" => "IciciNarrationParser",
    "name" => investor_name.upcase, "pattern" => "RTGS-hyphen", "confidence" => "high", "internal" => false, "notes" => nil,
    "amount" => remittance.call_amount.to_f, "tran_id" => "TXN-#{row}", "value_date" => Time.zone.today.iso8601,
    "tier" => tier, "matched_remittance_id" => remittance.id,
    "matched_commitment_id" => remittance.capital_commitment_id, "matched_investor_name" => remittance.investor_name,
    "due_amount" => remittance.call_amount.to_f, "amount_status" => "within_tolerance"
  }
  if tier == "exact"
    base.merge("raw_narration" => "RTGS-TEST-#{investor_name.upcase}-#{kyc_account}-HDFC0000240", "account_number" => kyc_account,
               "identity_via" => "kyc_account", "kyc_account_number" => kyc_account, "source_of_funds" => "confirmed",
               "reasoning" => ["sender account #{kyc_account} matches the investor's KYC bank account", "amount within tolerance of due"])
  else
    base.merge("raw_narration" => "TRFR FROM:#{investor_name.upcase}", "account_number" => nil, "identity_via" => "name",
               "kyc_account_number" => nil, "source_of_funds" => "unverifiable",
               "reasoning" => ["name similarity 1.0 to \"#{remittance.investor_name}\"", "amount within tolerance of due"])
  end
end

Given('there is a reconciliation report for the capital call with exact deposits for {string} and a probable deposit for {string}') do |exact_names, probable_name|
  deposits = exact_names.split(",").map(&:strip).each_with_index.map { |name, i| fixture_deposit_for(name, tier: "exact", row: i + 1) }
  deposits << fixture_deposit_for(probable_name, tier: "probable", row: deposits.size + 1)
  @reconciliation_report = build_reconciliation_report(deposits: deposits)
end

When('I confirm the bulk confirmation modal') do
  expect(page).to have_css("#confirm-all-exact-modal", visible: true)
  within("#confirm-all-exact-modal") { click_button "Record 2 payments" }
end

Then('no CapitalRemittancePayment should exist for {string}') do |investor_name|
  expect(CapitalRemittancePayment.where(capital_remittance: @remittances_by_investor[investor_name])).not_to exist
end

Then('the row for {string} links to its remittance and its payment in a new tab') do |investor_name|
  remittance = @remittances_by_investor.fetch(investor_name)
  payment = CapitalRemittancePayment.find_by!(capital_remittance: remittance)
  expect(page).to have_link(investor_name, href: capital_remittance_path(remittance))
  expect(find_link(investor_name, href: capital_remittance_path(remittance))[:target]).to eq("_blank")
  expect(page).to have_link(href: capital_remittance_payment_path(payment))
  expect(find_link(href: capital_remittance_payment_path(payment))[:target]).to eq("_blank")
end

Then('there is no Confirm all Matched button') do
  expect(page).not_to have_css("#confirm_all_exact_btn")
end

Given('there is a reconciliation report for the capital call with an exact payment already recorded for {string}') do |investor_name|
  remittance = @remittances_by_investor[investor_name]
  outcome = RemittanceDepositPaymentApplier.call(
    deposit: { "amount" => remittance.call_amount.to_f, "value_date" => Time.zone.today.iso8601,
               "sheet" => "ICICI", "row" => 1, "raw_narration" => "RTGS-TEST-#{investor_name.upcase}",
               "tran_id" => "T-#{SecureRandom.hex(4)}" },
    capital_remittance: remittance, fund: @fund
  )
  deposit = {
    "sheet" => "ICICI", "row" => 1, "bank" => "IciciNarrationParser",
    "raw_narration" => "RTGS-TEST-#{investor_name.upcase}",
    "name" => investor_name.upcase, "account_number" => nil,
    "pattern" => "RTGS-hyphen", "confidence" => "high", "internal" => false, "notes" => nil,
    "amount" => remittance.call_amount.to_f, "tran_id" => outcome[:reference_no], "value_date" => Time.zone.today.iso8601,
    "tier" => "exact", "matched_remittance_id" => remittance.id,
    "matched_commitment_id" => remittance.capital_commitment_id, "matched_investor_name" => remittance.investor_name,
    "identity_via" => "kyc_account", "kyc_account_number" => "50100602457893", "due_amount" => remittance.call_amount.to_f,
    "amount_status" => "within_tolerance",
    "source_of_funds" => "confirmed", "reasoning" => ["sender account 50100602457893 matches the investor's KYC bank account", "amount within tolerance of due"],
    "payment_id" => outcome[:payment_id], "reference_no" => outcome[:reference_no], "payment_status" => outcome[:status].to_s
  }
  @reconciliation_report = build_reconciliation_report(deposits: [deposit])
end

Then('a CapitalRemittancePayment should exist for {string}') do |investor_name|
  remittance = @remittances_by_investor[investor_name]
  expect(CapitalRemittancePayment.where(capital_remittance: remittance)).to exist
end

Then('the CapitalRemittancePayment for {string} should be destroyed') do |investor_name|
  remittance = @remittances_by_investor[investor_name]
  expect(CapitalRemittancePayment.where(capital_remittance: remittance)).not_to exist
end
