@rack_test @report_builder
Feature: Report Builder formula editor — results while you type

  Worked examples: openspec/changes/report-builder-live-builder/business-rules.md
  The formula editor checks a formula as it is typed and shows its result on
  the first rows, formatted as the preview shows them.

  Background:
    Given the Acme report builder data
    And I am signed in as Meera
    And the Acme report "LPs"
    And I add the columns "capital_commitments.call_amount, capital_commitments.committed_amount" from the builder

  # H10 — Happy path: Called % on the first rows (2 Cr / 5 Cr × 100 = 40.00; Nova LP has nothing committed, so blank)
  Scenario: Sample results for a valid formula
    When I check the formula "ROUND([capital_commitments.call_amount] / [capital_commitments.committed_amount] * 100, 2)"
    Then the formula works with the samples "Aditi Rao=40.00; Kiran Mehta=40.00; Zeta Holdings=40.00; Nova LP="

  # E11 — Edge case: an unfinished formula is refused with its error and no results
  Scenario: An invalid formula
    When I check the formula "[capital_commitments.call_amount] /"
    Then the formula is refused
