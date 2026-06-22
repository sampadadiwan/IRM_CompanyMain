# frozen_string_literal: true

# Step definitions for features/ai/support_agents/investor_presentation_analyst_agent.feature
#
# Strategy:
#   - Agent is invoked directly via PresentationAnalystAgent.call — no browser
#   - Real LlmService.ruby_llm_chat is used (no doubles) so the LLM actually processes
#     the presentation text and returns real extraction/comparison/question JSON
#   - Presentation text is written to Tempfiles and attached to Document records via
#     Shrine (doc.file = File.open(tmp.path)) — exactly like kpi_workbook_steps.rb
#   - Assertions are structural: "has N records", "has > 0 questions", "score present"
#     rather than asserting on exact LLM-generated values which are non-deterministic
#
# PRD: docs/ai/investor_presentation_analyst_prd.md

# ─── Dummy Presentation Text ──────────────────────────────────────────────────
# Realistic investor update text written to Tempfiles and attached to KPI reports.
# Concise enough to fit comfortably in one gemini-3-flash-preview call while containing
# all the signals the extraction and comparator prompts are designed to surface:
# commitments, risks, dropped initiatives, objective changes, metric trends.

Q1_2025_TEXT = <<~TEXT.freeze
  ACME ANALYTICS — INVESTOR UPDATE Q1 2025

  Dear Investors,

  Q1 marked a strong start to our enterprise push.

  KEY METRICS
  ARR: $5.2M  |  NRR: 118%  |  Burn: $420K/month  |  Runway: 22 months

  COMMITMENTS
  We are committed to reaching $8M ARR by Q4 2025. Our $14M qualified pipeline supports this.

  RISKS
  - Data residency compliance: HIGH PRIORITY. External legal counsel engaged; resolution expected in 60 days.
  - Customer concentration: MEDIUM. Top 3 customers represent 58% of ARR.

  INITIATIVES
  - Automation Platform: on track to launch within 90 days (Q2 2025).
  - Enterprise Sales Expansion: 2 additional AEs hired and ramping.

  STRATEGIC OBJECTIVE
  Enterprise mid-market (100–500 employees) is our primary ICP for 2025. SMB is not on our roadmap.

  — Acme Analytics Management
TEXT

Q4_2025_TEXT = <<~TEXT.freeze
  ACME ANALYTICS — INVESTOR UPDATE Q4 2025

  Dear Investors,

  Q4 closed with strong momentum as we transition into our next growth phase.

  KEY METRICS
  ARR: $6.1M  |  NRR: 102%  |  Burn: $510K/month  |  Runway: 14 months

  ACCOMPLISHMENTS
  - Expanded into healthcare analytics and supply chain verticals.
  - New VP Sales joining January 2026 following leadership transition.

  RISKS
  - Customer concentration: MEDIUM. Top 3 customers now at 62% of ARR. Expanding pipeline.

  STRATEGIC OBJECTIVE
  SMB self-serve is our primary growth motion for 2026. The addressable market is significantly
  larger and our product wins without heavy sales overhead.

  FORWARD PLANS
  - Launch SMB self-serve tier in H1 2026.
  - Raise Series B at $25M target in Q2 2026.

  — Acme Analytics Management
TEXT

Q3_2025_TEXT = <<~TEXT.freeze
  ACME ANALYTICS — INVESTOR UPDATE Q3 2025

  KEY METRICS
  ARR: $6.5M  |  NRR: 109%  |  Burn: $490K/month  |  Runway: 17 months

  ACCOMPLISHMENTS
  - Closed 4 enterprise deals, average ACV $180K.
  - Launched analytics engine v2 with 40% performance improvement.

  RISKS
  - Customer concentration: MEDIUM. Top 3 at 55%.
  - Competitive entrant: LOW. Being monitored.

  STRATEGIC OBJECTIVE
  Enterprise mid-market remains our primary ICP for 2025.

  FORWARD PLANS
  Close Q4 at approximately $7M ARR. Evaluating adjacent market opportunities for 2026.

  — Acme Analytics Management
TEXT

BETA_CORP_TEXT = <<~TEXT.freeze
  BETA CORP — INVESTOR UPDATE Q4 2025

  KEY METRICS
  ARR: $3.2M  |  NRR: 108%  |  Burn: $280K/month  |  Runway: 18 months

  COMMITMENTS
  Reach $5M ARR by mid-2026 following our Series A close in Q3 2025.

  RISKS
  - Key-person dependency on founding CTO: HIGH. Recruiting VP Engineering.

  STRATEGIC OBJECTIVE
  B2B SaaS for logistics optimisation in Southeast Asia.

  — Beta Corp Management
