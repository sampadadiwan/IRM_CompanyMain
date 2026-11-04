@rack_test @report_builder
Feature: Report Builder report page — opening and sorting

  Worked examples: openspec/changes/report-builder-trust/design.md#worked-examples
  A Report Builder report's name on the Reports list opens its report page.
  Clicking a column header sorts the page for this visit only.

  Background:
    Given the Acme report builder data
    And the Acme report "LPs"
    And the report also shows "capital_commitments.committed_amount"

  # H20 — Happy path: sorting by Committed, highest first, from its header
  Scenario: Sort by a column header
    Given I am signed in as Meera
    When I open the Report Builder page with "sort=capital_commitments.committed_amount&dir=desc"
    Then the rows are in the order "Aditi Rao, Kiran Mehta, Zeta Holdings, Nova LP"
    And the "Committed amount" header shows it is sorted "descending"

  # H21 — Happy path: the report's name on the Reports list opens the report page, not the builder
  Scenario: The report name opens the report page
    Given I am signed in as Meera
    When I open the reports list
    Then the name "LPs" links to its report page

  # E21 — Edge case: a header sort isn't saved; the next visit uses the saved sort
  Scenario: The saved sort is unchanged by a header sort
    Given the report is saved sorted by "investor_name" "desc"
    And I am signed in as Meera
    When I open the Report Builder page with "sort=capital_commitments.committed_amount&dir=desc"
    And I open the Report Builder page
    Then the rows are in the order "Zeta Holdings, Nova LP, Kiran Mehta, Aditi Rao"
    And the saved sort is still "investor_name" "desc"

  # E22 — Edge case: the sort is kept across pages
  Scenario: The sort is kept across pages
    Given I am signed in as Meera
    When I open the Report Builder page with "sort=capital_commitments.committed_amount&dir=desc&per_page=2"
    Then the next page link keeps the sort "capital_commitments.committed_amount" "desc"
    When I open the Report Builder page with "sort=capital_commitments.committed_amount&dir=desc&per_page=2&page=2"
    Then the rows are in the order "Zeta Holdings, Nova LP"

  # E23 — Edge case: a computed sort on a report bigger than the row cap says it sorted within the cap
  Scenario: A capped computed sort is noted
    Given the computed sort row cap is 3
    And I am signed in as Meera
    When I open the Report Builder page with "sort=capital_commitments.committed_amount&dir=desc"
    Then the Report Builder page says "Sorted within the first 3 rows"

  # E24 — Edge case: other reports keep their own links on the Reports list
  Scenario: A grid report's name keeps its own link
    Given a grid report "Legacy LP grid" on "/investors"
    And I am signed in as Meera
    When I open the reports list
    Then the name "Legacy LP grid" links to its own grid URL

  # X4 — Error case: a sort naming a column that isn't in the report is ignored
  Scenario: An unknown sort column is ignored
    Given I am signed in as Meera
    When I open the Report Builder page with "sort=not_a_column&dir=desc"
    Then the Report Builder page loads
    And the rows are in the order "Aditi Rao, Kiran Mehta, Zeta Holdings, Nova LP"

  # X5 — Error case: another entity's user can't open the report page, sorted or not
  Scenario: Another entity's user is refused
    Given I am signed in as Omar from another entity
    When I open the Report Builder page with "sort=capital_commitments.committed_amount&dir=desc"
    Then the page is refused
