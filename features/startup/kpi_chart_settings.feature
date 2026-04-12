@javascript
Feature: KPI Chart Settings
  As a user
  I want to save and load chart configurations for KPI reports
  So that I can easily view my preferred charts

  Background:
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And a KpiReport "as_of=2024-01-01;period=Month" exists for the entity
    And a KPI "name=Revenue;value=1000" exists for the kpi report
    And a KPI "name=EBITDA;value=200" exists for the kpi report
    And the following KPI mappings exist for the portfolio company:
      | reported_kpi_name |
      | Revenue           |
      | EBITDA            |

  Scenario: Save and reuse a KPI chart setting
    When I go to the KPIs of the company "MyFavStartup"
    And I check the KPI "Revenue" for charting
    And I check the KPI "EBITDA" for charting
    Then I should see chart controls for "Revenue"
    And I should see chart controls for "EBITDA"
    When I select "column" as the chart type for "EBITDA"
    And I enter "Revenue vs EBITDA" as the setting name
    And I click "Save Setting" and accept the alert
    Then I should see "Setting saved successfully!" in an alert
    
    When I refresh the page
    And I click "Saved Charts"
    Then I should see "Revenue vs EBITDA" in the saved charts list
    
    When I check "Revenue vs EBITDA" in the saved charts list
    Then the chart container should be visible
