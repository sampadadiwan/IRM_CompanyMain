@rack_test @report_builder
Feature: Report Builder Duplicate — the same report, for another fund

  Worked examples: openspec/changes/report-builder-starting-points/business-rules.md
  Duplicate makes "Copy of <name>" with the same columns, totals, order,
  related data, filters, formulas, sort and Excel grouping, opened in the
  builder. The email schedule and a pending Undo are not copied.

  Background:
    Given the Acme report builder data
    And I am signed in as Meera
    And the Acme report "LPs"
    And I add the columns "capital_commitments.committed_amount" from the builder
    And I add the formula "[capital_commitments.committed_amount] / 100" as "Committed (hundredths)" from the builder

  # H9 — Happy path: the copy opens in the builder with the same columns, labels, totals, order, related data, filters, formulas, sort and grouping
  Scenario: Duplicate copies the set-up
    Given the report is saved sorted by "capital_commitments.committed_amount" "desc"
    And the report groups rows in Excel by "category"
    When I duplicate the report
    Then the builder opens for the copy "Copy of LPs" saying "Copied from LPs"
    And the copy has the same set-up as the original

  # H10 — Happy path: changing the copy's fund leaves the original on Growth Fund II
  Scenario: The original is unchanged
    When I duplicate the report
    And I limit the copy's "capital_commitments" to "Global Fund"
    Then the copy's "capital_commitments" are limited to "Global Fund"
    And the original's "capital_commitments" are limited to "Growth Fund II"

  # E4 — Edge case: "Copy of LPs" is taken, so the copy is "Copy of LPs (2)"
  Scenario: Copy name is unique
    Given Acme already has a report named "Copy of LPs"
    When I duplicate the report
    Then the copy is named "Copy of LPs (2)"

  # E5 — Edge case: a weekly schedule and a pending Undo stay with the original
  Scenario: What isn't copied
    Given the report is emailed weekly to "cfo@acme.test, ops@acme.test"
    And I remove the column "category" from the builder
    When I duplicate the report
    Then the copy has no schedule and no Undo
    And the original still has its schedule and its Undo

  # X4 — Error case: a user of another company can't duplicate the report
  Scenario: Duplicate across companies
    Given I am signed in as Omar from another entity
    When I duplicate the report
    Then the change is refused
    And no copy is created
