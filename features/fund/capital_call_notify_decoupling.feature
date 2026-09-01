Feature: Capital call notification decoupled from approval
  Approving a capital call and notifying investors about it are separate actions. Notifications
  are only ever sent for an approved call, sending is safe to repeat, and sandbox mode is called
  out before anything goes out. See docs/technical/capital_call_notify_decoupling.md.

@import
Scenario: Approving a capital call does not, by itself, send any notification
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  And Given I upload an investors file for the fund
  Given the investors have approved investor access
  Given the fund has capital call template
  Given the investors are added to the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital call "percentage_called=20;call_basis=Percentage of Commitment"
  Then I should see the capital call details
  Given the notification deliveries are cleared
  Then when the capital call is approved
  Then no capital call notification emails should have been sent

@import
Scenario: Sending the call notification twice does not email investors twice
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  And Given I upload an investors file for the fund
  Given the investors have approved investor access
  Given the fund has capital call template
  Given the investors are added to the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital call "percentage_called=20;call_basis=Percentage of Commitment"
  Then I should see the capital call details
  Then when the capital call is approved
  Given the notification deliveries are cleared
  Then the capital call notifications are sent
  Then some capital call notification emails should have been sent
  Given the notification deliveries are cleared
  Then the capital call notifications are sent
  Then no capital call notification emails should have been sent

@import
Scenario: Sandbox warning appears when sending the call notification with sandbox mode on
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  And Given I upload an investors file for the fund
  Given the investors have approved investor access
  Given the fund has capital call template
  Given the investors are added to the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital call "percentage_called=20;call_basis=Percentage of Commitment"
  Then I should see the capital call details
  Given the entity is in sandbox mode with sandbox email "sandbox@example.com"
  Given I approve the capital call
  Then I should see the sandbox warning when sending the call notification

@import
Scenario: Manually setting Notification Sent on a remittance flips the notification button label
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  And Given I upload an investors file for the fund
  Given the investors have approved investor access
  Given the fund has capital call template
  Given the investors are added to the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital call "percentage_called=20;call_basis=Percentage of Commitment"
  Then I should see the capital call details
  Then when the capital call is approved
  Given I visit the first capital remittance for the call
  Then I should see "Send Call Notification" as the notification action
  Given I manually set Notification Sent to Yes on the remittance
  Then I should see "Send Call Reminder" as the notification action

@import
Scenario: Reminder and payment notifications are blocked before the capital call is approved
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  And Given I upload an investors file for the fund
  Given the investors have approved investor access
  Given the fund has capital call template
  Given the investors are added to the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital call "percentage_called=20;call_basis=Percentage of Commitment"
  Then I should see the capital call details
  Then the capital call reminder should be blocked because the call is not approved
  Then the capital call payment notification should be blocked because the call is not approved
