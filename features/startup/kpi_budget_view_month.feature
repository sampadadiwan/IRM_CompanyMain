Feature: KPI Budget View Month and Partial Data
  As a fund manager or company admin
  I want to see monthly KPI reports in budget view
  And I want to see data even if only one tag is present for a period
  And I want the ratio column to be blank if data for comparison is missing

  Background:
    Given Im logged in as a user "first_name=Test" for an entity "name=Test Fund;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=Monthly Startup;category=Portfolio Company"
    And a KpiReport "as_of=2024-03-31;period=Month;tag_list=Actual" exists for the entity "Monthly Startup"
    And a KPI "name=Revenue;value=1000" exists for the kpi report
    And a KpiReport "as_of=2024-04-30;period=Month;tag_list=Actual" exists for the entity "Monthly Startup"
    And a KPI "name=Revenue;value=1500" exists for the kpi report
    And a KpiReport "as_of=2024-04-30;period=Month;tag_list=Budget" exists for the entity "Monthly Startup"
    And a KPI "name=Revenue;value=1200" exists for the kpi report

  @javascript
  Scenario: View monthly reports with full and partial data
    When I go to the KPI reports page for "Monthly Startup" with budget view enabled and tags "Actual,Budget" and period "Month"
    And I fill in the number of periods with "2"
    And I click the filter button
    Then I should see a column header "Month"
    And I should see "1,000" in the "Revenue" row
    And I should see "1,500" in the "Revenue" row
    And I should see "1,200" in the "Revenue" row
    And I should see "125%" in the "Revenue" row

  @javascript
  Scenario: View monthly reports with multiple periods showing partial data
    When I go to the KPI reports page for "Monthly Startup" with budget view enabled and tags "Actual,Budget" and period "Month"
    # Change number of periods to 2 to see both March and April
    And I fill in the number of periods with "2"
    And I click the filter button
    Then I should see "1,000" in the "Revenue" row
    And I should see "1,500" in the "Revenue" row
    And I should see "1,200" in the "Revenue" row
    And I should see "125%" in the "Revenue" row
