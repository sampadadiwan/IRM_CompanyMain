# frozen_string_literal: true

# Step definitions for the KYC Agent Dashboard.
#
# Tests AgentReportsQuery (dashboard data aggregation, filters, doc ratios)
# and KycDashboardHelper (status classification, result summary, doc ratio
# display, mark verified, run output items) without a browser — data is
# fabricated directly and methods called in-process.

# Include the view helper so its methods are available in step definitions.
World(KycDashboardHelper)
# ActionView helpers (content_tag, h, safe_join) needed by kyc_doc_tooltip_html
World(ActionView::Helpers::TagHelper)
World(ActionView::Helpers::OutputSafetyHelper)
World(ActionView::Context)

# ── Helpers ──────────────────────────────────────────────────────────────

# Creates an Investor with a proper investor_entity_id. The :investor
# factory defaults investor_entity_id to Entity.startups.sample.id which
# is nil in test — we create an Investor-type entity explicitly.
#
# @param name [String] investor name
# @return [Investor]
def create_dashboard_investor(name: "Investor #{rand(9999)}")
  inv_entity = FactoryBot.create(:entity, entity_type: "Investor", name: name)
  FactoryBot.create(:investor, entity: @entity,
                     investor_entity_id: inv_entity.id,
                     investor_name: name)
end

# Creates an InvestorKyc for the entity. Sets kyc_type enum so the
# before_save callback derives the correct STI type column. Defaults to
# "completed" submission_status (after_save syncs completed_by_investor).
#
# @param investor [Investor, nil] uses @investor or creates a new one
# @param type [String] desired STI type — "IndividualKyc" or "NonIndividualKyc"
# @return [InvestorKyc]
def create_dashboard_kyc(investor: nil, type: "IndividualKyc", **attrs)
  inv = investor || create_dashboard_investor
  kyc_type_val = type == "NonIndividualKyc" ? "non_individual" : "individual"

  # submission_status defaults to "completed"; after_save syncs booleans.
  # Callers can override submission_status — the callback adjusts booleans.
  defaults = {
    entity: @entity,
    investor: inv,
    submission_status: "completed",
    kyc_type: kyc_type_val
  }
  FactoryBot.create(:investor_kyc, defaults.merge(attrs))
end

# Creates a SupportAgentReport for a KYC with the given json_fields.
# The after_create callback sets latest=true automatically.
#
# @param kyc [InvestorKyc]
# @param json_fields [Hash]
# @return [SupportAgentReport]
def create_dashboard_report(kyc, json_fields)
  SupportAgentReport.create!(
    owner: kyc,
    support_agent: @support_agent,
    status: :completed,
    json_fields: json_fields
  )
end

# Builds a json_fields hash for a "ready" (successful) report.
#
# @return [Hash]
def ready_report_fields
  { "final_status" => "ready",
    "field_issues" => [{ "message" => "PAN", "severity" => "success", "type" => "info" }],
    "document_issues" => [],
    "run_at" => Time.current.iso8601 }
end

# Builds a json_fields hash for a "blocked" report with no success issues (Failed).
#
# @return [Hash]
def blocked_no_success_fields
  { "final_status" => "blocked",
    "field_issues" => [{ "message" => "pan", "severity" => "blocking", "type" => "invalid_field_value" }],
    "document_issues" => [],
    "run_at" => Time.current.iso8601 }
end

# Builds a json_fields hash for a "blocked" report with some successes (Partially Failed).
#
# @return [Hash]
def blocked_with_success_fields
  { "final_status" => "blocked",
    "field_issues" => [
      { "message" => "PAN", "severity" => "success", "type" => "info" },
      { "message" => "address", "severity" => "blocking", "type" => "invalid_field_value" }
    ],
    "document_issues" => [],
    "run_at" => Time.current.iso8601 }
end

# ── Background ───────────────────────────────────────────────────────────

Given("there is a KYC onboarding agent for the dashboard") do
  @support_agent = SupportAgent.find_or_create_by!(
    agent_type: "KycOnboardingAgent", entity: @entity
  ) do |agent|
    agent.name    = "KYC Onboarding Validator"
    agent.enabled = true
    agent.json_fields = { "trigger_aml" => "false" }
  end
