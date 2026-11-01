@rack_test @report_builder
Feature: Report Builder totals row

  Worked examples: openspec/changes/report-builder-trust/design.md#worked-examples
  Sum and Count columns are totalled; Average, Latest, Minimum, Maximum and List
  are left blank; formulas are recalculated from the totals. On screen the row
  says whether it covers every row or just this page.

  Background:
    Given the Acme report builder data
    And I am signed in as Meera
    And the Acme report "LPs"

  # H17 — Happy path: Committed is totalled (5,00,00,000 + 2,50,00,000 + 1,00,00,000 + 0 = 8,50,00,000)
  Scenario: A summed column is totalled
    Given the report also shows "capital_commitments.committed_amount"
    When I open the Report Builder page
    Then the totals row is labelled "Total"
    And the totals row shows "8,50,00,000.00" under "Committed amount"

  # H18 — Happy path: Called % in the totals row is recalculated (3,40,00,000 ÷ 8,50,00,000 × 100 = 40.00), not summed
  Scenario: A ratio formula is recalculated from the totals
    Given the report also shows "capital_commitments.call_amount"
    And the report also shows "capital_commitments.committed_amount"
    And the report has formula "Called %" = "IF([capital_commitments.committed_amount] > 0, [capital_commitments.call_amount] / [capital_commitments.committed_amount] * 100, 0)"
    When I open the Report Builder page
    Then the totals row shows "3,40,00,000.00" under "Call amount"
    And the totals row shows "40.00" under "Called %"

  # E17 — Edge case: Average, Minimum, Maximum (Latest date), Latest and List columns have no total
  Scenario: Non-summing totals are left blank
    Given the report also shows "capital_commitments.committed_amount"
    And the report also shows "capital_commitments.call_amount"
    And the report stores the total "avg" for "capital_commitments.call_amount"
    And the report also shows "capital_commitments.collected_amount"
    And the report stores the total "min" for "capital_commitments.collected_amount"
    And the report also shows "capital_commitments.commitment_date"
    And the report also shows "capital_commitments.unit_type"
    And the report also shows "capital_commitments.fund_close"
    And the report stores the total "list" for "capital_commitments.fund_close"
    When I open the Report Builder page
    Then the totals row shows "8,50,00,000.00" under "Committed amount"
    And the totals row is blank under "Call amount"
    And the totals row is blank under "Collected amount"
    And the totals row is blank under "Commitment date"
    And the totals row is blank under "Unit type"
    And the totals row is blank under "Fund close"

  # E18 — Edge case: on a paged report the row totals this page only and says so (Aditi + Kiran = 7,50,00,000)
  Scenario: A paged report totals the page shown
    Given the report also shows "capital_commitments.committed_amount"
    When I open the Report Builder page with "per_page=2"
    Then the totals row is labelled "Total (this page)"
    And the totals row shows "7,50,00,000.00" under "Committed amount"

  # E19 — Edge case: a report with nothing to total has no totals row
  Scenario: No totalable columns, no totals row
    When I open the Report Builder page
    Then there is no totals row

  # E30 — Edge case: a blank value counts as zero in a total
  Scenario: Blank values count as zero
    Given the report also shows "capital_commitments.committed_amount"
    Then the total of "capital_commitments.committed_amount" over the values "5, , 3" is "8"

  # E31 — Edge case: a difference formula is recalculated from the totals (3,40,00,000 − 2,80,00,000 = 60,00,000)
  Scenario: A difference formula is recalculated from the totals
    Given the report also shows "capital_commitments.call_amount"
    And the report also shows "capital_commitments.collected_amount"
    And the report has formula "Unpaid" = "[capital_commitments.call_amount] - [capital_commitments.collected_amount]"
    When I open the Report Builder page
    Then the totals row shows "60,00,000.00" under "Unpaid"
