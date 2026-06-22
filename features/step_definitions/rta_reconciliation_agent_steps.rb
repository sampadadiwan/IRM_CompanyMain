# frozen_string_literal: true

# Step definitions for features/ai/rta_reconciliation_agent.feature.
#
# Strategy: agent runs go through RtaReconciliationAgent.wtf?() directly.
# LLM calls are stubbed — the extracted JSON is injected via @rta_extracted_json
# so scenarios control exactly what the LLM "sees" without real PDF parsing.
# Email delivery is checked via ActionMailer::Base.deliveries (:inline adapter).

# ── Helpers ────────────────────────────────────────────────────────────────────

def rta_fund_report
  # latest: true (not plain find_by) — scenarios that run the agent more than once
  # (continuity, movement) create a new SupportAgentReport row per run, so the
  # first match by primary key would silently return a stale report.
  SupportAgentReport.find_by(owner: @fund, support_agent: @rta_agent, latest: true)
end

def rta_report_json
  (rta_fund_report&.json_fields || {}).deep_symbolize_keys
end

def stub_rta_llm(json_hash)
  fake_chat = double("llm_chat")
  allow(fake_chat).to receive(:ask).and_return(double("result", content: json_hash.to_json))
  allow(LlmService).to receive(:ruby_llm_chat).and_return(fake_chat)
end

def run_rta_agent(rta_pdf_document_id: :_use_doc)
  # Default to the stub document created in the background step; pass nil to simulate no PDF.
  doc_id = rta_pdf_document_id == :_use_doc ? @rta_doc&.id : rta_pdf_document_id
  ActionMailer::Base.deliveries.clear
  stub_rta_llm(@rta_extracted_json || { "amc" => nil, "statement_date" => nil, "schemes" => [] })
  stub_pdf_read
  @rta_agent_result = RtaReconciliationAgent.wtf?(
    support_agent_id: @rta_agent.id,
    target: @fund,
    rta_pdf_document_id: doc_id
  )
end

# Stubs PDF text extraction so a real PDF is not required in tests.
def stub_pdf_read
  allow_any_instance_of(RtaReconciliationAgent).to receive(:extract_pdf_text).and_return("stub pdf text")
end

# Builds a minimal extracted JSON structure for a single scheme.
def build_scheme_json(isin:, scheme:, closing_units:, folios: [], nav: 45.20)
  {
    "amc" => "Test AMC",
    "statement_date" => @rta_statement_date || "31-12-2024",
    "schemes" => [
      {
        "scheme" => scheme,
        "isin" => isin,
        "nav" => nav,
        "summary" => {
          "opening_units" => 0.0,
          "subscriptions_units" => closing_units,
          "redemptions_units" => 0.0,
          "closing_units" => closing_units
        },
        "folios" => folios
      }
    ]
  }
end

# ── Background ─────────────────────────────────────────────────────────────────

Given('there is an RtaReconciliationAgent configured for the entity') do
  # Attach a stub PDF document so the agent finds an RTA statement
  @rta_agent = FactoryBot.create(
    :support_agent,
    entity: @entity,
    agent_type: "RtaReconciliationAgent",
    name: "RTA Reconciliation",
    enabled: true,
    llm_model: "gemini-3-flash-preview",
    json_fields: {
      "tolerance_units" => "0.01",
      "tolerance_pct" => "0",
      "check_pending_requests" => "Yes",
      "send_report" => "No",
      "notify_email" => ""
    }
  )

  # Stub Document whose ID is passed to the agent via ctx[:rta_pdf_document_id] in run_rta_agent.
  # In production this document is created by the controller from the uploaded file.
  rta_folder = FactoryBot.create(:folder, owner: @entity, entity: @entity)
  @rta_doc = Document.new(
    name: "RTA Statement (PDF)",
    entity: @entity,
    owner: @entity,
    folder: rta_folder,
    user: @user,
    send_email: false,
    orignal: true
  )
  @rta_doc.file_data = {
    "id" => "#{SecureRandom.hex(8)}.pdf",
    "storage" => "store",
    "metadata" => { "filename" => "rta_statement.pdf", "size" => 1024, "mime_type" => "application/pdf" }
  }.to_json
  @rta_doc.save!(validate: false)
end

# ── Fund + unit setting setup ──────────────────────────────────────────────────

