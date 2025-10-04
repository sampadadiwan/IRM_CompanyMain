Feature: Dashboard Widgets Import
  Verify import and validation of Dashboard Widgets functionality

  @import
  Scenario Outline: Import Dashboard Widgets
    Given Im logged in as a user "<user>" for an entity "<entity>"
    Given the user has role "company_admin"
    And Given import file "dashboard_widgets.xlsx" for "DashboardWidget"
    And the dashboard widgets must have the data in the sheet

  Examples:
      |user     |entity                                 |fund                 |
      |           |entity_type=Investment Fund;enable_funds=true  |name=Demo Fund  |