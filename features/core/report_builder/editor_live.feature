@javascript @report_builder
Feature: Report Builder in the browser — live preview, header menus, filters and formulas

  Worked examples: openspec/changes/report-builder-live-builder/business-rules.md
  The preview loads with the page and follows every change; filters check
  themselves and save after a short pause; the formula editor inserts columns.

  Background:
    Given the Acme report builder data

  # H1 — Happy path: the preview shows the four LPs and the Total row as soon as the builder opens
  Scenario: Preview on open
    Given the Acme report "LPs"
    And the report also shows "capital_commitments.committed_amount"
    And Meera is on the builder for the report
    Then the preview shows "Aditi Rao, Kiran Mehta, Zeta Holdings, Nova LP" without a click
    And the preview shows a "Total" row

  # H5 — Happy path: renaming Committed from its header menu updates the preview header
  Scenario: Rename from the header
    Given the Acme report "LPs"
    And the report also shows "capital_commitments.committed_amount" labelled "Committed"
    And Meera is on the builder for the report
    When I rename the "Committed" column to "Total committed" from its header
    Then the preview header reads "Total committed"

  # H7 — Happy path: Commitment date on or after 01/02/2026 saves by itself and leaves F-2, F-3, F-4
  Scenario: Date filter
    Given a "CapitalCommitment" report with columns "folio_id,commitment_date"
    And Meera is on the builder for the report
    When I add a filter on "Commitment date"
    And I choose the operator "is on or after"
    And I type the date "01/02/2026" in the filter
    Then the report's own filters are '{"commitment_date_gteq": "2026-02-01"}'
    And the preview rows are "F-2, F-3, F-4"

  # H9 — Happy path: clicking Called in the formula editor inserts its key
  Scenario: Insert a column into a formula
    Given the Acme report "LPs"
    And the report also shows "capital_commitments.call_amount" labelled "Called"
    And Meera is on the builder for the report
    When I open the formula editor
    And I click the column "Called" in the formula editor
    Then the formula expression contains "[capital_commitments.call_amount]"

  # E9 — Edge case: a Category filter with no value says so and nothing is saved
  Scenario: Missing value
    Given the Acme report "LPs"
    And Meera is on the builder for the report
    When I add a filter on "Category"
    Then the filter row says "needs a value"
    And the report's own filters stay empty

  # E10 — Edge case: a date that can't be read says how to write one and nothing is saved
  Scenario: Unreadable date
    Given a "CapitalCommitment" report with columns "folio_id,commitment_date"
    And Meera is on the builder for the report
    When I add a filter on "Commitment date"
    And I type the date "31/31/2026" in the filter
    Then the filter row says "Enter a date like 19/08/2026"
    And the report's own filters stay empty