end

# ══════════════════════════════════════════════════════════════════════════
# AgentReportsQuery — basic stats
# ══════════════════════════════════════════════════════════════════════════

Given("the entity has KYCs with submission statuses {string}") do |statuses_csv|
  statuses_csv.split(",").each do |status|
    s = status.strip
    # after_save :sync_boolean_fields_from_status derives completed_by_investor and
    # verified from submission_status, so we only need to set the status.
    # For "completed"/"verified" the callback sets completed_by_investor=true.
    create_dashboard_kyc(submission_status: s)
  end
end

When("I load the KYC dashboard data") do
  query = AgentReportsQuery.new(@support_agent)
  @kyc_dashboard = query.kyc_dashboard_data
end

# SQLite-safe variants that call individual methods instead of the
# full kyc_dashboard_data (which triggers MySQL-only kyc_type_stats).
When("I load the KYC basic stats") do
  query = AgentReportsQuery.new(@support_agent)
  @kyc_dashboard = { basic_stats: query.send(:kyc_basic_stats) }
end

When("I load the KYC doc ratios") do
  query = AgentReportsQuery.new(@support_agent)
  records = query.kyc_filtered_records.last
  @kyc_dashboard = { doc_ratios: query.send(:kyc_doc_ratios, records) }
end

When("I load the KYC pending IDs") do
  query = AgentReportsQuery.new(@support_agent)
  @kyc_dashboard = { pending_ids: query.send(:kyc_pending_ids) }
end

Then("the basic stats should show not_sent={int}, link_sent={int}, completed={int}, verified_status={int}") do |ns, ls, c, v|
  stats = @kyc_dashboard[:basic_stats]
  expect(stats[:not_sent]).to eq(ns), "not_sent: expected #{ns}, got #{stats[:not_sent]}"
  expect(stats[:link_sent]).to eq(ls), "link_sent: expected #{ls}, got #{stats[:link_sent]}"
  expect(stats[:completed]).to eq(c), "completed: expected #{c}, got #{stats[:completed]}"
  expect(stats[:verified_status]).to eq(v), "verified_status: expected #{v}, got #{stats[:verified_status]}"
end

Given("the entity has {int} verified and {int} unverified completed KYCs") do |verified_count, unverified_count|
  verified_count.times { create_dashboard_kyc(verified: true, submission_status: "verified") }
  unverified_count.times { create_dashboard_kyc(verified: false) }
end

Then("the basic stats should show verified={int}, unverified={int}") do |v, uv|
  stats = @kyc_dashboard[:basic_stats]
  expect(stats[:verified]).to eq(v), "verified: expected #{v}, got #{stats[:verified]}"
  expect(stats[:unverified]).to eq(uv), "unverified: expected #{uv}, got #{stats[:unverified]}"
end

Given("the entity has {int} individual and {int} non-individual completed KYCs") do |ind, non_ind|
  ind.times { create_dashboard_kyc(type: "IndividualKyc") }
  non_ind.times { create_dashboard_kyc(type: "NonIndividualKyc") }
end

Then("the basic stats should show individual={int}, non_individual={int}") do |ind, non_ind|
  stats = @kyc_dashboard[:basic_stats]
  expect(stats[:individual]).to eq(ind), "individual: expected #{ind}, got #{stats[:individual]}"
  expect(stats[:non_individual]).to eq(non_ind), "non_individual: expected #{non_ind}, got #{stats[:non_individual]}"
end

# ══════════════════════════════════════════════════════════════════════════
# AgentReportsQuery — type stats
# ══════════════════════════════════════════════════════════════════════════

Given("there is an individual KYC with a {string} agent report") do |final_status|
  kyc = create_dashboard_kyc(type: "IndividualKyc")
  fields = case final_status
           when "ready" then ready_report_fields
           when "blocked" then blocked_no_success_fields
           end
  create_dashboard_report(kyc, fields)
  @last_kyc_with_report = kyc
end

