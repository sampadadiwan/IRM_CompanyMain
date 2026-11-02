# Worked examples (H3-H6, H8, E10-E11): openspec/changes/fix-portfolio-dashboard-widgets/design.md#worked-examples
Feature: Dashboard Widget Metadata Configuration
  As an admin
  I want to configure dashboard widgets using dynamic fields
  So that I don't have to manually write Ruby/JSON strings

  Background:
    Given I am logged in as an admin
    And a dashboard widget "Fund Ratios" exists for "Fund Dashboard"

  @javascript
  Scenario: Loading dynamic fields for a widget
    When I go to the edit page for the "Fund Ratios" widget
    Then I should see the "Widget Configuration" section
    And I should see a field for "months"
    And I should see a field for "ratio_names"
    And I should see a field for "condensed"

  @javascript
  Scenario: Updating dynamic fields updates the raw metadata
    When I go to the edit page for the "Fund Ratios" widget
    Then I should see the "Widget Configuration" section
    When I fill in metadata "metadata_months" with "36"
    And I fill in metadata "metadata_ratio_names" with "XIRR, TVPI"
    And I select "ON" from "metadata_condensed"
    Then the "metadata" hidden field should contain "months: 36"
    And the "metadata" hidden field should contain "ratio_names: ['XIRR', 'TVPI']"
    And the "metadata" hidden field should contain "condensed: true"

  @javascript
  Scenario: Parsing irregular help text
    Given a dashboard widget "Fund Portfolio Stats" exists for "Fund Dashboard"
    When I go to the edit page for the "Fund Portfolio Stats" widget
    Then I should see a field for "fields"
    And the "fields" field should have placeholder "e.g. Bought Amount,Sold Amount"

  # H3 — Compound is shown as Data-only view with help
  Scenario: Compound is shown as Data-only view with help
    Given a dashboard widget "Kpis" exists for "Portfolio Company Dashboard"
    When I go to the edit page for the "Kpis" widget
    Then the field "compound" should have the label "Data-only view"
    And the field "compound" should have helper text containing "groups KPIs by category"
    And the field "compound" should have helper text containing "plot checkbox per KPI"

  # H4 — Show action buttons has helper text
  Scenario: Show action buttons has helper text
    Given a dashboard widget "Kpis" exists for "Portfolio Company Dashboard"
    When I go to the edit page for the "Kpis" widget
    Then the field "show_action_buttons" should have the label "Show action buttons"
    And the field "show_action_buttons" should have helper text containing "shows the heading and the filter, chart and settings buttons"

  # H5 — Budget vs Actual offers only the default category
  Scenario: Budget vs Actual offers only the default category
    Given a dashboard widget "Kpis Budget vs Actual" exists for "Portfolio Company Dashboard"
    When I go to the edit page for the "Kpis Budget vs Actual" widget
    Then there should be no field for "categories"
    And the field "category" should have the label "Default category"
    And the field "category" should have helper text containing "pre-selected in the filter"

  # H6 — Settings that do nothing are not offered
  Scenario Outline: Settings with no effect are not offered
    Given a dashboard widget "<widget>" exists for "<dashboard>"
    When I go to the edit page for the "<widget>" widget
    Then there should be no field for "<key>"

    Examples:
      | widget                 | dashboard                   | key         |
      | Kpis Performance Table | Portfolio Company Dashboard | chart       |
      | Key Kpis               | Portfolio Company Dashboard | kpis        |
      | Kpis                   | Portfolio Company Dashboard | show_table  |
      | Kpis                   | Portfolio Company Dashboard | show_chart  |
      | Kpis                   | Portfolio Company Dashboard | budget_view |
      | Kpis                   | Portfolio Company Dashboard | no_actions  |
      | Documents              | Portfolio Company Dashboard | entity_id   |

  # H8 — A whole number is saved
  @javascript
  Scenario: A whole number is saved
    Given a dashboard widget "Documents" exists for "Portfolio Company Dashboard"
    When I go to the edit page for the "Documents" widget
    And I type "42" into the field "folder_id"
    And I save the widget
    Then the saved metadata of the "Documents" widget should contain "folder_id: 42"

  # E10 — Letters are refused
  @javascript
  Scenario: Letters are refused in an ID field
    Given a dashboard widget "Documents" exists for "Portfolio Company Dashboard"
    When I go to the edit page for the "Documents" widget
    And I type "e12" into the field "folder_id"
    Then the field "folder_id" should contain "12"

  # E11 — Pasting mixed text keeps only digits
  @javascript
  Scenario: Pasting mixed text keeps only digits
    Given a dashboard widget "Documents" exists for "Portfolio Company Dashboard"
    When I go to the edit page for the "Documents" widget
    And I paste "1.5e3" into the field "owner_id"
    Then the field "owner_id" should contain "153"
