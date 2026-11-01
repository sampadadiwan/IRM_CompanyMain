@rack_test
Feature: Report Builder guided wizard — HTTP-level smoke tests

  The wizard is a friendlier, step-by-step front door onto the exact same
  Report#template the advanced builder writes. These scenarios exercise it
  purely over HTTP (no browser), the same way api.feature covers the
  advanced builder's endpoints.

  Background:
    Given a report builder entity and user
    And that entity has an investor "Wizard Test Investor"
    And I am signed in as the report builder user

  Scenario: GET the wizard's first step lists root models to choose from
    When I visit the wizard start page
    Then the wizard page should be successful
    And the wizard page should mention "Investor"

  Scenario: Creating a report via the wizard redirects into the columns step
    When I create a report via the wizard with name "Wizard LP Summary" and root model "Investor"
    Then the wizard-created report should have root model "Investor"
    And I should be on the wizard "columns" step

  Scenario: Walking through every wizard step builds up a working report
    Given I create a report via the wizard with name "Wizard Full Walkthrough" and root model "Investor"
    When I add the column "investor_name" to the wizard report
    Then the wizard report should have column "investor_name"

    When I visit the wizard "joins" step for the report
    Then the wizard page should be successful
    When I add the join "capital_commitments" with model "CapitalCommitment" to the wizard report
    Then the wizard report template should include join "capital_commitments"

    When I visit the wizard "aggregates" step for the report
    Then the wizard page should be successful
    When I add the column "capital_commitments.folio_committed_amount" to the wizard report
    And I set the aggregate for "capital_commitments.folio_committed_amount" to "sum" via the wizard
    Then the wizard report template aggregate for "capital_commitments.folio_committed_amount" should be "sum"

    When I visit the wizard "filters" step for the report
    Then the wizard page should be successful
    When I add a wizard root filter on field "investor_name" operator "cont" value "Wizard"
    Then the wizard report template root filter "investor_name_cont" should be "Wizard"
    When I remove the wizard root filter "investor_name_cont"
    Then the wizard report template should not have root filter "investor_name_cont"

    When I visit the wizard "sort" step for the report
    Then the wizard page should be successful
    When I set the wizard sort to "investor_name" direction "desc"
    Then the wizard report template sort key should be "investor_name"

    When I visit the wizard "review" step for the report
    Then the wizard page should be successful
    And the wizard page should mention "Wizard Full Walkthrough"

  Scenario: Aggregates step redirects straight to filters when no joins were added
    Given I create a report via the wizard with name "No Joins Report" and root model "Investor"
    When I visit the wizard "aggregates" step for the report
    Then I should be on the wizard "filters" step

  Scenario: Renaming a column's label via the wizard overrides its display header
    Given I create a report via the wizard with name "Label Rename Report" and root model "Investor"
    And I add the column "investor_name" to the wizard report
    When I rename the wizard column "investor_name" to "Investor Full Name"
    Then the wizard column "investor_name" should have label "Investor Full Name"
    When I rename the wizard column "investor_name" to ""
    Then the wizard column "investor_name" should have label "Investor name"

  Scenario: Turning a join into a pivot on the Summarize step
    Given I create a report via the wizard with name "Pivot Report" and root model "Investor"
    And I add the join "capital_commitments" with model "CapitalCommitment" to the wizard report
    And I add the column "capital_commitments.folio_committed_amount" to the wizard report

    When I apply a wizard pivot on join "capital_commitments" grouping by "unit_type" valued by "folio_committed_amount" aggregate "sum"
    Then the wizard report template join "capital_commitments" should have a pivot config
    And the wizard report should not have column "capital_commitments.folio_committed_amount"

    When I clear the wizard pivot on join "capital_commitments"
    Then the wizard report template join "capital_commitments" should not have a pivot config

  # ── Restored wizard (2026-11-01): the original steps, plus four changes ────
  # openspec/changes/report-builder-live-builder/business-rules.md#wizard-restored

  # R1 — Happy path: every table on the first page has an example question
  Scenario: Every table has an example question
    When I visit the wizard start page
    Then every table on the wizard start page has an example question

  # R2 — Happy path: the wizard says "Guided setup" and "Open in builder", like the rest of the app
  Scenario: One name everywhere
    Given I create a report via the wizard with name "Naming Report" and root model "Investor"
    When I visit the wizard "columns" step for the report
    Then the wizard page should mention "Guided setup"
    And the wizard page should mention "Open in builder"
    And the wizard page should not mention "Guided Report Wizard"
    And the wizard page should not mention "Advanced Builder"

  # R3 — Edge case: a related column's total on Summarize is the one saved and used (was shown as Sum but not stored)
  Scenario: The Summarize total is the saved total
    Given I create a report via the wizard with name "Totals Report" and root model "Investor"
    And I add the join "capital_commitments" with model "CapitalCommitment" to the wizard report
    When I add the column "capital_commitments.committed_amount" to the wizard report
    Then the wizard Summarize total for "capital_commitments.committed_amount" shows "Sum"
    And the wizard report template aggregate for "capital_commitments.committed_amount" should be "sum"

  # R4 — Happy path: Review's "Open My Report" opens the report page, not the builder
  Scenario: Open My Report opens the report page
    Given I create a report via the wizard with name "Review Report" and root model "Investor"
    When I visit the wizard "review" step for the report
    Then "Open My Report" links to the report page
