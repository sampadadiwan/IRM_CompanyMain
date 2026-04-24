Feature: ReportMailer — scheduled report email delivery

  Background:
    Given a report builder entity and user
    And a report builder report exists for the entity
    And the email queue is empty

  Scenario: Scheduled report email is delivered with correct subject
    When the scheduled report mailer is sent for the report
    Then an email should be delivered
    And the delivered email subject should include "Test Report"

  Scenario: Scheduled report email includes an XLSX attachment
    When the scheduled report mailer is sent for the report
    Then an email should be delivered
    And the delivered email should have an attachment

  Scenario: Scheduled report HTML template renders report name
    When the scheduled report mailer is sent for the report
    Then an email should be delivered
    And the delivered email HTML body should include "Test Report"

  Scenario: Scheduled report text template renders report name
    When the scheduled report mailer is sent for the report
    Then an email should be delivered
    And the delivered email text body should include "Test Report"

  Scenario: Scheduled report HTML template renders generation timestamp
    When the scheduled report mailer is sent for the report
    Then an email should be delivered
    And the delivered email HTML body should include "Generated"
