Feature: Email bounce and complaint detection & reporting
  Notifier-driven emails are tagged for SES bounce/complaint tracking. SES reports bounces
  and complaints back via SNS, which are recorded and shown in a scoped report, with a
  manual (never automatic) way to disable further email to a bounced address.

  Background:
    Given I am logged in as an admin
    And the user has role "company_admin"

  @stub-ses-signature
  Scenario: A notifier-driven email is tagged and a bounce is correlated back to it
    Given a notification-linked email has been sent to "investor@example.com"
    When SES reports a bounce for that email
    Then the notification should show a bounced status
    And I visit the email bounce events report
    And I should see "investor@example.com" in the email bounce events table
    And I should see "Permanent" in the email bounce events table

  Scenario: A directly-invoked mailer with no notification is never tagged
    When a direct mailer email is sent to "nobody@example.com" with no notification
    Then no tracking headers should be present on the sent email

  @stub-ses-signature
  Scenario: A complaint is tracked with its feedback type
    Given a notification-linked email has been sent to "complainer@example.com"
    When SES reports a complaint for that email
    And I visit the email bounce events report
    Then I should see "Complaint" in the email bounce events table
    And I should see "abuse" in the email bounce events table

  Scenario: An unsigned SES notification is rejected
    When an unsigned SNS bounce notification is posted to the webhook
    Then the webhook should respond with status 403

  @stub-ses-signature
  Scenario: A company admin only sees bounce events for their own entity
    Given a notification-linked email has been sent to "investor@example.com"
    And SES reports a bounce for that email
    And there is another entity "name=Other Fund" with its own bounced email "other@example.com"
    When I visit the email bounce events report
    Then I should see "investor@example.com" in the email bounce events table
    And I should not see "other@example.com" in the email bounce events table

  @stub-ses-signature
  Scenario: An internal admin sees bounce events across all entities
    Given a notification-linked email has been sent to "investor@example.com"
    And SES reports a bounce for that email
    And there is another entity "name=Other Fund" with its own bounced email "other@example.com"
    And I log out
    And I am logged in as an internal admin
    When I visit the email bounce events report
    Then I should see "investor@example.com" in the email bounce events table
    And I should see "other@example.com" in the email bounce events table

  @stub-ses-signature
  Scenario: Disabling email for a bounced address updates InvestorAccess and is audited
    Given a notification-linked email has been sent to "investor@example.com"
    And SES reports a bounce for that email
    And there is an InvestorAccess record with email "investor@example.com" for my entity
    When I visit the email bounce events report
    And I click "Disable Email" and confirm the dialog
    Then I should see a flash notice containing "Disabled email for 1 InvestorAccess record"
    And the InvestorAccess record for "investor@example.com" should have email disabled