Given("there is an individual KYC with no agent report") do
  @last_kyc_without_report = create_dashboard_kyc(type: "IndividualKyc")
end

# ══════════════════════════════════════════════════════════════════════════
# AgentReportsQuery — filtered records
# ══════════════════════════════════════════════════════════════════════════

Given("there is an individual KYC for {string} with a {string} agent report") do |investor_name, final_status|
  investor = create_dashboard_investor(name: investor_name)
  kyc = create_dashboard_kyc(investor: investor, type: "IndividualKyc")
  fields = case final_status
           when "ready" then ready_report_fields
           when "blocked" then blocked_no_success_fields
           end
  create_dashboard_report(kyc, fields)
end

Given("there is a non-individual KYC for {string} with a {string} agent report") do |investor_name, final_status|
  investor = create_dashboard_investor(name: investor_name)
  kyc = create_dashboard_kyc(investor: investor, type: "NonIndividualKyc")
  fields = case final_status
           when "ready" then ready_report_fields
           when "blocked" then blocked_no_success_fields
           end
  create_dashboard_report(kyc, fields)
end

When("I load filtered KYC records with kyc_type {string}") do |kyc_type|
  query = AgentReportsQuery.new(@support_agent)
  _pagy, @filtered_records = query.kyc_filtered_records(kyc_type: kyc_type)
end

When("I load filtered KYC records with search {string}") do |search_term|
  query = AgentReportsQuery.new(@support_agent)
  _pagy, @filtered_records = query.kyc_filtered_records(q: search_term)
end

Then("the filtered records should include {string}") do |investor_name|
  names = @filtered_records.map { |r| r.investor&.investor_name }
  expect(names).to include(investor_name),
    "Expected '#{investor_name}' in filtered records, got: #{names.inspect}"
end

Then("the filtered records should not include {string}") do |investor_name|
  names = @filtered_records.map { |r| r.investor&.investor_name }
  expect(names).not_to include(investor_name),
    "Expected '#{investor_name}' NOT in filtered records, got: #{names.inspect}"
end

# ══════════════════════════════════════════════════════════════════════════
# AgentReportsQuery — doc ratios
# ══════════════════════════════════════════════════════════════════════════

Given("there is a KYC with {int} required File fields and {int} uploaded document") do |required, uploaded|
  # Create the KYC first, before adding required File fields to the form_type —
  # otherwise the KYC validation rejects the record for missing required fields.
  form_type = FormType.where(entity: @entity, name: "IndividualKyc").first ||
               FormType.create!(entity: @entity, name: "IndividualKyc", tag: "Default")

  kyc = create_dashboard_kyc(type: "IndividualKyc")
  kyc.update_columns(form_type_id: form_type.id)

  @required_field_names = []
  required.times do |i|
    label = "Required Doc #{i}"
    FormCustomField.create!(
      form_type: form_type,
      name: "doc_field_#{i}",
      label: label,
      field_type: "File",
      required: true,
      position: i
    )
    @required_field_names << label
  end

  # Ensure a folder exists for the Document factory's Folder.first default
  Folder.first || FactoryBot.create(:folder, entity: @entity)

  # Upload documents matching first N required field labels
  uploaded.times do |i|
    FactoryBot.create(:document,
      name: @required_field_names[i],
      owner: kyc,
      entity: @entity,
      user: @user)
  end

  @doc_ratio_kyc = kyc
end

Then("the doc ratio for that KYC should show uploaded={int}, required={int}") do |up, req|
  ratio = @kyc_dashboard[:doc_ratios][@doc_ratio_kyc.id]
  expect(ratio).to be_present, "No doc ratio found for KYC #{@doc_ratio_kyc.id}"
  expect(ratio[:uploaded]).to eq(up), "uploaded: expected #{up}, got #{ratio[:uploaded]}"
  expect(ratio[:required]).to eq(req), "required: expected #{req}, got #{ratio[:required]}"
end

Then("the doc ratio missing names should include the unuploaded field") do
  ratio = @kyc_dashboard[:doc_ratios][@doc_ratio_kyc.id]
  # The second required field was not uploaded, so it should be in missing_names
  expect(ratio[:missing_names]).not_to be_empty,
    "Expected missing_names to include unuploaded fields, got: #{ratio[:missing_names].inspect}"