TEXT

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Returns the SupportAgentReport for a given portfolio company and @agent.
def presentation_report(portfolio_company = @portfolio_company)
  SupportAgentReport
    .where(owner: portfolio_company, support_agent: @agent)
    .order(created_at: :desc)
    .first
end

# Creates or retrieves the PresentationAnalystAgent SupportAgent for @entity.
def build_presentation_agent(entity, extra_fields = {})
  SupportAgent.find_or_create_by!(agent_type: "PresentationAnalystAgent", entity: entity) do |a|
    a.name       = "Investor Presentation Analyst"
    a.enabled    = true
    # gemini-3-flash-preview has a 1M token context window — required for full-document processing.
    # PRD §4.1: "Full document needs to be processed — gemini has a 1M context."
    a.llm_model  = "gemini-3-flash-preview"
    a.json_fields = {
      "presentation_doc_names" => "Investor Update, Board Deck, Management Presentation, Quarterly Update, Investor Presentation",
      "max_periods"            => "8",
      "kpi_tag_list"           => "Actual",
      "comparison_strategy"    => "all_periods",
      "llm_model"              => "gemini-3-flash-preview",
      "enable_scoring"         => "Yes",
      "enable_questions"       => "Yes"
    }.merge(extra_fields)
  end
end

# Creates a KpiReport and attaches a real text file (via Shrine) containing +text+.
# The doc.file is set from a Tempfile so read_document_text can download and read it
# exactly like production — no file I/O stubs.
def create_presentation_report(portfolio_company:, text:, doc_name: "Investor Update", as_of:, period: "Quarter")
  report = KpiReport.create!(
    entity:            @entity,
    portfolio_company: portfolio_company,
    user:              @user,
    as_of:             as_of,
    period:            period,
    tag_list:          "Actual"
  )

  # Write presentation content to a named Tempfile with .txt extension so
  # extract_text_from_file picks the simple File.read branch (no LibreOffice/Pandoc needed).
  tmp = Tempfile.new(["presentation_#{as_of}", ".txt"])
  tmp.write(text)
  tmp.flush
  tmp.rewind

  doc = Document.new(
    name:       doc_name,
    entity:     @entity,
    owner:      report,
    user:       @user,
    folder:     report.document_folder,
    send_email: false
  )
  # Attach via real Shrine upload — same pattern as kpi_workbook_steps.rb.
  doc.file = File.open(tmp.path)
  doc.save!
  tmp.close!

  doc
end

# ─── Background / Agent Setup ────────────────────────────────────────────────

Given("the investor presentation analyst agent is configured for the entity") do
  @agent = build_presentation_agent(@entity)
end

Given("the investor presentation analyst agent is disabled") do
  @agent ||= build_presentation_agent(@entity)
  @agent.update!(enabled: false)
end

Given("the agent is configured with comparison_strategy {string}") do |strategy|
  @agent.update!(json_fields: @agent.json_fields.merge("comparison_strategy" => strategy))
end

Given("the agent is configured with presentation_doc_names {string}") do |names|
  @agent.update!(json_fields: @agent.json_fields.merge("presentation_doc_names" => names))
end

# Stubs LlmService.ruby_llm_chat with fixed canned responses (by prompt type) so the
# digest-caching scenario can verify the caching logic itself — comparing a SHA-256 of
# cross_period_flags across two runs — without live-LLM wording drift between runs
# producing a different digest from identical input. Stubbed at the service layer
# (not allow_any_instance_of(RubyLLM::Chat)) — see kyc_onboarding_agent_steps.rb for why.
Given("the LLM gives deterministic responses for digest caching") do
  extraction_response = <<~JSON
    ```json
    {"management_narrative": "Steady execution, no notable tone shift.", "commitments": [],
     "risks": [], "accomplishments": [], "forward_plans": [], "strategic_objectives": [],
     "key_metrics": [], "initiatives": []}
    ```
  JSON

  comparator_response = <<~JSON
    ```json
    {"commitment_tracker": [], "risk_evolution": [], "objective_drift": [],
     "initiative_graveyard": [], "metric_anomalies": []}
    ```
  JSON

  questions_response = <<~JSON
    ```json
    [{"question": "ARR growth decelerated — what changed in the sales motion?",
      "category": "Metrics", "source_period": "Q4 2025", "source_evidence": "ARR $6.1M"}]
    ```
  JSON

  mock_chat = double("chat")
  allow(mock_chat).to receive(:ask) do |prompt|
    content = if prompt.include?("EXTRACTION RULES:")
                extraction_response
              elsif prompt.include?("Compare these investor presentations")
                comparator_response
              else
                questions_response
              end
    OpenStruct.new(content: content)
  end
  allow(LlmService).to receive(:ruby_llm_chat).and_return(mock_chat)
