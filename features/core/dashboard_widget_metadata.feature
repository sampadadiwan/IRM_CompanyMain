# Worked examples (H3-H6, H8, E10-E11): openspec/changes/fix-portfolio-dashboard-widgets/design.md#worked-examples
# Worked examples (H1-H3, H8, H9, E11-E13, E17, E18): openspec/changes/fix-portfolio-dashboard-widgets-2/design.md#worked-examples
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
    And the "field_names" field should have placeholder "e.g. Bought, Sold"

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

  # H1 — Happy path: stats Fields picked from the list are saved in the order picked
  @javascript
  Scenario: Stats fields are saved in the order picked
    Given a dashboard widget "Portfolio Stats" exists for "Portfolio Company Dashboard"
    When I go to the edit page for the "Portfolio Stats" widget
    And I pick "FMV" in the multi-select "fields"
    And I pick "Bought Amount" in the multi-select "fields"
    Then the "metadata" hidden field should contain "fields: 'FMV, Bought Amount'"
    When I save the widget
    Then the saved metadata of the "Portfolio Stats" widget should contain "fields: 'FMV, Bought Amount'"

  # H2 — Happy path: saved stats Fields reopen selected in their saved order
  @javascript
  Scenario: Saved stats fields reopen in their saved order
    Given a dashboard widget "Portfolio Stats" exists for "Portfolio Company Dashboard" with metadata "{fields: 'Sold Amount, Bought Amount'}"
    When I go to the edit page for the "Portfolio Stats" widget
    Then the multi-select "fields" should show "Sold Amount, Bought Amount"

  # H3 — Happy path: Field names explains the order rule
  Scenario: Field names hint on a fund stats widget
    Given a dashboard widget "Fund Portfolio Stats" exists for "Fund Dashboard"
    When I go to the edit page for the "Fund Portfolio Stats" widget
    Then the field "field_names" should have the label "Field names"
    And the field "field_names" should have helper text containing "same order as the Fields you picked"

  # H8 — Happy path: the Data Card offers only Fields and Title
  Scenario: Data Card offers Fields and Title only
    Given a dashboard widget "Data Card" exists for "Portfolio Company Dashboard"
    When I go to the edit page for the "Data Card" widget
    Then I should see a field for "fields"
    And I should see a field for "title"
    And there should be no field for "cols"
    And there should be no field for "field_names"

  # H9 — Happy path: the Data Card's Fields help stays visible while typing
  @javascript
  Scenario: Data Card fields help stays while typing
    Given a dashboard widget "Data Card" exists for "Portfolio Company Dashboard"
    When I go to the edit page for the "Data Card" widget
    And I type "Category:" into the field "fields"
    Then the field "fields" should have helper text containing "custom_fields."
    And the field "fields" should have helper text containing "KPI Currency:custom_fields.kpi_currency"

  # E11 — Edge case: a saved field name that is not a card is dropped when the form is saved
  @javascript
  Scenario: Unknown saved stats field is dropped on save
    Given a dashboard widget "Portfolio Stats" exists for "Portfolio Company Dashboard" with metadata "{fields: 'FMV, Total FMV'}"
    When I go to the edit page for the "Portfolio Stats" widget
    And I save the widget
    Then the saved metadata of the "Portfolio Stats" widget should contain "fields: 'FMV'"
    And the saved metadata of the "Portfolio Stats" widget should not contain "Total FMV"

  # E12 — Edge case: the company stats widget offers a Default currency pick-list with its order hint
  Scenario: Company stats offer a Default currency
    Given the entity has currency "INR" and an exchange rate from "USD" to "INR"
    And a dashboard widget "Portfolio Stats" exists for "Portfolio Company Dashboard"
    When I go to the edit page for the "Portfolio Stats" widget
    Then I should see a field for "tracking_currency"
    And I should see a field for "show_currency_filter"
    And the field "currency" should have the label "Default currency"
    And the field "currency" should offer "USD, INR"
    And the field "currency" should have helper text containing "Order: picked on page > Tracking currency (if ON) > Default currency > firm's currency"

  # E13 — Edge case: fund-level stats widgets offer no currency settings
  Scenario Outline: Fund-level stats offer no currency settings
    Given a dashboard widget "<widget>" exists for "<dashboard>"
    When I go to the edit page for the "<widget>" widget
    Then there should be no field for "currency"
    And there should be no field for "tracking_currency"
    And there should be no field for "show_currency_filter"
    And I should see a field for "per_row"

    Examples:
      | widget               | dashboard           |
      | Fund Portfolio Stats | Fund Dashboard      |
      | Portfolio Stats      | Portfolio Dashboard |

  # E17 — Edge case: removing every chip leaves Fields out of the saved settings
  @javascript
  Scenario: Removing all stats fields leaves the setting out
    Given a dashboard widget "Portfolio Stats" exists for "Portfolio Company Dashboard" with metadata "{fields: 'FMV', decimals: 2}"
    When I go to the edit page for the "Portfolio Stats" widget
    And I remove "FMV" from the multi-select "fields"
    And I save the widget
    Then the saved metadata of the "Portfolio Stats" widget should not contain "fields"

  # E18 — Edge case: Fields works as a multi-select when the widget type is chosen on a new widget
  @javascript
  Scenario: Stats fields multi-select on a new widget
    When I go to the new dashboard widget page
    And I choose the dashboard "Portfolio Company Dashboard" and widget type "Portfolio Stats"
    And I pick "FMV" in the multi-select "fields"
    Then the "metadata" hidden field should contain "fields: 'FMV'"
