@rack_test @report_builder
Feature: Report Builder undo — put back a removal

  Worked examples: openspec/changes/report-builder-live-builder/business-rules.md
  Removing a column, or related data with its columns, answers with a message
  that has Undo. Undo puts the set-up back within 10 minutes, as long as
  nothing has changed since.

  Background:
    Given the Acme report builder data
    And I am signed in as Meera
    And the Acme report "LPs"
    And I add the columns "capital_commitments.committed_amount" from the builder

  # H11 — Happy path: Committed (Sum) removed from position 3 comes back at position 3 with its label and total
  Scenario: Undo a column
    When I remove the column "capital_commitments.committed_amount" from the builder
    Then the builder message offers Undo
    And the report columns are "Investor name, Category"
    When I undo from the builder
    Then the builder message says "Restored Committed"
    And the column "capital_commitments.committed_amount" is at position 3
    And the column "capital_commitments.committed_amount" is labelled "Committed"
    And the stored total for "capital_commitments.committed_amount" is "sum"

  # H12 — Happy path: removing capital commitments and undoing restores the join, its filter and its three columns with totals
  Scenario: Undo related data
    Given I add the columns "capital_commitments.call_amount, capital_commitments.collected_amount" from the builder
    And the related data "capital_commitments" is filtered to "unit_type" = "A"
    When I remove the related data "capital_commitments" from the builder
    Then the builder message says "Removed Capital commitments and 3 columns"
    And the report has no related data "capital_commitments"
    When I undo from the builder
    Then the report has the related data "capital_commitments" filtered to "unit_type" = "A"
    And the report has the columns "capital_commitments.committed_amount, capital_commitments.call_amount, capital_commitments.collected_amount"
    And the stored total for "capital_commitments.call_amount" is "sum"

  # H13 — Happy path: the Remove button of capital commitments explains, as Immediate Actions, that Committed and Called go with it
  Scenario: The confirmation names the columns
    Given I add the columns "capital_commitments.call_amount" from the builder
    When I open the builder
    Then the Remove button of "capital_commitments" names the columns "Committed, Called"

  # E12 — Edge case: Undo 11 minutes after the removal is too late
  Scenario: Too late to undo
    When I remove the column "capital_commitments.committed_amount" from the builder
    And 11 minutes pass
    And I undo from the builder
    Then the builder answer is refused with status 422
    And the builder message says "Too late to undo — removals can be undone for 10 minutes"
    And the report columns are "Investor name, Category"

  # E13 — Edge case: after another change (a new sort), Undo is refused
  Scenario: Undo after another change
    When I remove the column "capital_commitments.committed_amount" from the builder
    And I sort by "category" "asc" from the builder
    And I undo from the builder
    Then the builder answer is refused with status 422
    And the builder message says "Too late to undo — the report has changed since"
    And the report columns are "Investor name, Category"

  # X1 — Error case: a user of another entity can't undo the removal; nothing is restored
  Scenario: Undo by another entity
    When I remove the column "capital_commitments.committed_amount" from the builder
    And I am signed in as Omar from another entity
    And I undo from the builder
    Then the change is refused
    And the report columns are "Investor name, Category"