Given('the fund has a FundUnitSetting with ISIN {string} and name {string}') do |isin, name|
  # Fund#unit_types must list the unit type name or FundUnitSetting's allowed_unit_type validation rejects it.
  @fund.update!(unit_types: [@fund.unit_types, name].compact_blank.join(", ")) unless @fund.unit_types.to_s.include?(name)
  @fund_unit_setting = FactoryBot.create(:fund_unit_setting, fund: @fund, entity: @entity, isin: isin, name: name)
end

# Registers a unit type as one the fund recognizes (CapitalCommitment#unit_type is validated
# against Fund#unit_types) without configuring a FundUnitSetting/ISIN for it — for the
# fund-wide readiness-gap scenario, where the gap *is* the missing FundUnitSetting.
Given('the fund recognizes unit type {string}') do |name|
  @fund.update!(unit_types: [@fund.unit_types, name].compact_blank.join(", ")) unless @fund.unit_types.to_s.include?(name)
end

Given('the fund has no FundUnitSettings') do
  FundUnitSetting.where(fund: @fund).destroy_all
end

Given('the fund has no capital commitments') do
  CapitalCommitment.where(fund: @fund).find_each(&:really_destroy!)
end

def rta_test_investor
  inv_entity = FactoryBot.create(:entity, entity_type: "Company")
  FactoryBot.create(:investor, entity: @entity, investor_entity: inv_entity)
end

Given('the fund has {int} capital commitment(s) with folio_ids and unit_type {string} totalling {float} units') do |count, unit_type, total|
  units_each = (total / count).round(8)
  @commitments = Array.new(count) do |_i|
    cc = FactoryBot.create(
      :capital_commitment,
      fund: @fund,
      entity: @entity,
      investor: rta_test_investor,
      unit_type: unit_type,
      folio_id: "FOLIO-#{SecureRandom.hex(4)}"
    )
    # Bypass counter_culture and set total_fund_units_quantity directly
    cc.update_columns(total_fund_units_quantity: units_each)
    cc
  end
end

Given('the fund has {int} capital commitment(s) with folio_id {string} and unit_type {string} with {float} units') do |_count, folio_id, unit_type, units|
  @commitments ||= []
  cc = FactoryBot.create(
    :capital_commitment,
    fund: @fund,
    entity: @entity,
    investor: rta_test_investor,
    unit_type: unit_type,
    folio_id: folio_id
  )
  cc.update_columns(total_fund_units_quantity: units)
  @commitments << cc
end

Given('the agent tolerance_units is {string}') do |tol|
  @rta_agent.json_fields["tolerance_units"] = tol
  @rta_agent.save!
end

Given('the agent is configured to send reports to {string}') do |email|
  # Enable email delivery and set the notify address
  @rta_agent.json_fields["send_report"]  = "Yes"
  @rta_agent.json_fields["notify_email"] = email
  @rta_agent.save!
end

# ── RTA statement JSON setup ────────────────────────────────────────────────────

Given('the RTA statement PDF contains scheme {string} ISIN {string} closing units {float}') do |scheme, isin, closing|
  # Reset this ISIN's folio list to whatever @rta_folios currently holds — for a single-scheme
  # scenario that's [] the first time, matching the long-standing behaviour. For a multi-run
  # scenario (continuity/movement) where only the per-ISIN folio steps are used, @rta_folios
  # stays nil throughout, so each call here starts the new statement with a clean slate rather
  # than carrying over the previous run's folios.
  @rta_folios_by_isin ||= {}
  @rta_folios_by_isin[isin] = @rta_folios || []
  @rta_extracted_json = build_scheme_json(isin: isin, scheme: scheme, closing_units: closing, folios: @rta_folios_by_isin[isin])
end

# Adds a second (or further) ISIN block to a statement already started with the step above —
# for scenarios covering multiple schemes in one upload ("some matched", coverage gaps, etc).
Given('the RTA statement PDF also contains scheme {string} ISIN {string} closing units {float}') do |scheme, isin, closing|
  @rta_folios_by_isin ||= {}
  @rta_folios_by_isin[isin] = []
  @rta_extracted_json["schemes"] << {
    "scheme" => scheme,
    "isin" => isin,
    "nav" => 45.20,
    "summary" => {
      "opening_units" => 0.0,
      "subscriptions_units" => closing,
      "redemptions_units" => 0.0,
      "closing_units" => closing
    },
    "folios" => @rta_folios_by_isin[isin]
  }
