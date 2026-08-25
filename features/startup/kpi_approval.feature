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

  Scenario: Rejecting an individual KPI
    Given there is an unapproved KPI "name=Revenue;value=1000" for the company
    And I am on the KPI reports page for the portfolio company in grid view with staged data
    When I reject the KPI "Revenue"
    Then I should not see the KPI "Revenue" with value "1,000.0"
    And the KPI "Revenue" should not exist in the database

  Scenario: Toggling a KPI between approved and unapproved from its own show page
    Given there is an approved KPI "name=Revenue;value=1000" for the company
    When I visit the KPI show page for "Revenue"
    Then I should see an "Unapprove" button
    And I should not see an "Approve" button
    When I click "Unapprove" and confirm
    Then the KPI "Revenue" should have "unapproved" status in the database
    When I visit the KPI show page for "Revenue"
    Then I should see an "Approve" button
    And I should not see an "Unapprove" button

  Scenario: Verifying unapproved KPI statistics cards
    Given the following unapproved KPIs exist for the company:
      | name    | value | period_relative |
      | Revenue | 1000  | last year       |
      | Revenue | 2000  | this month      |
      | EBITDA  | 500   | this quarter    |
      | Revenue | 3000  | this year       |
    And I am on the KPI reports page for the portfolio company in grid view with staged data
    Then I should see the following unapproved KPI stats:
      | subtitle              | count |
      | Total Unapproved      | 4     |
      | Unapproved Prev Year  | 1     |
      | Unapproved This Month | 1     |
      | Unapproved This Qtr   | 3     |
      | Unapproved This Year  | 3     |
    And the "Total Unapproved" card should link to the unapproved KPIs
