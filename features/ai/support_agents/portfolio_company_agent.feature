Feature: Portfolio Company Agent
  As a fund administrator
  I want the portfolio company agent to validate KPI submissions, documents, and valuations
  So that I can identify data health issues across all portfolio companies

  # The agent runs these steps in order:
  #   initialize_agent → check_kpi_submission → send_kpi_reminder →
  #   check_document_presence → check_valuations → generate_progress_reports
  #
  # All dates are period-relative so the feature stays green regardless of
  # when the tests run. KPI / valuation records use as_of / valuation_date
  # computed in step definitions as "one day after the previous quarter end".

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is an existing portfolio company "name=TestCorp;category=Portfolio Company"
    And the portfolio company agent is enabled

  # ── Happy path ──────────────────────────────────────────────────────────

  Scenario: KPIs submitted and valuation present — report is ready
    Given the portfolio company has submitted KPIs for the current period
    And the portfolio company has a recent valuation
    When I run the portfolio company agent
    Then the portfolio agent report final status should be "ready"
    And the portfolio agent report should have a successful KPI issue
    And the portfolio agent report should have a successful valuation issue

  # ── KPI submission ───────────────────────────────────────────────────────

  Scenario: KPIs not submitted — report is blocked
    Given the portfolio company has no KPI reports
    And the portfolio company has a recent valuation
    When I run the portfolio company agent
    Then the portfolio agent report final status should be "blocked"
    And the portfolio agent report should have a blocking KPI issue

  # ── KPI reminder ─────────────────────────────────────────────────────────

  Scenario: KPIs missing and today is a reminder day — reminder email sent
    Given the portfolio company agent has KPI reminders enabled for today
    And the portfolio company has no KPI reports
    When I run the portfolio company agent
    Then a KPI reminder email should have been sent
    And the portfolio agent report should record that a reminder was sent today

  Scenario: KPI reminder already sent today — no duplicate email
    Given the portfolio company agent has KPI reminders enabled for today
    And the portfolio company has no KPI reports
    And a KPI reminder was already sent today for the portfolio company
    When I run the portfolio company agent
    Then no KPI reminder email should have been sent

  # ── Valuation ────────────────────────────────────────────────────────────

  Scenario: Valuation missing — report is blocked
    Given the portfolio company has submitted KPIs for the current period
    And the portfolio company has no valuations
    When I run the portfolio company agent
    Then the portfolio agent report final status should be "blocked"
    And the portfolio agent report should have a blocking valuation issue

  Scenario: Both KPIs and valuation missing — report is blocked with both issues
    Given the portfolio company has no KPI reports
    And the portfolio company has no valuations
    When I run the portfolio company agent
    Then the portfolio agent report final status should be "blocked"
    And the portfolio agent report should have a blocking KPI issue
    And the portfolio agent report should have a blocking valuation issue

  # ── Document presence ────────────────────────────────────────────────────

  Scenario: Required document missing from KPI report — report is blocked
    Given the portfolio company agent requires a "Financial Statement" document
    And the portfolio company has submitted KPIs for the current period
    And the KPI report has no documents uploaded
    When I run the portfolio company agent
    Then the portfolio agent report final status should be "blocked"
    And the portfolio agent report should have a blocking document issue mentioning "Financial Statement"

  Scenario: No KPI report — document check is skipped, no spurious blocking issue
    Given the portfolio company agent requires a "Financial Statement" document
    And the portfolio company has no KPI reports
    When I run the portfolio company agent
    Then the portfolio agent report final status should be "blocked"
    And the portfolio agent report should not have a blocking document issue

  # ── Initialization guards ────────────────────────────────────────────────

  Scenario: Investor that is not a portfolio company is skipped
    Given there is an existing investor "investor_name=LPInvestor"
    And the portfolio company agent is enabled
    When I run the portfolio company agent for the LP investor
    Then no portfolio agent report should be created for the LP investor

  Scenario: Disabled agent skips all processing
    Given the portfolio company agent is disabled
    And the portfolio company has submitted KPIs for the current period
    When I run the portfolio company agent
    Then no portfolio agent report should be created

  # ── Batch processing ─────────────────────────────────────────────────────

  Scenario: Batch run processes multiple companies and returns success/error counts
    Given there is also a portfolio company "name=OtherCorp;category=Portfolio Company"
    And the portfolio company has submitted KPIs for the current period
    And the portfolio company has a recent valuation
    When I run the portfolio company agent in batch mode
    Then the batch result should show 2 successes and 0 errors
