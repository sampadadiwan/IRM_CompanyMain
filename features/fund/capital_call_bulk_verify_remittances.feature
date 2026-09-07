Feature: Bulk Verify Remittances from Capital Call Show Page
  A user can bulk-verify all currently unverified remittances for a capital call
  directly from the call's own Remittances tab, via a confirmation popup that
  explains exactly what the action will do. Already-verified remittances must
  never be affected by the bulk action.

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
    Given the remittances are paid


  Scenario: Bulk verify modal explains the action in detail before confirming
    When I open the bulk verify remittances modal for the capital call
    Then the bulk verify modal should contain "Unverified Remittance"
    And the bulk verify modal should contain "Only unverified remittances are affected"
    And the bulk verify modal should contain "Status recalculated, fees unchanged"
    And the bulk verify modal should contain "Payment notifications sent"
    And the bulk verify modal should contain "Runs in the background"
    When I confirm the bulk verify remittances action
    Then all remittances for the capital call should be verified


  Scenario: Bulk verify does not un-verify remittances that were already verified
    Given the first remittance is verified
    When I bulk verify pending remittances for the capital call
    Then all remittances for the capital call should be verified


  Scenario: Bulk verify reports failures for remittances that cannot be saved
    Given the last remittance belongs to a commitment with a zero committed amount
    When I bulk verify pending remittances for the capital call
    Then all remittances except the invalid remittance should be verified
    And a bulk verify error email should be sent listing the invalid remittance


  Scenario: Verify Pending Remittances button is hidden once nothing is left to verify
    Given the remittances are verified
    When I visit the capital call remittances tab
    Then I should not see the "Verify Pending Remittances" button on the remittances tab
