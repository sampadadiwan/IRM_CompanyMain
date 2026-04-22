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
