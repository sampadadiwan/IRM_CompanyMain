Feature: KPI Budget View Multiple Tags
  As a fund manager or company admin
  I want to see the percentage change between any two selected tags in the KPI Budget View
  So that I can compare different scenarios beyond just Actual vs Budget

  Background:
    Given Im logged in as a user "first_name=Test" for an entity "name=Test Fund;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=Target Startup;category=Portfolio Company"
    And a KpiReport "as_of=2024-03-31;period=Quarter;tag_list=Budget" exists for the entity "Target Startup"
    And a KPI "name=Revenue;value=1000" exists for the kpi report
    And a KpiReport "as_of=2024-03-31;period=Quarter;tag_list=IC Case" exists for the entity "Target Startup"
    And a KPI "name=Revenue;value=1200" exists for the kpi report

  @javascript
  Scenario: Compare Budget and IC Case tags
    When I go to the KPI reports page for "Target Startup" with budget view enabled and tags "Budget,IC Case"
    Then I should see a column header "Budget / IC Case"
    And I should see "83.33%" in the "Revenue" row under the achievement column

  @javascript
  Scenario: Compare Actual and Budget tags (Original behavior)
    Given a KpiReport "as_of=2024-03-31;period=Quarter;tag_list=Actual" exists for the entity "Target Startup"
    And a KPI "name=Revenue;value=1100" exists for the kpi report
    When I go to the KPI reports page for "Target Startup" with budget view enabled and tags "Actual,Budget"
    Then I should see a column header "Actual / Budget"
    And I should see "110.00%" in the "Revenue" row under the achievement column
