Feature: KPI Self-Reporting Reminder Email

  Background:
    Given there is a user "first_name=Fund;last_name=Employee;email=employee@if.com" for an entity "name=Demo Fund;entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is another user "first_name=Portco;last_name=Founder;email=founder@startupone.com" for another entity "name=Startup One;category=Portfolio Company"
    And the other entity is an investor with category "Portfolio Company"
    And investor access "approved=1" in the portfolio company
    And the entity setting for "Demo Fund" has kpi_reminder_frequency "Monthly" and kpi_reminder_before 0

  @javascript
  Scenario: Send reminder email and verify the link
    Given the periodic KPI report generation job runs for today
    Then an email should be sent to "founder@startupone.com" with subject containing "Reminder to report KPIs for Startup One"
    And the email should contain a link to "Fill KPI Report"

  @javascript
  Scenario: Manually trigger periodic KPI report from the show page
    And a KpiReport "as_of=2024-12-31;period=Month;enable_portco_upload=true" exists for the portfolio company "Startup One"
    Given I log in with email "employee@if.com"
    And I am on the kpi report show page
    When I press "Trigger Upload Notification"
    Then I should see the message "Periodic KPI reports generation triggered"
    And an email should be sent to "founder@startupone.com" with subject containing "Reminder to report KPIs for Startup One"
    Given I log out
    When I follow the "Fill KPI Report" link in the email
    Then I should see the kpi report details

  @javascript
  Scenario: Manually send KPI reminder with a specific date from grid view
    Given I log in with email "employee@if.com"
    And I am on the kpis page for the portfolio company "Startup One"
    When I click the dropdown item "Actions"
    And I click "Send Reminder"
    Then I should see a modal with title "Send KPI Report Reminder"
    When I fill in "Period Ending Date" with "2024-03-31"
    And I press "Send Reminder"
    And a KpiReport "as_of=2024-03-31;tag_list=Actual" should exist for the portfolio company "Startup One"
    And an email should be sent to "founder@startupone.com" with subject containing "Reminder to report KPIs for Startup One"
