@javascript @report_builder
Feature: Report Builder — truthful save messages

  Worked examples: openspec/changes/report-builder-trust/design.md#worked-examples
  A setting shows a green message only once the server confirms it; otherwise a
  red message gives the reason and the control goes back to its saved value.
  (Trust H23, E26 — Apply Template asking first — were removed with the builder's
  Templates button by the starting-points change: templates now always create
  a new report.)

  Background:
    Given the Acme report builder data
    And the Acme report "LPs"
    And the report also shows "capital_commitments.committed_amount"
    And the report stores the total "sum" for "capital_commitments.committed_amount"
    And the report also shows "capital_commitments.call_amount"
    And the report also shows "capital_commitments.collected_amount"
    And Meera is on the builder for the report

  # H22 — Happy path: a saved change shows a green message
  Scenario: A saved change says so
    When I choose "Investor name" as the default sort
    Then I see a green message "Sort saved"
    And the saved sort is still "investor_name" "asc"

  # E25 — Edge case: when the server can't be reached, a red message says so and the control goes back
  Scenario: A change that can't reach the server says it wasn't saved
    When the network drops the next save
    And I choose "Investor name" as the default sort
    Then I see a red message containing "Sort wasn't saved — the server couldn't be reached"
    And I see no green message
    And the default sort shows "— none —"

  # X3 — Error case: a change the server refuses shows the reason, no green message, and the control reverts
  Scenario: A refused change says why and reverts
    When I pick a total the server refuses for "capital_commitments.committed_amount"
    Then I see a red message containing "Total wasn't saved — Unknown total 'median'"
    And I see no green message
    And the total for "capital_commitments.committed_amount" shows "sum"
