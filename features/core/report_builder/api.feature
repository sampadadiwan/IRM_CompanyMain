Feature: ReportBuilderController — HTTP API endpoints

  All scenarios use ActionDispatch::Integration::Session (no browser).
  The user is signed in via Devise form submission before each scenario.

  Background:
    Given a report builder entity and user
    And that entity has an investor "API Test Investor"
    And I am signed in as the report builder user

  # ── Model discovery ───────────────────────────────────────────────────────

  @rack_test
  Scenario: GET /report_builder/models returns available root models as JSON
    When I request the models endpoint
    Then the report builder API response should be successful
    And the models list should include "Investor"

  # ── Association discovery ─────────────────────────────────────────────────

  @rack_test
  Scenario: GET /report_builder/associations returns associations for a known model
    When I request the associations endpoint for "Investor"
    Then the report builder API response should be successful
    And the associations list should not be empty in the response

  # ── Create ────────────────────────────────────────────────────────────────

  @rack_test
  Scenario: POST /report_builder creates a new report with the given root model
    When I create a new report for root model "Investor"
    Then a report should be created with root model "Investor"

  # ── Column management ─────────────────────────────────────────────────────

  @rack_test
  Scenario: POST columns adds a GridViewPreference to the report
    When I create a new report for root model "Investor"
    And I add the column "investor_name" to the report
    Then the report should have column "investor_name"

  @rack_test
  Scenario: DELETE columns removes a GridViewPreference from the report
    When I create a new report for root model "Investor"
    And I add the column "investor_name" to the report
    And I add the column "city" to the report
    Then the report should have column "investor_name"
    And the report should have column "city"

  # ── Join management ───────────────────────────────────────────────────────

  @rack_test
  Scenario: POST join adds a join entry to the report template
    When I create a new report for root model "Investor"
    And I add the join "capital_commitments" with model "CapitalCommitment" to the report
    Then the report template should include join "capital_commitments"

  Scenario: DELETE join removes the join and its columns from the report
    When I create a new report for root model "Investor"
    And I add the join "capital_commitments" with model "CapitalCommitment" to the report
    And I add the column "capital_commitments.folio_committed_amount" to the report
    And I remove the join "capital_commitments" from the report
    Then the report template should not include join "capital_commitments"
    And the report should not have column "capital_commitments.folio_committed_amount"

  # ── Aggregate update ──────────────────────────────────────────────────────

  @rack_test
  Scenario: PATCH aggregate stores the chosen aggregate type in the template
    When I create a new report for root model "Investor"
    And I add the join "capital_commitments" with model "CapitalCommitment" to the report
    And I add the column "capital_commitments.folio_committed_amount" to the report
    And I update the aggregate for "capital_commitments.folio_committed_amount" to "sum"
    Then the report builder API response should be successful
    And the API JSON should have key "ok"
    And the report template aggregate for "capital_commitments.folio_committed_amount" should be "sum"

  # ── Name update ───────────────────────────────────────────────────────────

  @rack_test
  Scenario: PATCH name renames the report
    When I create a new report for root model "Investor"
    And I update the report name to "Monthly LP Summary"
    Then the report builder API response should be successful
    And the report name should be "Monthly LP Summary"

  # ── Schedule ──────────────────────────────────────────────────────────────

  @rack_test
  Scenario: PATCH schedule creates a ReportSchedule record
    When I create a new report for root model "Investor"
    And I configure the schedule with frequency "weekly" and recipient "lp@example.com"
    Then the report builder API response should be successful
    And a ReportSchedule should exist for the report
    And the ReportSchedule frequency should be "weekly"

  # ── Preview ───────────────────────────────────────────────────────────────

  @rack_test
  Scenario: GET preview returns a successful response
    When I create a new report for root model "Investor"
    And I add the column "investor_name" to the report
    When I request the preview for the report
    Then the report builder API response should be successful
