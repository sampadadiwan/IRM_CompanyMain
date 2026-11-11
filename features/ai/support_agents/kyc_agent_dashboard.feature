Feature: KYC Agent Dashboard
  As a fund administrator
  I want the KYC dashboard to show aggregate stats, status breakdowns, and filtered tables
  So that I can monitor KYC onboarding agent results at a glance

  # The KYC Dashboard tab on the KycOnboardingAgent show page displays:
  #   - Basic stats (submission status pipeline: not_sent → verified)
  #   - Type stats (Individual / Non-Individual breakdown with chart data)
  #   - Top failure reasons (most common blocking issues across all reports)
  #   - Filtered records (paginated table with status/type/search/date filters)
  #   - Document ratios (uploaded vs required per KYC)
  #   - Pending IDs (KYCs with no agent report yet)
  #
  # Data flows through AgentReportsQuery#kyc_dashboard_data → view helpers
  # (KycDashboardHelper) → ERB partials. Tests exercise the query + helper
  # layers directly — no browser, no LLM.
  #
  # Type stats, top failures, and status-filtered records use MySQL-specific
  # SQL (JSON_EXTRACT, JSON_SEARCH, CURDATE) and are not testable on SQLite.
  # Those are verified manually on staging.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is a KYC onboarding agent for the dashboard

  # ══════════════════════════════════════════════════════════════════════════
  # AgentReportsQuery — basic stats
  # ══════════════════════════════════════════════════════════════════════════

  Scenario: Basic stats count KYCs by submission status
    Given the entity has KYCs with submission statuses "not_sent,link_sent,completed,completed,verified"
    When I load the KYC basic stats
    Then the basic stats should show not_sent=1, link_sent=1, completed=2, verified_status=1

  Scenario: Basic stats count verified and unverified KYCs
    Given the entity has 2 verified and 1 unverified completed KYCs
    When I load the KYC basic stats
    Then the basic stats should show verified=2, unverified=1

  Scenario: Basic stats count individual and non-individual KYCs
    Given the entity has 2 individual and 1 non-individual completed KYCs
    When I load the KYC basic stats
    Then the basic stats should show individual=2, non_individual=1

  # ══════════════════════════════════════════════════════════════════════════
  # AgentReportsQuery — filtered records
  # ══════════════════════════════════════════════════════════════════════════

  Scenario: Filter records by KYC type returns only that STI type
    Given there is an individual KYC for "Indi Investor" with a "ready" agent report
    And there is a non-individual KYC for "Corp Investor" with a "ready" agent report
    When I load filtered KYC records with kyc_type "IndividualKyc"
    Then the filtered records should include "Indi Investor"
    And the filtered records should not include "Corp Investor"

  Scenario: Filter records by search matches investor name
    Given there is an individual KYC for "Searchable Name" with a "ready" agent report
    And there is an individual KYC for "Other Person" with a "ready" agent report
    When I load filtered KYC records with search "Searchable"
    Then the filtered records should include "Searchable Name"
    And the filtered records should not include "Other Person"

  # ══════════════════════════════════════════════════════════════════════════
  # AgentReportsQuery — document ratios
  # ══════════════════════════════════════════════════════════════════════════

  Scenario: Doc ratios count uploaded vs required documents per KYC
    Given there is a KYC with 2 required File fields and 1 uploaded document
    When I load the KYC doc ratios
    Then the doc ratio for that KYC should show uploaded=1, required=2
    And the doc ratio missing names should include the unuploaded field

  # ══════════════════════════════════════════════════════════════════════════
  # AgentReportsQuery — pending IDs
  # ══════════════════════════════════════════════════════════════════════════

  Scenario: Pending IDs returns KYCs with no latest agent report
    Given there is an individual KYC with a "ready" agent report
    And there is an individual KYC with no agent report
    When I load the KYC pending IDs
    Then the pending IDs should include the KYC without a report
    And the pending IDs should not include the KYC with a report

  # ══════════════════════════════════════════════════════════════════════════
  # KycDashboardHelper — status classification
  # ══════════════════════════════════════════════════════════════════════════

  Scenario: Status is Pending when KYC has no report
    Given a KYC with no agent report
    When I classify the KYC dashboard status
    Then the dashboard status should be "Pending"

  Scenario: Status is Successful when report final_status is ready
    Given a KYC with a report whose final_status is "ready"
    When I classify the KYC dashboard status
    Then the dashboard status should be "Successful"

  Scenario: Status is Failed when report is blocked with no success issues
    Given a KYC with a report whose final_status is "blocked" and has no success issues
    When I classify the KYC dashboard status
    Then the dashboard status should be "Failed"

  Scenario: Status is Partially Failed when report is blocked but has some successes
    Given a KYC with a report whose final_status is "blocked" and has success issues
    When I classify the KYC dashboard status
    Then the dashboard status should be "Partially Failed"

  Scenario: Status is Expired when KYC expiry_date is in the past regardless of report
    Given a KYC with a report whose final_status is "ready" and expiry_date is yesterday
    When I classify the KYC dashboard status
    Then the dashboard status should be "Expired"

  # ══════════════════════════════════════════════════════════════════════════
  # KycDashboardHelper — result summary
  # ══════════════════════════════════════════════════════════════════════════

  Scenario: Result summary shows passed count of total items
    Given a KYC report with 3 success issues and 2 blocking issues
    When I compute the result summary
    Then the result summary should be "3 of 5 items passed"

  Scenario: Result summary is a dash when there is no report
    When I compute the result summary for a nil report
    Then the result summary should be "—"

  # ══════════════════════════════════════════════════════════════════════════
  # KycDashboardHelper — doc ratio display
  # ══════════════════════════════════════════════════════════════════════════

  Scenario: Doc ratio color is green when all docs uploaded
    When I check the doc ratio color for uploaded=3, required=3
    Then the doc ratio color should be "text-success"

  Scenario: Doc ratio color is orange when some docs uploaded
    When I check the doc ratio color for uploaded=1, required=3
    Then the doc ratio color should be "text-warning"

  Scenario: Doc ratio color is red when no docs uploaded
    When I check the doc ratio color for uploaded=0, required=3
    Then the doc ratio color should be "text-danger"

  # ══════════════════════════════════════════════════════════════════════════
  # KycDashboardHelper — show mark verified
  # ══════════════════════════════════════════════════════════════════════════

  Scenario: Mark verified is shown for successful unverified KYC
    Given a KYC that is not verified with a "ready" report
    When I check whether to show mark verified
    Then mark verified should be shown

  Scenario: Mark verified is hidden for already-verified KYC
    Given a KYC that is verified with a "ready" report
    When I check whether to show mark verified
    Then mark verified should not be shown

  Scenario: Mark verified is hidden when report status is blocked
    Given a KYC that is not verified with a "blocked" report
    When I check whether to show mark verified
    Then mark verified should not be shown

  # ══════════════════════════════════════════════════════════════════════════
  # KycDashboardHelper — run output items
  # ══════════════════════════════════════════════════════════════════════════

  Scenario: Run output items converts field and document issues into display rows
    Given a KYC report with field issues and document issues
    When I compute the run output items
    Then the output should have field-sourced and document-sourced rows
    And the output counts should tally all items by status

  # ══════════════════════════════════════════════════════════════════════════
  # Non-KYC agent guard
  # ══════════════════════════════════════════════════════════════════════════

  Scenario: Dashboard data is empty for a non-KYC agent type
    Given there is a portfolio scoring agent instead of KYC
    When I load the KYC dashboard data for that agent
    Then the dashboard data should be empty with zero stats
