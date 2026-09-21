Feature: Investor Presentation Analyst Agent
  As a fund manager
  I want the agent to read investor presentations across periods
  So that I get a pre-board briefing, cross-period flags, and a Management Accountability Score
  without manually re-reading every deck before every board call

  # The agent pipeline (7 Trailblazer steps):
  #   initialize_agent → collect_presentations → extract_intelligence →
  #   compare_across_periods → generate_analyst_qs → compute_scores → store_results
  #
  # These are integration tests — the real LlmService.ruby_llm_chat is called.
  # Presentation text is real .txt content written to Tempfiles and attached via Shrine.
  # Assertions are structural (presence, type, count) rather than exact LLM values.
  #
  # Tag @llm marks scenarios that make live API calls (gemini-3-flash).
  #
  # PRD: docs/modules/ai/investor_presentation_analyst_prd.md

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=Acme Analytics;category=Portfolio Company"
    And the investor presentation analyst agent is configured for the entity

  # ── Happy path — two presentations, full pipeline ────────────────────────────

  @llm
  Scenario: Two presentations — extracts, compares, generates briefing, and scores
    # Acme Analytics committed to $8M ARR in Q1 but only delivered $6.1M by Q4.
    # The data residency risk was silently dropped. NRR declined from 118% to 102%.
    # Expected: period_records for both periods, at least 1 analyst question,
    # cross_period_flags present, and a full Management Accountability Score.
    Given Acme Analytics has a Q1 2025 investor presentation attached to a KPI report
    And Acme Analytics has a Q4 2025 investor presentation showing a missed ARR target
    When I run the investor presentation analyst agent for Acme Analytics
    Then the analyst report final_status should be "ready"
    And the analyst report should have 2 period_records
    And each period_record should contain the eight extraction categories
    And the analyst report cross_period_flags should be present
    And the analyst report cross_period_flags should include the five comparison lenses
    And the analyst report cross_period_flags should include at least one commitment entry
    And the analyst report should have at least 3 analyst questions
    And each analyst question should have a question, category, source_period, and source_evidence
    And the analyst report should have a Management Accountability Score
    And the score dimensions should be present

  # ── Single presentation — no cross-period analysis ───────────────────────────

  @llm
  Scenario: Only one presentation — extracts intelligence but skips comparison
    # With a single period, compare_across_periods skips the LLM call.
    # cross_period_flags will be empty; analysis_issues mentions the skip reason.
    Given Acme Analytics has a Q4 2025 investor presentation showing a missed ARR target
    When I run the investor presentation analyst agent for Acme Analytics
    Then the analyst report final_status should be "ready"
    And the analyst report should have 1 period_record
    And each period_record should contain the eight extraction categories
    And the analyst report cross_period_flags should be empty
    And the analyst report should have at least 1 analyst questions

  # ── No matching documents ─────────────────────────────────────────────────────

  Scenario: No presentation documents found — report is blocked
    # The agent looks for documents whose names match the presentation_doc_names CSV.
    # A "Financial Model" doc does not match any default name → collection blocked.
    Given Acme Analytics has a KPI report with a document named "Financial Model"
    When I run the investor presentation analyst agent for Acme Analytics
    Then the analyst report final_status should be "blocked"
    And the analyst report should have 0 period_records
    And the analyst report collection_issues should mention "No presentation documents found"

  # ── Digest caching — questions reused when flags unchanged ───────────────────

  Scenario: Questions are reused when cross-period flags have not changed
    # Run the agent twice on the same presentations with no data changes.
    # The second run should detect the same flags_digest and reuse the cached questions
    # rather than making a new LLM call for question generation.
    # LLM responses are stubbed deterministically here — this scenario tests the
    # caching logic itself, not live-LLM output, which can legitimately vary in
    # wording between identical calls and would make an exact digest match flaky.
    Given the LLM gives deterministic responses for digest caching
    And Acme Analytics has a Q1 2025 investor presentation attached to a KPI report
    And Acme Analytics has a Q4 2025 investor presentation showing a missed ARR target
    When I run the investor presentation analyst agent for Acme Analytics
    Then the analyst report should store a flags_digest
    And I record the first run questions and flags_digest
    When I run the investor presentation analyst agent for Acme Analytics a second time
    Then the analyst report final_status should be "ready"
    And the analyst report should have the same flags_digest as the first run
    And the analyst report should have the same analyst questions as the first run

  # ── Sliding window comparison strategy ───────────────────────────────────────

  @llm
  Scenario: Sliding window strategy makes one comparator call per adjacent pair
    # PRD §12.1: "sliding_window: one call per adjacent pair — cheaper when many periods."
    # With 3 presentations (Q1, Q3, Q4) there are 2 adjacent pairs.
    # The flags from both pairs are merged into a single cross_period_flags object.
    Given Acme Analytics has a Q1 2025 investor presentation attached to a KPI report
    And Acme Analytics has a Q3 2025 investor presentation with a declining NRR
    And Acme Analytics has a Q4 2025 investor presentation showing a missed ARR target
    And the agent is configured with comparison_strategy "sliding_window"
    When I run the investor presentation analyst agent for Acme Analytics
    Then the analyst report final_status should be "ready"
    And the analyst report should have 3 period_records
    And the analyst report cross_period_flags should be present

  # ── Initialization guards ─────────────────────────────────────────────────────

  Scenario: Non-portfolio-company target — agent skips immediately
    # initialize_agent returns false if target.category != "Portfolio Company".
    # No SupportAgentReport should be created for an LP investor.
    Given there is an existing investor "investor_name=Silent LP"
    When I run the investor presentation analyst agent for "Silent LP"
    Then no analyst report should be created for "Silent LP"

  Scenario: Disabled agent — skips all processing
    Given the investor presentation analyst agent is disabled
    And Acme Analytics has a Q4 2025 investor presentation showing a missed ARR target
    When I run the investor presentation analyst agent for Acme Analytics
    Then no analyst report should be created for Acme Analytics

  # ── Custom document name filter ───────────────────────────────────────────────

  @llm
  Scenario: Custom presentation_doc_names CSV overrides the default name list
    # When the GP configures "Board Update, Q-Report" the agent ignores default names
    # and only matches documents whose name contains "Board Update" or "Q-Report".
    Given the agent is configured with presentation_doc_names "Board Update, Q-Report"
    And Acme Analytics has a KPI report with a document named "Board Update Q4 2025" matching the custom filter
    When I run the investor presentation analyst agent for Acme Analytics
    Then the analyst report final_status should be "ready"
    And the analyst report should have 1 period_record

  # ── Batch run ─────────────────────────────────────────────────────────────────

  @llm
  Scenario: Batch run processes multiple portfolio companies sequentially
    # process_batch mirrors PortfolioScoringAgent: sequential, soft-fail per company.
    # Both companies have one presentation each → single-period runs.
    Given there is also a portfolio company for batch run "name=Beta Corp;category=Portfolio Company"
    And each company has one investor presentation
    When I run the investor presentation analyst agent in batch mode for both companies
    Then the batch result should show 2 successes and 0 errors
    And an analyst report should exist for Acme Analytics
    And an analyst report should exist for Beta Corp
