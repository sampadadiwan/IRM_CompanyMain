# Worked examples (H14-H16, E16, E17): openspec/changes/fix-portfolio-dashboard-widgets/design.md#worked-examples
Feature: Portfolio Investments widget groups by a column of the grid
  "Group by column" is a pick-list of the grid's columns, and a chosen column takes effect whether or not AG Grid is
  switched on.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=Flipkart Unlisted;category=Portfolio Company"

  # H14 — Happy path: the choices are the grid's columns, including Fund Name
  @rack_test
  Scenario: List shows the grid's columns
    Given a dashboard widget "Portfolio Investments" exists for "Portfolio Company Dashboard"
    When I go to the edit page for the "Portfolio Investments" widget
    Then the field "group_by_column" should have the label "Group by column"
    And the field "group_by_column" should be a list including "Instrument"
    And the field "group_by_column" should be a list including "Portfolio Company"
    And the field "group_by_column" should be a list including "Fund Name"

  # H15 — Happy path: a group column with AG Grid off still uses the grid
  @rack_test
  Scenario: Grouping with AG Grid off
    Given the company dashboard has the widget "Portfolio Investments" with metadata "{ag: false, group_by_column: 'fund_name'}"
    When I open the company page
    Then the Portfolio Investments widget should request the AG grid grouped by "fund_name"

  # H16 — Happy path: a group column with AG Grid not set uses the grid
  @rack_test
  Scenario: Grouping with AG Grid default
    Given the company dashboard has the widget "Portfolio Investments" with metadata "{group_by_column: 'fund_name'}"
    When I open the company page
    Then the Portfolio Investments widget should request the AG grid grouped by "fund_name"

  # E16 — Edge case: no group column and AG off keeps the aggregate table
  @rack_test
  Scenario: No group column
    Given the company dashboard has the widget "Portfolio Investments" with metadata "{ag: false}"
    When I open the company page
    Then the Portfolio Investments widget should request the aggregate table

  # E17 — Edge case: a saved comma-separated value stays selected and is kept when saved
  @javascript
  Scenario: Saved value is preserved
    Given a dashboard widget "Portfolio Investments" exists for "Portfolio Company Dashboard" with metadata "{group_by_column: 'fund_name, investment_instrument_name'}"
    When I go to the edit page for the "Portfolio Investments" widget
    Then the field "group_by_column" should contain "fund_name, investment_instrument_name"
    When I save the widget
    Then the saved metadata of the "Portfolio Investments" widget should contain "group_by_column: 'fund_name, investment_instrument_name'"
