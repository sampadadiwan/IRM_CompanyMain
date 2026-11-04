@rack_test @report_builder
Feature: Report Builder pivot preview — how many columns before Apply

  Worked examples: openspec/changes/report-builder-live-builder/business-rules.md

  Background:
    Given the Acme report builder data
    And I am signed in as Meera
    And an "Investor" report with columns "investor_name"
    And the report has related data "capital_commitments"

  # H16 — Happy path: Unit Type × Committed creates one column per unit type (A, B)
  Scenario: The pivot preview counts the columns
    When I preview a pivot on "capital_commitments" by "unit_type" on "committed_amount"
    Then the pivot preview says 2 columns: "A, B"

  # X2 — Error case: a field that isn't on the related data is refused with a message; nothing is applied
  Scenario: An unknown field is refused
    When I preview a pivot on "capital_commitments" by "unit_type" on "no_such"
    Then the pivot preview is refused with "no_such isn't a field of capital commitments"