end

# Sets a statement date for the run that follows — needed to anchor the period for
# opening-balance continuity and unit-movement checks, which compare the current run
# against the *previous* run's statement_date.
Given('the RTA statement date is {string}') do |date_str|
  @rta_statement_date = date_str
end

Given('the PDF folio breakdown matches all {int} capital commitments exactly') do |_count|
  @rta_folios = @commitments.map do |cc|
    {
      "folio_number" => cc.folio_id,
      "investor_name" => cc.investor_name,
      "holding_type" => "Resident",
      "opening_units" => 0.0,
      "closing_units" => cc.total_fund_units_quantity.to_f,
      "pending_requests" => "None"
    }
  end
  scheme = @rta_extracted_json["schemes"].first
  scheme["folios"]                    = @rta_folios
  scheme["summary"]["closing_units"]  = @rta_folios.sum { |f| f["closing_units"] }
  @rta_extracted_json["schemes"]      = [scheme]
end

Given('the PDF folio breakdown has folio {string} with closing units {float}') do |folio_number, closing|
  @rta_folios ||= []
  @rta_folios << {
    "folio_number" => folio_number,
    "investor_name" => "Test Investor",
    "holding_type" => "Resident",
    "opening_units" => 0.0,
    "closing_units" => closing,
    "pending_requests" => "None"
  }
  @rta_extracted_json["schemes"].first["folios"] = @rta_folios if @rta_extracted_json
end

Given('the PDF folio breakdown has folio {string} with closing units {float} and pending requests {string}') do |folio_number, closing, pending|
  @rta_folios ||= []
  @rta_folios << {
    "folio_number" => folio_number,
    "investor_name" => "Test Investor",
    "holding_type" => "Resident",
    "opening_units" => 0.0,
    "closing_units" => closing,
    "pending_requests" => pending
  }
  @rta_extracted_json["schemes"].first["folios"] = @rta_folios if @rta_extracted_json
end

Given('the PDF folio breakdown is empty') do
  @rta_folios = []
  @rta_extracted_json["schemes"].first["folios"] = [] if @rta_extracted_json
end

# ── Per-ISIN folio steps — for multi-scheme statements and multi-run scenarios ──────────────

Given('the PDF folio breakdown for ISIN {string} has folio {string} with closing units {float}') do |isin, folio_number, closing|
  @rta_folios_by_isin ||= {}
  (@rta_folios_by_isin[isin] ||= []) << {
    "folio_number" => folio_number, "investor_name" => "Test Investor", "holding_type" => "Resident",
    "opening_units" => 0.0, "closing_units" => closing, "pending_requests" => "None"
  }
end

Given('the PDF folio breakdown for ISIN {string} has folio {string} with opening units {float} and closing units {float}') do |isin, folio_number, opening, closing|
  @rta_folios_by_isin ||= {}
  (@rta_folios_by_isin[isin] ||= []) << {
    "folio_number" => folio_number, "investor_name" => "Test Investor", "holding_type" => "Resident",
    "opening_units" => opening, "closing_units" => closing, "pending_requests" => "None"
  }
end

Given('the PDF folio breakdown for ISIN {string} has folio {string} with investor name {string} and closing units {float}') do |isin, folio_number, investor_name, closing|
  @rta_folios_by_isin ||= {}
  (@rta_folios_by_isin[isin] ||= []) << {
    "folio_number" => folio_number, "investor_name" => investor_name, "holding_type" => "Resident",
    "opening_units" => 0.0, "closing_units" => closing, "pending_requests" => "None"
  }
end

# Overrides the auto-derived subscriptions_units on a scheme's summary, independent of the
# folio-level figures — used to simulate an RTA-reported subscription CapHive's FundUnit
# ledger doesn't corroborate (a movement break despite a matching closing balance).
Given('the PDF summary for ISIN {string} reports {float} units subscribed') do |isin, subscribed|
  scheme = @rta_extracted_json["schemes"].find { |s| s["isin"] == isin }
  scheme["summary"]["subscriptions_units"] = subscribed
end