end

# ══════════════════════════════════════════════════════════════════════════
# AgentReportsQuery — pending IDs
# ══════════════════════════════════════════════════════════════════════════

Then("the pending IDs should include the KYC without a report") do
  expect(@kyc_dashboard[:pending_ids]).to include(@last_kyc_without_report.id),
    "Expected pending_ids to include #{@last_kyc_without_report.id}, got: #{@kyc_dashboard[:pending_ids].inspect}"
end

Then("the pending IDs should not include the KYC with a report") do
  expect(@kyc_dashboard[:pending_ids]).not_to include(@last_kyc_with_report.id),
    "Expected pending_ids NOT to include #{@last_kyc_with_report.id}, got: #{@kyc_dashboard[:pending_ids].inspect}"
end

# ══════════════════════════════════════════════════════════════════════════
# KycDashboardHelper — status classification
# ══════════════════════════════════════════════════════════════════════════

Given("a KYC with no agent report") do
  @helper_kyc = create_dashboard_kyc
  @helper_report = nil
end

Given("a KYC with a report whose final_status is {string}") do |final_status|
  @helper_kyc = create_dashboard_kyc
  fields = case final_status
           when "ready" then ready_report_fields
           when "blocked" then blocked_no_success_fields
           end
  @helper_report = create_dashboard_report(@helper_kyc, fields)
end

Given("a KYC with a report whose final_status is {string} and has no success issues") do |_status|
  @helper_kyc = create_dashboard_kyc
  @helper_report = create_dashboard_report(@helper_kyc, blocked_no_success_fields)
end

Given("a KYC with a report whose final_status is {string} and has success issues") do |_status|
  @helper_kyc = create_dashboard_kyc
  @helper_report = create_dashboard_report(@helper_kyc, blocked_with_success_fields)
end

Given("a KYC with a report whose final_status is {string} and expiry_date is yesterday") do |_status|
  @helper_kyc = create_dashboard_kyc(expiry_date: Time.zone.today - 1.day)
  @helper_report = create_dashboard_report(@helper_kyc, ready_report_fields)
end

When("I classify the KYC dashboard status") do
  @dashboard_status = kyc_agent_status(@helper_kyc, @helper_report)
end

Then("the dashboard status should be {string}") do |expected|
  expect(@dashboard_status).to eq(expected),
    "Expected dashboard status '#{expected}', got '#{@dashboard_status}'"
end

# ══════════════════════════════════════════════════════════════════════════
# KycDashboardHelper — result summary
# ══════════════════════════════════════════════════════════════════════════

Given("a KYC report with {int} success issues and {int} blocking issues") do |success_count, blocking_count|
  field_issues = []
  success_count.times { |i| field_issues << { "message" => "field_#{i}", "severity" => "success", "type" => "info" } }
  blocking_count.times { |i| field_issues << { "message" => "bad_#{i}", "severity" => "blocking", "type" => "invalid_field_value" } }

  kyc = create_dashboard_kyc
  @summary_report = create_dashboard_report(kyc,
    "final_status" => "blocked",
    "field_issues" => field_issues,
    "document_issues" => [],
    "run_at" => Time.current.iso8601)
end

When("I compute the result summary") do
  @result_summary = kyc_result_summary(@summary_report)
end

When("I compute the result summary for a nil report") do
  @result_summary = kyc_result_summary(nil)
end

Then("the result summary should be {string}") do |expected|
  expect(@result_summary).to eq(expected),
    "Expected result summary '#{expected}', got '#{@result_summary}'"
end

# ══════════════════════════════════════════════════════════════════════════
# KycDashboardHelper — doc ratio display
# ══════════════════════════════════════════════════════════════════════════

When("I check the doc ratio color for uploaded={int}, required={int}") do |uploaded, required|
  @ratio_color = kyc_doc_ratio_color(uploaded, required)
end

Then("the doc ratio color should be {string}") do |expected|
  expect(@ratio_color).to eq(expected),
    "Expected doc ratio color '#{expected}', got '#{@ratio_color}'"
