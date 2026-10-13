@rack_test
Feature: ReportBuilderXlsxExporter — Data/Totals sheet generation

  Scenarios build a report + hand-supplied rows/columns, run the exporter
  directly, and read the generated .xlsx bytes back with Roo. No QueryEngine
  or aggregator involved — these test the exporter's own formatting/totaling
  logic in isolation.

  Background:
    Given a report builder entity and user

  Scenario: Totals sheet sums a regular "sum" aggregate column
    Given an xlsx export report on "Investor" with columns:
      | key                                         | label            | aggregate |
      | investor_name                               | Investor         |           |
      | capital_commitments.folio_committed_amount   | Committed Amount | sum       |
    And export rows:
      | investor_name | capital_commitments.folio_committed_amount |
      | Alpha         | 100                                         |
      | Beta          | 250                                         |
    When I generate the report xlsx export
    Then the export should include a "Totals" sheet
    And the "Totals" sheet total for the column labeled "Committed Amount" should equal "350"

  # A pivot column's aggregate type lives on the join's own pivot config
  # (join.pivot.aggregate), not in config.aggregates — before this fix,
  # add_totals_sheet only ever looked in config.aggregates, so a pivot column
  # never got a total, and any_numeric_aggregates? never even created the
  # Totals sheet when a pivot column was the only summable thing in the report.
  Scenario: Totals sheet sums a pivot column even with no regular aggregate configured
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
    Then the export should include a "Totals" sheet
    And the "Totals" sheet total for the column labeled "First Close" should equal "1000"

  # Formula results aren't necessarily sum-able (a formula could be a ratio or
  # a percentage), so — unlike pivot columns — they're deliberately left out
  # of the Totals sheet rather than guessed at.
  Scenario: Totals sheet leaves a formula column without a total
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
    Then the "Totals" sheet total for the column labeled "Committed Amount" should equal "350"
    And the "Totals" sheet should have no total for the column labeled "Growth %"

  # A configured currency only changes the cell's Excel number-format style
  # (e.g. `"$"#,##0.00`) — the underlying value written to the Data sheet must
  # stay a real number so sorting/formulas/the Totals sheet SUM keep working.
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