# Creates a real CapHive unit-ledger entry (FundUnit) for the period-based movement check —
# counter_culture fires on create, so the matching capital_commitment's total_fund_units_quantity
# is bumped by `quantity` automatically, same as a real allotment/redemption would.
Given('there is a FundUnit record for the fund with unit_type {string} quantity {float} issued on {string}') do |unit_type, quantity, issue_date|
  cc = @commitments&.find { |c| c.unit_type == unit_type }
  FactoryBot.create(
    :fund_unit,
    fund: @fund,
    entity: @entity,
    capital_commitment: cc,
    investor: cc.investor,
    unit_type: unit_type,
    quantity: quantity,
    issue_date: Date.parse(issue_date)
  )
end

# ── When ───────────────────────────────────────────────────────────────────────

When('the RtaReconciliationAgent runs for the fund') do
  run_rta_agent
end

When('the RtaReconciliationAgent runs for the fund without a PDF') do
  # Pass nil document ID so the agent skips PDF extraction and records the blocking issue.
  run_rta_agent(rta_pdf_document_id: nil)
end

# Semantically distinct from "runs for the fund" — signals this is a second run reusing
# the previous run's saved report (continuity / movement scenarios). No special handling
# needed: the agent looks up the latest prior report itself at the start of every run.
When('the RtaReconciliationAgent runs again for the fund') do
  run_rta_agent
end

# ── Then ───────────────────────────────────────────────────────────────────────

Then('a fund-level SupportAgentReport is saved') do
  expect(rta_fund_report).to be_present
end

Then('the RTA report has no blocking issues') do
  issues = rta_report_json[:issues] || []
  blocking = issues.select { |i| (i[:severity] || i["severity"]).to_s == "blocking" }
  expect(blocking).to be_empty, "Expected no blocking issues, got: #{blocking.map { |i| i[:message] || i['message'] }.join(', ')}"
end

Then('the report has a blocking issue matching {string}') do |text|
  issues = rta_report_json[:issues] || []
  match  = issues.any? { |i| (i[:severity] || i["severity"]).to_s == "blocking" && (i[:message] || i["message"]).to_s.include?(text) }
  expect(match).to be(true), "Expected a blocking issue containing '#{text}', got: #{issues.map { |i| i[:message] || i['message'] }.join('; ')}"
end

Then('the report has a warning issue matching {string}') do |text|
  issues = rta_report_json[:issues] || []
  match  = issues.any? { |i| (i[:severity] || i["severity"]).to_s == "warning" && (i[:message] || i["message"]).to_s.include?(text) }
  expect(match).to be(true), "Expected a warning issue containing '#{text}', got: #{issues.map { |i| i[:message] || i['message'] }.join('; ')}"
end

Then('the report scheme_results show summary_match {word} for ISIN {string}') do |bool_str, isin|
  expected = bool_str == "true"
  results  = rta_report_json[:scheme_results] || []
  scheme   = results.find { |sr| (sr[:isin] || sr["isin"]) == isin }
  expect(scheme).to be_present, "No scheme_result found for ISIN #{isin}"
  # rta_report_json is deep_symbolize_keys'd, so :summary_match is the only valid key —
  # `|| scheme["summary_match"]` previously masked a real `false` with a `nil` fallback.
  actual = scheme[:summary_match]
  expect(actual).to eq(expected), "Expected summary_match=#{expected} for #{isin}, got #{actual}"
end

Then('the report health_score is {int}') do |score|
  expect(rta_report_json[:health_score]).to eq(score)
end

Then('an email is delivered to {string}') do |address|
  delivered = ActionMailer::Base.deliveries
  expect(delivered).not_to be_empty, "Expected an email to #{address} but none was delivered"
  expect(delivered.last.to).to include(address)
end

Then('the email subject contains {string}') do |text|
  subject = ActionMailer::Base.deliveries.last&.subject.to_s
  expect(subject).to include(text), "Expected email subject to include '#{text}', got: '#{subject}'"
end

Then('the report scheme_results show movement_matched {word} for ISIN {string}') do |bool_str, isin|
  expected = bool_str == "true"
  results  = rta_report_json[:scheme_results] || []
  scheme   = results.find { |sr| sr[:isin] == isin }
  expect(scheme).to be_present, "No scheme_result found for ISIN #{isin}"
  actual = scheme.dig(:movement, :matched)
  expect(actual).to eq(expected), "Expected movement matched=#{expected} for #{isin}, got #{actual} (movement=#{scheme[:movement]})"
end
