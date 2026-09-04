Feature: Bulk Mark Notification Sent / Unsent
  Business rationale (docs/user_guides/capital_call_actions_and_notifications_matrix.md,
  Question 3): after a call correction, or when a Call Notice bounced, the remittance's
  "Notification Sent" flag had to be reset by an engineer at the console or one Edit Remittance
  screen at a time. These bulk actions on the remittance search page let the business team set the
  flag for every remittance in the current search results in one step — the same self-service
  pattern as the "Toggle Verify" bulk action. They are explicit set-to-a-value actions, not a
  toggle, so a mixed selection can never silently flip a never-notified investor to "sent".

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the user has role "company_admin"
    Given there is an existing investor "investor_name=Investor 1" with "1" users
    Given there is a fund "name=TestFund;currency=INR" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is a capital call "percentage_called=20"
    Then the corresponding remittances should be created
    Given the capital calls are approved


  Scenario: Mark Unsent re-opens already-notified investors for a fresh call-level Send Notification
    Given the remittances are directly marked with notification_sent "true"
    Given I filter the "capital_remittances" by "notification_sent=true"
    And I trigger the bulk action for "Mark Notification Unsent"
    And the remittances have notification_sent set to "false"


  Scenario: Mark Sent records investors notified outside the system so Send Notification skips them
    Given the remittances are directly marked with notification_sent "false"
    Given I filter the "capital_remittances" by "notification_sent=false"
    And I trigger the bulk action for "Mark Notification Sent"
    And the remittances have notification_sent set to "true"


  Scenario: Mark Unsent is idempotent — remittances already unsent stay unsent
    Given the remittances are directly marked with notification_sent "false"
    Given I filter the "capital_remittances" by "verified=false"
    And I trigger the bulk action for "Mark Notification Unsent"
    And the remittances have notification_sent set to "false"
