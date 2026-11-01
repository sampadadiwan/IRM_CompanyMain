@rack_test @report_builder
Feature: Report Builder "Only rows that have …"

  Worked examples: openspec/changes/report-builder-trust/design.md#worked-examples
  Each many-per-row related data can restrict the report to rows with at
  least one matching related row, respecting that related data's filters.
  The row count always matches the rows.

  Background:
    Given the Acme report builder data

  # H13 — Happy path: turning the setting on leaves out Nova LP (no commitments); rows and count agree
  Scenario: Investors without commitments are left out
    Given the Acme report "LPs"
    And the report also shows "capital_commitments.committed_amount"
    And I am signed in as Meera
    When I turn on only-with-rows for "capital_commitments" over HTTP
    Then only-with-rows is on for "capital_commitments"
    When I run the report
    Then the report has 3 rows and counts 3
    And no row has "investor_name" = "Nova LP"

  # H14 — Happy path: with the related filter Status = Overdue, only investors with an overdue remittance remain
  Scenario: The setting respects the related data's filters
    Given an "Investor" report with columns "investor_name"
    And the report has related data "capital_remittances"
    And the related data "capital_remittances" is filtered to "status" = "Overdue"
    And the report keeps only rows that have "capital_remittances"
    When I run the report
    Then the only row has "investor_name" = "Aditi Rao"

  # E11 — Edge case: off by default — every investor is listed, with a zero total where there are no commitments
  Scenario: Off by default
    Given the Acme report "LPs"
    And the report also shows "capital_commitments.committed_amount"
    When I run the report
    Then the report has 4 rows and counts 4
    And the row where "investor_name" is "Nova LP" shows "0" in "capital_commitments.committed_amount"

  # X8 — Error case: a user of another entity can't change the setting
  Scenario: Another entity's user is refused
    Given the Acme report "LPs"
    And I am signed in as Omar from another entity
    When I turn on only-with-rows for "capital_commitments" over HTTP
    Then the change is refused
    And only-with-rows is off for "capital_commitments"

  # X9 — Error case: one-per-row related data (a commitment's fund) can't use the setting
  Scenario: Refused on one-per-row related data
    Given a "CapitalCommitment" report with columns "folio_id,fund.name"
    And the report has related data "fund"
    And I am signed in as Meera
    When I turn on only-with-rows for "fund" over HTTP
    Then the request is refused with status 422
    And only-with-rows is off for "fund"
