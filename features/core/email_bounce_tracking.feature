Feature: Email bounce and complaint detection & reporting
  Notifier-driven emails are tagged for SES bounce/complaint tracking. SES reports bounces
  and complaints back via SNS, which are recorded and shown in a scoped report, with a
  manual (never automatic) way to disable further email to a bounced address.

  Background:
    Given I am logged in as an admin
    And the user has role "company_admin"

  @stub-ses-signature @rack_test
  Scenario: A notifier-driven email is tagged and a bounce is correlated back to it
    Given a notification-linked email has been sent to "investor@example.com"
    When SES reports a bounce for that email
    Then the notification should show a bounced status
    And I visit the email bounce events report
    And I should see "investor@example.com" in the email bounce events table
    And I should see "Permanent" in the email bounce events table

  # Regression guard. SES names the event-type field "eventType" when events come from a
  # configuration set (what production uses) and "notificationType" only on the legacy
  # identity-notification path. The job originally read notificationType alone, so every
  # real event fell straight through while the endpoint still returned 200 - SNS counted the
  # delivery as successful and email_bounce_events stayed empty. The scenario above now
  # sends the eventType shape; this one keeps the legacy shape working too.
  # SES publishes a plain-text confirmation to the topic when a configuration set event
  # destination is created - "Successfully validated SNS topic for Amazon SES event
  # publishing." It is not JSON, and raising on it made Sidekiq retry an unparseable message
  # 25 times, reporting an exception each time. Seen in staging the moment the destination
  # was created.
  @stub-ses-signature
  Scenario: A non-JSON message on the topic is ignored rather than retried
    When SES publishes its plain-text topic validation message
    Then no email bounce events should be recorded

  @stub-ses-signature @rack_test
  Scenario: A bounce sent with the legacy notificationType field is still recorded
    Given a notification-linked email has been sent to "legacy@example.com"
    When SES reports a bounce for that email using the legacy notificationType field
    Then the notification should show a bounced status
    And I visit the email bounce events report
    And I should see "legacy@example.com" in the email bounce events table

  Scenario: A directly-invoked mailer with no notification is never tagged
    When a direct mailer email is sent to "nobody@example.com" with no notification
    Then no tracking headers should be present on the sent email

  @stub-ses-signature @rack_test
  Scenario: A complaint is tracked with its feedback type
    Given a notification-linked email has been sent to "complainer@example.com"
    When SES reports a complaint for that email
    And I visit the email bounce events report
    Then I should see "Complaint" in the email bounce events table
    And I should see "abuse" in the email bounce events table

  # A valid SNS signature only proves the message came from SOME SNS topic in SOME AWS
  # account - it does not bind it to ours. Without a TopicArn allowlist anyone could point
  # this endpoint at a topic they control and inject Bounce payloads, setting bounced_at on
  # any notification whose tracking UUID they guessed.
  @stub-ses-signature @rack_test
  Scenario: A correctly signed notification from someone else's topic is rejected
    When SES reports a bounce from an SNS topic we do not own
    Then the notification should be rejected as coming from an unexpected topic
    And no email bounce events should be recorded

  @rack_test
  Scenario: An unsigned SES notification is rejected
    When an unsigned SNS bounce notification is posted to the webhook
    Then the webhook should respond with status 403

  @stub-ses-signature @rack_test
  Scenario: A company admin only sees bounce events for their own entity
    Given a notification-linked email has been sent to "investor@example.com"
    And SES reports a bounce for that email
    And there is another entity "name=Other Fund" with its own bounced email "other@example.com"
    When I visit the email bounce events report
    Then I should see "investor@example.com" in the email bounce events table
    And I should not see "other@example.com" in the email bounce events table

  @stub-ses-signature @rack_test
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