end

# ══════════════════════════════════════════════════════════════════════════
# KycDashboardHelper — show mark verified
# ══════════════════════════════════════════════════════════════════════════

Given("a KYC that is not verified with a {string} report") do |final_status|
  @verified_kyc = create_dashboard_kyc(verified: false)
  fields = final_status == "ready" ? ready_report_fields : blocked_no_success_fields
  @verified_report = create_dashboard_report(@verified_kyc, fields)
end

Given("a KYC that is verified with a {string} report") do |final_status|
  @verified_kyc = create_dashboard_kyc(verified: true, submission_status: "verified")
  @verified_report = create_dashboard_report(@verified_kyc, ready_report_fields)
end

When("I check whether to show mark verified") do
  @show_verified = show_mark_verified?(@verified_kyc, @verified_report)
end

Then("mark verified should be shown") do
  expect(@show_verified).to be(true), "Expected show_mark_verified? to be true"
end

Then("mark verified should not be shown") do
  expect(@show_verified).to be(false), "Expected show_mark_verified? to be false"
end

# ══════════════════════════════════════════════════════════════════════════
# KycDashboardHelper — run output items
# ══════════════════════════════════════════════════════════════════════════

Given("a KYC report with field issues and document issues") do
  kyc = create_dashboard_kyc
  @output_report = create_dashboard_report(kyc,
    "final_status" => "blocked",
    "field_issues" => [
      { "message" => "PAN", "severity" => "success", "type" => "info" },
      { "message" => "address", "severity" => "blocking", "type" => "invalid_field_value", "value" => "" }
    ],
    "document_issues" => [
      { "name" => "Passport", "message" => "Valid passport", "severity" => "success", "type" => "info" },
      { "name" => "PAN Card", "message" => "Missing", "severity" => "blocking", "type" => "missing" }
    ],
    "run_at" => Time.current.iso8601)
end

When("I compute the run output items") do
  @output_items = kyc_run_output_items(@output_report)
  @output_counts = kyc_run_output_counts(@output_items)
end

Then("the output should have field-sourced and document-sourced rows") do
  field_rows = @output_items.select { |i| i[:source] == :field }
  doc_rows = @output_items.select { |i| i[:source] == :document }
  expect(field_rows).not_to be_empty, "Expected field-sourced rows but got none"
  expect(doc_rows).not_to be_empty, "Expected document-sourced rows but got none"
end

Then("the output counts should tally all items by status") do
  expect(@output_counts["all"]).to eq(@output_items.size),
    "Expected 'all' count #{@output_items.size}, got #{@output_counts['all']}"
  expect(@output_counts["documents"]).to eq(@output_items.count { |i| i[:source] == :document }),
    "Expected 'documents' count to match document-sourced items"
  # Passed + Failed should account for all items (no warnings in this test data)
  expect(@output_counts["passed"].to_i + @output_counts["failed"].to_i).to eq(@output_items.size),
    "Expected passed + failed to equal total items"
end

# ══════════════════════════════════════════════════════════════════════════
# Non-KYC agent guard
# ══════════════════════════════════════════════════════════════════════════

Given("there is a portfolio scoring agent instead of KYC") do
  @other_agent = SupportAgent.create!(
    name: "Scoring Agent",
    agent_type: "PortfolioScoringAgent",
    entity: @entity,
    enabled: true
  )
end

When("I load the KYC dashboard data for that agent") do
  query = AgentReportsQuery.new(@other_agent)
  @kyc_dashboard = query.kyc_dashboard_data
end

Then("the dashboard data should be empty with zero stats") do
  expect(@kyc_dashboard[:basic_stats][:verified]).to eq(0)
  expect(@kyc_dashboard[:basic_stats][:not_sent]).to eq(0)
  expect(@kyc_dashboard[:type_stats][:individual][:validated]).to eq(0)
  expect(@kyc_dashboard[:records]).to be_empty
  expect(@kyc_dashboard[:top_failures]).to be_empty
  expect(@kyc_dashboard[:pending_ids]).to be_empty
end
