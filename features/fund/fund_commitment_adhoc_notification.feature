@notification
Feature: Fund Commitment Adhoc Notification
  As a GP admin I want to send a custom adhoc notification
  to all or a selected subset of fund commitment holders

  Scenario: Send notification to all commitments when no selection is made
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with subject "Q4 Update"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email

  Scenario: Send notification to a selected commitment only
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with subject "Selected Investor Notice"
    When the adhoc notification is triggered for the first commitment only
    Then only the first commitment investor receives the notification email
    And the second commitment investor does not receive a notification email

  Scenario: Notification attaches commitment document matching attachment_names
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "Statement of Account" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "Statement of Account"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has the document "Statement of Account" attached

  Scenario: GP admin can preview the fund's adhoc notification from a capital commitment
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with subject "Q4 Update"
    When I open the actions menu on the first capital commitment
    Then I see a preview adhoc notification button
    When I click the preview adhoc notification button for "Q4 Update"
    Then I see the adhoc notification preview with subject "Q4 Update"

  Scenario: GP admin can preview each adhoc notification when the fund has more than one defined
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with subject "Q4 Update"
    Given there is an adhoc custom notification for the fund with subject "Year End Wrap-up"
    When I open the actions menu on the first capital commitment
    Then I see 2 preview adhoc notification buttons
    When I click the preview adhoc notification button for "Year End Wrap-up"
    Then I see the adhoc notification preview with subject "Year End Wrap-up"

  Scenario: Preview button is hidden when the fund has no adhoc notification defined
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    When I open the actions menu on the first capital commitment
    Then I do not see a preview adhoc notification button

  Scenario: Placeholders are resolved in adhoc notification body
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with placeholders and subject "Placeholder Test"
    When the adhoc notification is triggered for all commitments
    Then the adhoc notification placeholders are resolved correctly
