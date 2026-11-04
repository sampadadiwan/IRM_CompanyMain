@rack_test @report_builder
Feature: Report Builder report check — what will look wrong, before export

  Worked examples: openspec/changes/report-builder-live-builder/business-rules.md
  The builder's header shows "All good" or the number of warnings; its panel
  lists each problem with a Fix button that opens the tab that fixes it.

  Background:
    Given the Acme report builder data
    And I am signed in as Meera

  # H14 — Happy path: LPs (Growth Fund II only) with Committed (Sum) has nothing to warn about
  Scenario: All good
    Given the Acme report "LPs"
    And I add the columns "capital_commitments.committed_amount" from the builder
    When I open the builder's report check
    Then the report check says "All good"
    And the report check has no notes

  # H15 — Happy path: commitments of every fund (INR and USD) summed together are flagged
  Scenario: Mixed currencies
    Given an "Investor" report with columns "investor_name"
    And the report has related data "capital_commitments"
    And I add the columns "capital_commitments.committed_amount" from the builder
    When I open the builder's report check
    Then the report check says "1 warning"
    And the report check warns "Committed adds amounts in INR and USD — pick a fund or split by fund" with a Fix for "filters"

  # E14 — Edge case: a column of related data that no longer exists will be blank
  Scenario: Blank column
    Given the Acme report "LPs"
    And the report has broken related data "capital_commitments.no_such"
    And the report also shows "capital_commitments.no_such.name" labelled "no_such name"
    When I open the builder's report check
    Then the report check warns "no_such name will be blank — its related data no longer exists" with a Fix for "related"

  # E15 — Edge case: a formula using a removed column names the formula and the column
  Scenario: Broken formula reference
    Given the Acme report "LPs"
    And I add the columns "capital_commitments.committed_amount, capital_commitments.collected_amount" from the builder
    And I add the formula "[capital_commitments.collected_amount] / [capital_commitments.committed_amount]" as "Collected %" from the builder
    And I remove the column "capital_commitments.collected_amount" from the builder
    When I open the builder's report check
    Then the report check warns "Formula Collected % uses capital_commitments.collected_amount, which isn't in the report" with a Fix for "formulas"

  # E16 — Edge case: the report is empty and Category = Partner alone matches nothing
  Scenario: Filter matches nothing
    Given the Acme report "LPs"
    And the report's own rows are filtered to "category" = "Partner"
    When I open the builder's report check
    Then the report check warns "No rows match Category is Partner" with a Fix for "filters"

  # E17 — Edge case: a pivot on 22 unit types (A, B and 20 more) is over the 20-column limit
  Scenario: Large pivot
    Given the Acme report "LPs"
    And Growth Fund II has 20 more unit types
    And the report pivots "capital_commitments" by "unit_type" on "committed_amount"
    When I open the builder's report check
    Then the report check warns "Capital commitments pivot creates 22 columns — consider fewer categories" with a Fix for "related"

  # E18 — Edge case: 4 rows over a threshold of 3, and a related column saved before default totals
  Scenario: Large export and default totals
    Given the Acme report "LPs"
    And the export threshold is 3 rows
    And the report also shows "capital_commitments.committed_amount" labelled "Committed"
    When I open the builder's report check
    Then the report check says "All good"
    And the report check notes "Export will have 4 rows — it may take a while"
    And the report check notes "Committed uses the default total Sum"
