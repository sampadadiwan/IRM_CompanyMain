Feature: Selecting which remittances to verify in the bulk verify modal
  Only unverified remittances with a collected amount greater than 0 are eligible to
  be bulk-verified. The bulk verify modal also lets a user narrow verification down
  to specific remittances instead of verifying every eligible one, since verification
  triggers payment notifications.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the user has role "company_admin"
    Given there is an existing investor "investor_name=Investor 1" with "1" users
    Given there is an existing investor "investor_name=Investor 2" with "1" users
    Given there is a fund "name=TestFund;currency=INR" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is a capital call "percentage_called=20;send_payment_notification_flag=true"
    Then the corresponding remittances should be created
    Given the capital calls are approved


  Scenario: Unverified remittances with nothing collected are excluded and left untouched
    Given only the first remittance has a payment collected
    When I open the bulk verify remittances modal for the capital call
    Then the bulk verify modal should contain "1 Eligible Remittance"
    When I confirm the bulk verify remittances action
    Then the first remittance should be verified
    And the second remittance should still be unverified


  Scenario: The remittance picker excludes remittances with nothing collected
    Given only the first remittance has a payment collected
    When I open the bulk verify remittances modal for the capital call
    Then the remittance picker should contain the first remittance
    And the remittance picker should not contain the second remittance


  Scenario: User can narrow verification down to specific remittances
    Given the remittances are paid
    When I open the bulk verify remittances modal for the capital call
    And I select only the first remittance in the bulk verify modal
    And I confirm the bulk verify remittances action
    Then the first remittance should be verified
    And the second remittance should still be unverified


  Scenario: Reopening the modal reflects the current state without a full page reload
    Given the remittances are paid
    When I open the bulk verify remittances modal for the capital call
    Then the bulk verify modal should contain "2 Eligible Remittances"
    Given the first remittance is verified
    When I close the bulk verify remittances modal
    And I reopen the bulk verify remittances modal
    Then the bulk verify modal should contain "1 Eligible Remittance"
