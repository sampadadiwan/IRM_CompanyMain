@rack_test @report_builder
Feature: Report Builder columns — picker, bulk add, header menus and live updates

  Worked examples: openspec/changes/report-builder-live-builder/business-rules.md
  Columns are ticked in a grouped picker and added together; each preview
  column has a menu to rename, total, move or remove it; every change answers
  with the settings panel, the preview and the health badge.

  Background:
    Given the Acme report builder data
    And I am signed in as Meera
    And the Acme report "LPs"

  # H2 — Happy path: a change from the builder re-renders the settings and the preview together (Count shows 1 for Aditi)
  Scenario: A change updates the settings panel and the preview
    Given I add the columns "capital_commitments.committed_amount" from the builder
    When I set the total for "capital_commitments.committed_amount" to "count" from the builder
    Then the builder answer replaces the settings, the preview and the health
    And the settings show the total "count" for "capital_commitments.committed_amount"
    And the streamed preview shows "1" under "Committed" in the row with "Aditi Rao"

  # H3 — Happy path: the picker is grouped by source and kind, without internal id or cents fields
  Scenario: The column picker is grouped
    When I open the builder
    Then the column picker has the sources "About the investor, From capital commitments"
    And the column picker groups columns as "Amounts, Names & text"
    And no column in the picker is an internal id or cents field

  # H4 — Happy path: three columns added in one request, with their default totals
  Scenario: Several columns are added at once
    When I add the columns "capital_commitments.committed_amount, capital_commitments.call_amount, capital_commitments.commitment_date" from the builder
    Then the builder message says "Added 3 columns"
    And the report has the columns "capital_commitments.committed_amount, capital_commitments.call_amount, capital_commitments.commitment_date"
    And the stored total for "capital_commitments.committed_amount" is "sum"
    And the stored total for "capital_commitments.call_amount" is "sum"
    And the stored total for "capital_commitments.commitment_date" is "max"

  # H6 — Happy path: moving the first column right swaps it with its neighbour
  Scenario: Move a column right
    When I move "investor_name" "right" from the builder
    Then the report columns are "Category, Investor name"

  # E1 — Edge case: Add selected stays disabled until a column is ticked
  Scenario: Nothing ticked
    When I open the builder
    Then Add selected is disabled

  # E2 — Edge case: a column already in the report is skipped and an unknown one refused; the rest are added
  Scenario: Already added and refused columns
    When I add the columns "category, capital_commitments.committed_amount, capital_commitments.no_such" from the builder
    Then the builder message says "'capital_commitments.no_such' isn't available in this report"
    And the report has the columns "capital_commitments.committed_amount"
    And the report has "category" only once

  # E3 — Edge case: two columns with the same label are told apart by their field
  Scenario: Same label told apart
    Then the "AggregatePortfolioInvestment" column picker shows "Net bought amount" with the hints "bought_amount, net_bought_amount"

  # E4 — Edge case: a blank rename puts the original label back
  Scenario: Blank rename restores the label
    Given I add the columns "capital_commitments.committed_amount" from the builder
    When I rename "capital_commitments.committed_amount" to "Total committed" from the builder
    Then the column "capital_commitments.committed_amount" is labelled "Total committed"
    When I rename "capital_commitments.committed_amount" to "" from the builder
    Then the column "capital_commitments.committed_amount" is labelled "Committed"

  # E5 — Edge case: one-per-row related data (a commitment's fund) has no Total in its menu
  Scenario: No total on one-per-row columns
    Given a "CapitalCommitment" report with columns "folio_id,fund.name"
    And the report has related data "fund"
    When I open the builder preview
    Then the "Name" header menu has no Total

  # E6 — Edge case: the first column can't move left and the last can't move right
  Scenario: Columns can't move past the ends
    When I open the builder preview
    Then the "Investor name" header menu can't move "left"
    And the "Category" header menu can't move "right"

  # X3 — Error case: a move in any direction but left or right is refused and nothing changes
  Scenario: An invalid move is refused
    When I move "investor_name" "up" from the builder
    Then the builder answer is refused with status 422
    And the report columns are "Investor name, Category"
