Feature: KPI Self-Reporting Reminder Email

  Background:
    Given there is a user "first_name=Fund;last_name=Employee" for an entity "name=Demo Fund;entity_type=Investment Fund"
    And there is another user "first_name=Portco;last_name=Founder;email=founder@startupone.com" for another entity "name=Startup One;category=Portfolio Company"
    And the other entity is an investor with category "Portfolio Company"
    And investor access "approved=1" in the portfolio company
    And the entity setting for "Demo Fund" has kpi_reminder_frequency "Monthly" and kpi_reminder_before 0

  @javascript
  Scenario: Send reminder email and verify the link
    When the periodic KPI report generation job runs for today
    Then an email should be sent to "founder@startupone.com" with subject containing "Reminder: KPI Reporting for Startup One"
    And the email should contain a link to "Fill KPI Report"
    When I follow the "Fill KPI Report" link in the email
    Given I fill and submit the login page
    Then I should see the kpi report details

  @javascript
  Scenario: Send manual reminder email from the KPI report show page
    And a KpiReport "as_of=2024-12-31;period=Month;enable_portco_upload=true" exists for the portfolio company "Startup One"
    And I log in with email "founder@startupone.com"
    And I am on the kpi report show page
    When I press "Send Notification"
    Then an email should be sent to "founder@startupone.com" with subject containing "Reminder to report KPIs for Startup One"
    And the email should contain a link to "Fill KPI Report"

