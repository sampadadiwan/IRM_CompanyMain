Feature: KPI Approval Workflow
  As an authorized user
  I want to approve staged KPI data
  So that it becomes the official data point for the company

  Background:
    Given Im logged in as a user "first_name=Approver" for an entity "entity_type=Investment Fund"
    And the user has role "approver"
    And there is an existing portfolio company "name=MyStartup;category=Portfolio Company"
    And the following KPI mappings exist for the portfolio company:
      | reported_kpi_name |
      | Revenue           |
      | EBITDA            |

  Scenario: Approving an individual KPI
    Given there is an unapproved KPI "name=Revenue;value=1000" for the company
    And I am on the KPI reports page for the portfolio company in grid view with staged data
    When I approve the KPI "Revenue"
    Then I should see the KPI "Revenue" with value "1,000.0" as approved
    And the KPI "Revenue" should have "approved" status in the database

  Scenario: Approving all staged KPIs
    Given the following unapproved KPIs exist for the company:
      | name    | value |
      | Revenue | 2000  |
      | EBITDA  | 500   |
    And I am on the KPI reports page for the portfolio company in grid view with staged data
    When I approve all staged KPIs
    Then I should see the following KPIs as approved:
      | name    | value   |
      | Revenue | 2,000.0 |
      | EBITDA  | 500.0   |
    And all KPIs for "MyStartup" should have "approved" status in the database
