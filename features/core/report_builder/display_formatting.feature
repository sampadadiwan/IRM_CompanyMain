@rack_test @report_builder
Feature: Report Builder values look the same in the preview and on the report page

  Worked examples: openspec/changes/report-builder-trust/design.md#worked-examples
  Values are formatted by column type: amounts with separators (Indian grouping
  for INR) and two decimals, right-aligned; dates in the user's format; yes/no
  as Yes or No. The preview states how many rows it shows.

  Background:
    Given the Acme report builder data
    And I am signed in as Meera

  # H15 — Happy path: an amount, a date and a yes/no read identically in the preview and on the report page
  Scenario: The same text in the preview and on the report page
    Given the Acme report "LPs"
    And the report also shows "capital_commitments.committed_amount"
    And the report also shows "capital_commitments.commitment_date"
    And the report also shows "capital_commitments.onboarding_completed"
    Then the preview and the report page show "5,00,00,000.00" under "Committed amount" in the row with "Aditi Rao"
    And the preview and the report page show "15/01/2026" under "Commitment date" in the row with "Aditi Rao"
    And the preview and the report page show "Yes" under "Onboarding completed" in the row with "Aditi Rao"
    And the preview and the report page show "No" under "Onboarding completed" in the row with "Kiran Mehta"
    And the "Committed amount" column is right-aligned

  # H24 — Happy path: a 25-row report's preview says "20 of 25 rows" and labels its totals as a sample
  Scenario: The preview states how many rows it shows
    Given 21 more investors exist
    And an "Investor" report with columns "investor_name,capital_commitments.committed_amount"
    And the report has related data "capital_commitments"
    When I open the preview
    Then the Report Builder page says "20 of 25 rows"
    And the totals row is labelled "Total (these 20 rows)"

  # E15 — Edge case: amounts whose names don't contain "amount" are formatted too
  Scenario: Amounts not named "amount" are formatted
    Given the Acme distribution payment exists
    And a "CapitalDistributionPayment" report with columns "investor_name,gross_payable,net_payable,units_quantity"
    When I open the Report Builder page
    Then the table shows "13,00,000.00" under "Gross payable" in the row with "Aditi Rao"
    And the table shows "12,34,567.00" under "Net payable" in the row with "Aditi Rao"
    And the table shows "100.00" under "Units quantity" in the row with "Aditi Rao"
    And the "Net payable" column is right-aligned

  # E16 — Edge case: the display currency labels money columns only, not quantities
  Scenario: The currency label goes on amounts only
    Given the Acme fund units exist
    And a "FundUnit" report with columns "unit_type,amount,quantity"
    And the report's display currency is "INR"
    When I open the Report Builder page
    Then the table shows "₹ 1,000.00" under "Amount" in the row with "1,000.00"
    And the table shows "500.00" under "Quantity" in the row with "₹ 500.00"

  # E20 — Edge case: a report with fewer rows than the preview shows says "All 4 rows" and "Total"
  Scenario: A small report's preview shows every row
    Given the Acme report "LPs"
    And the report also shows "capital_commitments.committed_amount"
    When I open the preview
    Then the Report Builder page says "All 4 rows"
    And the totals row is labelled "Total"

  # X6 — Error case: a value of an unexpected kind in a column of unknown type shows as text; nothing breaks
  Scenario: Unknown types fall back to text
    Given the Acme report "LPs"
    Then a column of unknown type holding a hash shows as text
