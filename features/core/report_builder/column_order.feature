@rack_test @report_builder
Feature: Report Builder column order — formulas and pivots keep their place

  Worked examples: openspec/changes/report-builder-trust/design.md#worked-examples
  A formula's position and a pivot's block of columns are rows in the report's
  column order, so they can be dragged like any other column. Reports saved
  before this change keep pivots, then formulas, after all other columns.

  Background:
    Given the Acme report builder data
    And I am signed in as Meera

  # H10 — Happy path: a new formula goes last, and moving it after Called puts it there everywhere
  Scenario: A formula stays where it is moved
    Given the Acme report "LPs"
    And the report also shows "capital_commitments.call_amount"
    And the report also shows "capital_commitments.committed_amount"
    When I add the formula "Called %" = "IF([capital_commitments.committed_amount] > 0, [capital_commitments.call_amount] / [capital_commitments.committed_amount] * 100, 0)" over HTTP
    Then the report has a position row for formula "Called %"
    And the report columns are "Investor name, Category, Call amount, Committed amount, Called %"
    When I move column "Called %" to position 4
    Then the report columns are "Investor name, Category, Call amount, Called %, Committed amount"

  # H11 — Happy path: a pivot's columns move together as one block
  Scenario: A pivot block moves as one
    Given an "Investor" report with columns "investor_name,category"
    And the report has related data "capital_commitments"
    When I apply a pivot on "capital_commitments" by "unit_type" on "committed_amount" with "sum" over HTTP
    Then the report has a pivot position row for "capital_commitments"
    When I move column "Capital commitments (pivot)" to position 2
    Then the report columns are "Investor name, Capital commitments · A (sum), Capital commitments · B (sum), Category"

  # E7 — Edge case: a report saved before positions existed keeps pivots, then formulas, after the other columns
  Scenario: Legacy order is unchanged
    Given an "Investor" report with columns "investor_name,category"
    And the report has related data "capital_commitments"
    And the report pivots "capital_commitments" by "unit_type" on "committed_amount" with "sum"
    And the report has formula "Twice" = "2 * 2"
    Then the report columns are "Investor name, Category, Capital commitments · A (sum), Capital commitments · B (sum), Twice"

  # E8 — Edge case: removing a formula removes its position; no empty column is left
  Scenario: Removing a formula removes its position
    Given the Acme report "LPs"
    And the report also shows "capital_commitments.call_amount"
    When I add the formula "Double" = "[capital_commitments.call_amount] * 2" over HTTP
    And I remove the formula "Double" over HTTP
    Then the report has no position row for formula "Double"
    And the report columns are "Investor name, Category, Call amount"

  # E9 — Edge case: clearing a pivot removes its position
  Scenario: Clearing a pivot removes its position
    Given an "Investor" report with columns "investor_name"
    And the report has related data "capital_commitments"
    When I apply a pivot on "capital_commitments" by "unit_type" on "committed_amount" with "sum" over HTTP
    And I clear the pivot on "capital_commitments" over HTTP
    Then the report has no pivot position row for "capital_commitments"
    And the report columns are "Investor name"

  # E10 — Edge case: removing the related data removes its pivot position and columns
  Scenario: Removing related data removes its pivot position
    Given an "Investor" report with columns "investor_name"
    And the report has related data "capital_commitments"
    When I apply a pivot on "capital_commitments" by "unit_type" on "committed_amount" with "sum" over HTTP
    And I remove the related data "capital_commitments" over HTTP
    Then the report has no pivot position row for "capital_commitments"
    And the report columns are "Investor name"
