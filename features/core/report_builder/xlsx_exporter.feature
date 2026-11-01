@rack_test
Feature: ReportBuilderXlsxExporter — Data sheet with a totals row

  Scenarios build a report + hand-supplied rows/columns, run the exporter
  directly, and read the generated .xlsx bytes back with Roo. No QueryEngine
  or aggregator involved — these test the exporter's own formatting/totaling
  logic in isolation.

  Background:
    Given a report builder entity and user

  Scenario: The totals row sums a regular "sum" aggregate column
    Given an xlsx export report on "Investor" with columns:
      | key                                         | label            | aggregate |
      | investor_name                               | Investor         |           |
      | capital_commitments.folio_committed_amount   | Committed Amount | sum       |
    And export rows:
      | investor_name | capital_commitments.folio_committed_amount |
      | Alpha         | 100                                         |
      | Beta          | 250                                         |
    When I generate the report xlsx export
    Then the export should not include a "Totals" sheet
    And the Data sheet totals row shows "350" for the column labeled "Committed Amount"

  # A pivot column's aggregate type lives on the join's own pivot config
  # (join.pivot.aggregate), not in config.aggregates — the totals row reads it
  # from there, so a pivot is totalled even when it is the only summable column.
  Scenario: The totals row sums a pivot column even with no regular aggregate configured
    Given an xlsx export report on "Investor" with columns:
      | key           | label    | aggregate |
      | investor_name | Investor |           |
    And the xlsx export report has a pivot join "capital_commitments" on "folio_committed_amount" grouped by "fund_close" with "sum" aggregate
    And the xlsx export has a dynamic column "capital_commitments.folio_committed_amount__pivot__First Close" labeled "First Close (sum)"
    And export rows:
      | investor_name | capital_commitments.folio_committed_amount__pivot__First Close |
      | Alpha         | 400                                                              |
      | Beta          | 600                                                              |
    When I generate the report xlsx export
    Then the Data sheet totals row shows "1000" for the column labeled "First Close"

  # A column that isn't one of the report's formulas and has no known type
  # (here a dynamic column with no expression) gets no total rather than a guess.
  Scenario: The totals row leaves an unknown column without a total
    Given an xlsx export report on "Investor" with columns:
      | key                                         | label            | aggregate |
      | investor_name                               | Investor         |           |
      | capital_commitments.folio_committed_amount   | Committed Amount | sum       |
    And the xlsx export has a dynamic column "formula_1" labeled "Growth %"
    And export rows:
      | investor_name | capital_commitments.folio_committed_amount | formula_1 |
      | Alpha         | 100                                         | 12        |
      | Beta          | 250                                         | 8         |
    When I generate the report xlsx export
    Then the Data sheet totals row shows "350" for the column labeled "Committed Amount"
    And the Data sheet totals row is blank for the column labeled "Growth %"

  # A configured currency only changes the cell's Excel number-format style
  # (e.g. `"$"#,##0.00`) — the underlying value written to the Data sheet must
  # stay a real number so sorting, formulas and SUM keep working.
  Scenario: A configured currency does not change the underlying exported value
    Given an xlsx export report on "Investor" with columns:
      | key                                         | label            | aggregate |
      | capital_commitments.folio_committed_amount   | Committed Amount |           |
    And the xlsx export report's currency is set to "USD"
    And export rows:
      | capital_commitments.folio_committed_amount |
      | 1234.5                                      |
    When I generate the report xlsx export
    Then the Data sheet value in row 1 for the column labeled "Committed Amount" should equal "1234.5"

  # ── report-builder-trust ────────────────────────────────────────────────
  # Worked examples: openspec/changes/report-builder-trust/design.md#worked-examples

  # H16 — Happy path: amounts are number cells with a number format, dates are date cells, yes/no reads Yes
  @report_builder
  Scenario: Excel cells keep their types
    Given the Acme report builder data
    And the Acme report "LPs"
    And the report also shows "capital_commitments.committed_amount"
    And the report also shows "capital_commitments.commitment_date"
    And the report also shows "capital_commitments.onboarding_completed"
    When I export the report to Excel
    Then the export has the number "50000000" with format "#,##0.00" under "Committed amount" in the row with "Aditi Rao"
    And the export has a date cell "2026-01-15" under "Commitment date" in the row with "Aditi Rao"
    And the export shows "Yes" under "Onboarding completed" in the row with "Aditi Rao"

  # H19 — Happy path: the totals are the Data sheet's last, bold row; there is no Totals sheet
  @report_builder
  Scenario: Excel totals are the last row
    Given the Acme report builder data
    And the Acme report "LPs"
    And the report also shows "capital_commitments.committed_amount"
    When I export the report to Excel
    Then the export's last row is a bold totals row with "85000000" under "Committed amount"
    And the export should not include a "Totals" sheet