end

# ─── Presentation Document Creation ──────────────────────────────────────────

Given("Acme Analytics has a Q1 2025 investor presentation attached to a KPI report") do
  create_presentation_report(
    portfolio_company: @portfolio_company,
    text:              Q1_2025_TEXT,
    as_of:             Date.new(2025, 3, 31)
  )
end

Given("Acme Analytics has a Q3 2025 investor presentation with a declining NRR") do
  create_presentation_report(
    portfolio_company: @portfolio_company,
    text:              Q3_2025_TEXT,
    as_of:             Date.new(2025, 9, 30)
  )
end

Given("Acme Analytics has a Q4 2025 investor presentation showing a missed ARR target") do
  create_presentation_report(
    portfolio_company: @portfolio_company,
    text:              Q4_2025_TEXT,
    as_of:             Date.new(2025, 12, 31)
  )
end

Given("Acme Analytics has a KPI report with a document named {string}") do |doc_name|
  # doc_name does NOT match any default presentation_doc_names →
  # collect_presentations finds nothing and marks the run as blocked.
  report = KpiReport.create!(
    entity:            @entity,
    portfolio_company: @portfolio_company,
    user:              @user,
    as_of:             Date.new(2025, 12, 31),
    period:            "Quarter",
    tag_list:          "Actual"
  )
  tmp = Tempfile.new(["non_presentation", ".txt"])
  tmp.write("This is a financial model, not an investor presentation.")
  tmp.flush; tmp.rewind
  doc = Document.new(name: doc_name, entity: @entity, owner: report, user: @user,
                     folder: report.document_folder, send_email: false)
  doc.file = File.open(tmp.path)
  doc.save!
  tmp.close!
end

Given("Beta Corp has a Q4 2025 investor presentation") do
  @beta_corp ||= Investor.find_by(investor_name: "Beta Corp", entity: @entity)
  create_presentation_report(
    portfolio_company: @beta_corp,
    text:              BETA_CORP_TEXT,
    as_of:             Date.new(2025, 12, 31)
  )
end

Given("each company has one investor presentation") do
  # Acme Analytics Q4 2025 (step assumed to have been called separately in batch scenario)
  # Beta Corp Q4 2025 — created here so the step is self-contained
  step "Acme Analytics has a Q4 2025 investor presentation showing a missed ARR target"
  step "Beta Corp has a Q4 2025 investor presentation"
end

# ─── Agent Config Mutations ───────────────────────────────────────────────────

# Custom doc name filter: overrides DEFAULT_DOC_NAMES so only "Board Update"- or
# "Q-Report"-named documents are picked up (PRD §12.1 — presentation_doc_names).
Given("Acme Analytics has a KPI report with a document named {string} matching the custom filter") do |doc_name|
  create_presentation_report(
    portfolio_company: @portfolio_company,
    text:              Q4_2025_TEXT,
    doc_name:          doc_name,
    as_of:             Date.new(2025, 12, 31)
  )
end

# ─── Agent Execution ──────────────────────────────────────────────────────────

When("I run the investor presentation analyst agent for Acme Analytics") do
  # Uses real LlmService.ruby_llm_chat — the LLM actually reads the presentation text.
  PresentationAnalystAgent.call(
    support_agent_id: @agent.id,
    target:           @portfolio_company
  )
  @report = presentation_report(@portfolio_company)
  @report&.reload
end

When("I run the investor presentation analyst agent for {string}") do |investor_name|
  target = Investor.find_by!(investor_name: investor_name, entity: @entity)
  PresentationAnalystAgent.call(
    support_agent_id: @agent.id,
    target:           target
  )
  @skipped_target     = target
  @report_for_skipped = SupportAgentReport.find_by(owner: target, support_agent: @agent)
