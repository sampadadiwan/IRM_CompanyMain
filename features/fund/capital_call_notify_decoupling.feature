Feature: Capital call notification decoupled from approval
  Approving a capital call and notifying investors about it are separate actions. Notifications
  are only ever sent for an approved call, sending is safe to repeat, and sandbox mode is called
  out before anything goes out. See docs/modules/funds/capital_call_notify_decoupling.md.

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

@import
Scenario Outline: Send Call Notification access on a remittance depends only on employee permission, not the call's approval
  Given there is a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "<role>"
  Given there is an existing investor ""
  Given there is a fund "name=SAAS Fund" for the entity
  Given the fund has capital commitments from each investor
  Given the fund has "1" capital call
  Then user "<can_send>" have "send_notification" access to the capital remittances

  Examples:
    | role          | can_send |
    | company_admin | true     |
    | investor      | false    |

@import
Scenario: Send Call Notification is greyed out on a remittance when the call is set up not to send notifications
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  And Given I upload an investors file for the fund
  Given the investors have approved investor access
  Given the fund has capital call template
  Given the investors are added to the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given the commitments have a cc "advisor@gmail.com"
  Given there is a capital call "percentage_called=20;call_basis=Percentage of Commitment;send_call_notice_flag=false"
  Then when the capital call is approved
  Given I visit the first capital remittance for the call
  Then I should see the notification action disabled with reason "the call is set up to not send notifications"

@import @doc_gen
Scenario: Send Call Notification is greyed out on a remittance when its generated call notice is pending approval
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
  Given each investor has a "verified" kyc linked to the commitment
  And when the capital call docs are generated
  Then the generated doc must be attached to the capital remittances
  Given the generated call notices are approved
  Then when the capital call is approved
  Given the remittance's generated call notice is marked as pending approval again
  Given I visit the first capital remittance for the call
  Then I should see the notification action disabled with reason "pending approval"

@import
Scenario: Send Notification warns when a remittance's commitment has Skip Doc Gen enabled
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
  Given the first commitment has skip_doc_gen enabled
  Then I should see the skip doc gen warning when sending the call notification

@import @doc_gen
Scenario: Approve popup hides the confirm text when blocked by unapproved call notices
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given the user has role "approver"
  Given the default validation rules are seeded
  Given there is a fund "name=SAAS Fund" for the entity
  And Given I upload an investors file for the fund
  Given the investors have approved investor access
  Given the fund has capital call template
  Given the investors are added to the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given the commitments have a cc "advisor@gmail.com"
  When I create a new capital call "percentage_called=20;call_basis=Percentage of Commitment"
  Then I should see the capital call details
  Given each investor has a "verified" kyc linked to the commitment
  And when the capital call docs are generated
  Then the generated doc must be attached to the capital remittances
  Then I should see the approve blocker without the approval confirmation text

@import
Scenario: Unapprove reverts an approved capital call and warns when remittances have already been notified
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given the user has role "approver"
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
  Then the capital call notifications are sent
  Given I open the unapprove confirmation for the capital call
  Then the unapprove confirmation popup should contain "some remittances have already been notified"
  Given I confirm the unapprove action
  Then the capital call should no longer be approved

@import
Scenario: Unapprove warns when fund units have already been allocated
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given the user has role "approver"
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
  Given the remittances has some units already allocated
  Given I open the unapprove confirmation for the capital call
  Then the unapprove confirmation popup should contain "fund units have already been allocated"
  Given I confirm the unapprove action
  Then the capital call should no longer be approved
