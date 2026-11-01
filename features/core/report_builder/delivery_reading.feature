@rack_test @report_builder
Feature: Report Builder delivery — reading a report

  Worked examples: openspec/changes/report-builder-delivery/business-rules.md
  The report page says which filters the report applies, lets a reader narrow
  it for this visit without changing it, and shows the first totals as cards.
  The unused "Save as View" settings are gone.

  Background:
    Given the Acme report builder data
    And the Acme delivery report "LPs"
    And Aditi Rao is in "Mumbai" and Kiran Mehta in "Pune"
    And I am signed in as Meera

  # H9 — Happy path: the report's own filters as chips, with a way to change them in the builder
  Scenario: Saved filters as chips
    When I open the report builder report page
    Then the report shows only "Category is LP, Only capital commitments in Growth Fund II"
    And the report page offers "Change in builder"

  # H10 — Happy path: Narrow down to one city, for this visit only
  Scenario: Narrow down
    When I narrow the report down to "city" "eq" "Mumbai"
    Then the report page rows are "Aditi Rao"
    And the reader chips are "City is Mumbai"
    And the report's saved filters are still Category is LP

  # H11 — Happy path: the first totals as cards, each the totals row's text
  Scenario: Headline totals
    When I open the report builder report page
    Then the headline cards are "Committed=7,50,00,000.00 | Called=3,00,00,000.00"
    And each headline card equals the totals row

  # H12 — Happy path: no View settings, and the old address is gone
  Scenario: Save as View is gone
    When I open the builder
    Then the builder page has no View or Sharing settings
    When I request the old view-settings address
    Then the answer is Not found

  # E8 — Edge case: ✕ on a reader chip shows the report's rows again
  Scenario: Remove a reader filter
    Given I narrow the report down to "city" "eq" "Mumbai"
    When I remove the reader chip "City is Mumbai"
    Then the report page rows are "Aditi Rao, Kiran Mehta, Nova LP"
    And there are no reader chips

  # E9 — Edge case: a reader filter can't replace a filter the report sets
  Scenario: Reader can't override a saved filter
    When I open the report builder report page with "q[category_eq]=Co-Investor"
    Then the report page rows are "Aditi Rao, Kiran Mehta, Nova LP"
    And the report page reads "Category is already set by the report"
    And there are no reader chips

  # E10 — Edge case: a filter on a field that isn't one of the report's is ignored
  Scenario: Unknown field ignored
    When I open the report builder report page with "q[no_such_field_eq]=x"
    Then the report page rows are "Aditi Rao, Kiran Mehta, Nova LP"
    And there are no reader chips

  # E11 — Edge case: a report without filters shows no "shows only" line, and Narrow down is still there
  Scenario: No saved filters
    Given the report has no filters
    When I open the report builder report page
    Then the report page has no "This report shows only"
    And the report page offers Narrow down

  # E12 — Edge case: on a paged report the cards say "this page", like the totals row
  Scenario: Paged report
    When I open the report builder report page with "per_page=2"
    Then each headline card equals the totals row
    And each headline card says "this page"
    And the totals row reads "Total (this page)"

  # E13 — Edge case: nothing to total, no cards
  Scenario: Nothing to total
    Given the report shows only Investor and Category
    When I open the report builder report page
    Then there are no headline cards

  # E14 — Edge case: a report once marked as a view opens like any report
  Scenario: A report once marked as a view
    Given the report was once marked as a view
    When I open the report builder report page
    Then the report page rows are "Aditi Rao, Kiran Mehta, Nova LP"