end

When("I run the investor presentation analyst agent in batch mode for both companies") do
  @beta_corp ||= Investor.find_by(investor_name: "Beta Corp", entity: @entity)
  targets = Investor.where(id: [@portfolio_company.id, @beta_corp.id], entity: @entity)
  @batch_result = PresentationAnalystAgent.process_batch(
    support_agent_id: @agent.id,
    targets:          targets,
    user_id:          @user.id,
    entity_id:        @entity.id,
    execution_mode:   :adhoc_batch
  )
end

# Second run for the caching scenario: re-runs the agent for the same company.
# The flags_digest from the first run is compared; if unchanged, questions are reused.
When("I run the investor presentation analyst agent for Acme Analytics a second time") do
  PresentationAnalystAgent.call(
    support_agent_id: @agent.id,
    target:           @portfolio_company
  )
  @report = presentation_report(@portfolio_company)
  @report&.reload
end

# ─── Assertions — Report Existence ───────────────────────────────────────────

Then("the analyst report final_status should be {string}") do |expected|
  expect(@report).to be_present,
    "Expected a SupportAgentReport for #{@portfolio_company.investor_name} but none was found"
  expect(@report.json_fields["final_status"]).to eq(expected),
    "Expected final_status=#{expected.inspect} but got #{@report.json_fields['final_status'].inspect}"
end

Then("no analyst report should be created for Acme Analytics") do
  expect(presentation_report(@portfolio_company)).to be_nil,
    "Expected no SupportAgentReport for Acme Analytics but one was created"
end

Then("no analyst report should be created for {string}") do |investor_name|
  expect(@report_for_skipped).to be_nil,
    "Expected no report for '#{investor_name}' but one was created"
end

# ─── Assertions — Period Records ──────────────────────────────────────────────

Then("the analyst report should have {int} period_record(s)") do |count|
  records = @report.json_fields["period_records"] || []
  expect(records.size).to eq(count),
    "Expected #{count} period_record(s) but got #{records.size}: " \
    "#{records.map { |r| r['period_label'] }.inspect}"
end

Then("each period_record should contain the eight extraction categories") do
  records = @report.json_fields["period_records"] || []
  expected_keys = %w[management_narrative commitments risks accomplishments
                     forward_plans strategic_objectives key_metrics initiatives]
  records.each do |record|
    missing = expected_keys.reject { |k| record.key?(k) }
    expect(missing).to be_empty,
      "Period '#{record['period_label']}' is missing keys: #{missing.inspect}"
  end
end

# ─── Assertions — Cross-Period Flags ─────────────────────────────────────────

Then("the analyst report cross_period_flags should be empty") do
  flags     = @report.json_fields["cross_period_flags"] || {}
  all_items = flags.values.flatten
  expect(all_items).to be_empty,
    "Expected empty cross_period_flags but got: #{flags.inspect}"
end

Then("the analyst report cross_period_flags should be present") do
  flags     = @report.json_fields["cross_period_flags"] || {}
  all_items = flags.values.flatten
  expect(all_items).not_to be_empty,
    "Expected non-empty cross_period_flags but all lenses were empty"
end

Then("the analyst report cross_period_flags should include at least one commitment entry") do
  tracker = @report.json_fields.dig("cross_period_flags", "commitment_tracker") || []
  expect(tracker).not_to be_empty,
    "Expected at least one commitment_tracker entry but got none"
end

Then("the analyst report cross_period_flags should include the five comparison lenses") do
  flags         = @report.json_fields["cross_period_flags"] || {}
  expected_keys = %w[commitment_tracker risk_evolution objective_drift initiative_graveyard metric_anomalies]
  missing       = expected_keys.reject { |k| flags.key?(k) }
  expect(missing).to be_empty,
    "cross_period_flags is missing lenses: #{missing.inspect}. Got keys: #{flags.keys.inspect}"
end

# ─── Assertions — Analyst Questions ──────────────────────────────────────────

Then("the analyst report should have at least {int} analyst question(s)") do |min_count|
  questions = @report.json_fields["analyst_questions"] || []
  expect(questions.size).to be >= min_count,
    "Expected at least #{min_count} question(s) but got #{questions.size}"
end

