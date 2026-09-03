# frozen_string_literal: true

# Step definitions for features/ai/capital_remittance_reconciliation_agent.feature.
#
# Strategy: agent runs go through RemittanceReconciliationAgent.wtf?() directly,
# same as RtaReconciliationAgent's feature. Unlike RTA (which stubs the LLM entirely since
# extraction is AI-driven), Phase 1 of this agent has no LLM step at all — narration parsing
# is fully deterministic — so scenarios build a *real* xlsx workbook (via Axlsx) and attach it
# to a real Document, exercising the genuine Roo + BankDepositNarrationParser pipeline rather
# than stubbing it out.

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

# ICICI-shape header: Sl No / Transaction Remarks / Withdrawal (Dr) / Deposit (Cr).
# withdrawal_amount and deposit_amount are mutually exclusive per row, same as a real
# statement — exactly one is populated, the other left blank.
def icici_sheet_rows(deposits: [], withdrawals: [])
  header = ["Sl No", "Transaction Remarks", "Withdrawal (Dr)", "Deposit (Cr)"]
  rows = deposits.each_with_index.map { |(narration, amount), i| [i + 1, narration, nil, amount] }
  rows += withdrawals.each_with_index.map { |(narration, amount), i| [deposits.size + i + 1, narration, amount, nil] }
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

def parse_amount_table(table)
  table.hashes.map { |row| [row["narration"], row["amount"].to_f] }
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

Given("the agent's auto_apply_exact is {string}") do |value|
  @remit_agent.json_fields["auto_apply_exact"] = value
  @remit_agent.save!
end

# ── Given: remittance candidates ────────────────────────────────────────────────

# Builds one investor + CapitalCommitment (+ optional InvestorKyc) + CapitalRemittance under
# @capital_call. investor_kyc is assigned onto the commitment explicitly — CapitalCommitment
# belongs_to :investor_kyc is a real FK, not auto-resolved from the investor, so a KYC record
# floating unassociated would never be found by capital_remittance.investor_kyc.
def create_remittance_candidate(investor_name:, call_amount:, bank_account_number: nil, virtual_bank_account: nil)
  investor_entity = FactoryBot.create(:entity, entity_type: "Individual", name: investor_name)
  investor = FactoryBot.create(:investor, entity: @entity, investor_entity: investor_entity)
  kyc = bank_account_number ? FactoryBot.create(:investor_kyc, entity: @entity, investor: investor, bank_account_number: bank_account_number) : nil
  commitment = FactoryBot.create(
    :capital_commitment, fund: @fund, entity: @entity, investor: investor, investor_kyc: kyc,
                         folio_id: "F-#{SecureRandom.hex(3)}", virtual_bank_account: virtual_bank_account
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

Then('the report has a blocking issue matching {string}') do |text|
  issues = remit_report_json[:issues] || []
  match  = issues.any? { |i| (i[:severity] || i["severity"]).to_s == "blocking" && (i[:message] || i["message"]).to_s.include?(text) }
  expect(match).to be(true), "Expected a blocking issue containing '#{text}', got: #{issues.map { |i| i[:message] || i['message'] }.join('; ')}"
end

Then('the report has a warning issue matching {string}') do |text|
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

When('I click {string}') do |button_text|
  click_button button_text
end

Then('I should see the reconciliation panel') do
  expect(page).to have_content("Remittance Reconciliation")
end

Then('I should not see the reconciliation panel') do
  expect(page).not_to have_content("Remittance Reconciliation")
end

Then('I should see the run reconciliation button') do
  expect(page).to have_button("Run Reconciliation")
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
    "identity_via" => "name", "due_amount" => remittance.call_amount.to_f,
    "source_of_funds" => "unverifiable", "reasoning" => ["name similarity 1.0 to \"#{remittance.investor_name}\""]
  }
  @reconciliation_report = build_reconciliation_report(deposits: [deposit])
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
    "identity_via" => "kyc_account", "due_amount" => remittance.call_amount.to_f,
    "source_of_funds" => "confirmed", "reasoning" => ["account matches InvestorKyc#bank_account_number"],
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
