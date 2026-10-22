# bulk-path-query-optimisation, phase 4 — a KPI workbook import reads each report's KPIs once.
# Worked examples: openspec/changes/bulk-path-query-optimisation/business-rules.md (H4, E2)

@bulk_query @rack_test
Feature: KPI workbook import reads each report's KPIs once
  Every cell used to query the report for an unapproved KPI and an approved one before saving. The
  report's KPIs are now read once per report for the whole import. Results must not change.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the KPI workbook file "kpi_extraction/MIS sample.xlsx" for a kpi report
    And the target KPIs are "Revenue, Number of Distributors, Net Current Assets, Orders MoMGrowth, Returns%"

  # H4 — Happy path: same KPIs staged, without two lookups per cell
  Scenario: H4 A workbook import stages the same KPIs without per-cell lookups
    Given I count queries by call site
    When the KpiWorkbookReader processes the file
    Then the extracted KPI data should be valid for the given workbook and targets with "17"
    # 85 cells: 85 INSERTs. Without the per-report maps, 340 (two lookups per cell and an entity load per save)
    And at most 85 queries came from "KpiWorkbookReader#save_kpi_entry"

  # E2 — Edge case: KPIs already in the report (here from a first import) are updated, never duplicated
  Scenario: E2 Re-importing the same workbook updates its KPIs instead of adding copies
    When the KpiWorkbookReader processes the file
    And I note the staged KPIs of the portfolio company
    And the KpiWorkbookReader processes the file
    Then the staged KPIs of the portfolio company should be the same rows
    And no staged KPI of the portfolio company should be duplicated