Then("each analyst question should have a question, category, source_period, and source_evidence") do
  questions = @report.json_fields["analyst_questions"] || []
  expect(questions).not_to be_empty, "No analyst questions found to validate structure"
  questions.each_with_index do |q, i|
    %w[question category source_period source_evidence].each do |key|
      expect(q[key]).to be_present,
        "Question #{i + 1} is missing '#{key}': #{q.inspect}"
    end
  end
end

# ─── Assertions — Scoring ─────────────────────────────────────────────────────

Then("the analyst report should have a Management Accountability Score") do
  score = @report.json_fields["score"]
  expect(score).to be_present,
    "Expected a 'score' object in json_fields but it was nil/absent"
  expect(score["overall_score"]).to be_between(0, 100),
    "overall_score #{score['overall_score']} is outside 0–100"
  expect(score["grade"]).to be_present,
    "Expected a grade but got nil/blank"
  expect(score["periods_analyzed"]).to be_present,
    "Expected periods_analyzed count in the score object"
end

Then("the score dimensions should be present") do
  score = @report.json_fields["score"] || {}
  %w[commitment_score risk_score coherence_score narrative_score].each do |dim|
    expect(score[dim]).to be_present, "Score dimension '#{dim}' is missing"
    expect(score[dim]).to be_between(0, 100), "'#{dim}' value #{score[dim]} is outside 0–100"
  end
end

# ─── Assertions — Issues ──────────────────────────────────────────────────────

Then("the analyst report collection_issues should mention {string}") do |fragment|
  issues  = @report.json_fields["collection_issues"] || []
  matching = issues.select { |i| i["message"].to_s.include?(fragment) }
  expect(matching).not_to be_empty,
    "Expected a collection_issue mentioning '#{fragment}' but got: " \
    "#{issues.map { |i| i['message'] }.inspect}"
end

Then("the analyst report analysis_issues should mention {string}") do |fragment|
  issues  = @report.json_fields["analysis_issues"] || []
  matching = issues.select { |i| i["message"].to_s.include?(fragment) }
  expect(matching).not_to be_empty,
    "Expected an analysis_issue mentioning '#{fragment}' but got: " \
    "#{issues.map { |i| i['message'] }.inspect}"
end

# ─── Assertions — Caching ─────────────────────────────────────────────────────

Then("the analyst report should store a flags_digest") do
  digest = @report.json_fields["flags_digest"]
  expect(digest).to be_present,
    "Expected flags_digest in json_fields but it was absent"
  expect(digest).to match(/\A[0-9a-f]{64}\z/),
    "Expected a SHA-256 hex digest but got: #{digest.inspect}"
  @stored_digest = digest
end

Then("the analyst report should have the same flags_digest as the first run") do
  current_digest = @report.json_fields["flags_digest"]
  expect(current_digest).to eq(@stored_digest),
    "Expected digest to be unchanged (#{@stored_digest}) but got #{current_digest}"
end

Then("the analyst report should have the same analyst questions as the first run") do
  current_questions = @report.json_fields["analyst_questions"] || []
  expect(current_questions).to eq(@first_run_questions),
    "Expected cached questions to be reused but questions changed between runs"
end

# Stores first-run questions for later comparison in the caching scenario
Then("I record the first run questions and flags_digest") do
  @first_run_questions = @report.json_fields["analyst_questions"] || []
  @stored_digest       = @report.json_fields["flags_digest"]
end

# ─── Assertions — Batch ───────────────────────────────────────────────────────

Then("an analyst report should exist for Acme Analytics") do
  expect(presentation_report(@portfolio_company)).to be_present,
    "Expected a SupportAgentReport for Acme Analytics but none was found"
end

Then("an analyst report should exist for Beta Corp") do
  @beta_corp ||= Investor.find_by(investor_name: "Beta Corp", entity: @entity)
  expect(presentation_report(@beta_corp)).to be_present,
    "Expected a SupportAgentReport for Beta Corp but none was found"
end

# ─── Second Portfolio Company (batch scenario) ────────────────────────────────

Given("there is also a portfolio company for batch run {string}") do |args|
  # "there is an existing portfolio company" (investor.rb) overwrites @portfolio_company
  # with whatever it just created — preserve and restore Acme's reference so later steps
  # like "Acme Analytics has a Q4 2025 investor presentation..." don't target Beta Corp instead.
  acme = @portfolio_company
  steps %(Given there is an existing portfolio company "#{args}")
  @beta_corp = @investor
  @portfolio_company = acme
end
