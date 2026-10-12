Feature: Capital Remittance Verify Confirmation Popup
  Verifying a capital remittance requires the capital call to be approved first — the
  "Verify" action renders as a disabled/greyed-out item otherwise. Once available, its
  confirmation popup displays contextual warnings based on the capital call's notification
  settings and whether the collected amount matches the call amount.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the user has role "company_admin"
    Given there is an existing investor "investor_name=Investor 1" with "1" users
    Given there is a fund "name=TestFund;currency=INR" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor


  Scenario Outline: Verify popup shows correct notification message based on Send Payment Notification flag
    Given there is a capital call "percentage_called=20;send_payment_notification_flag=<notification_flag>"
    Then the corresponding remittances should be created
    Given the capital calls are approved
    Given the remittances are paid
    When I click verify on the first remittance
    Then the verify confirmation popup should contain "<expected_text>"
    And I proceed with the remittance verification

    Examples:
      | notification_flag | expected_text                                                                                                                             |
      | true              | This will confirm the payment amount as recorded and send a notification for the collected amount to the investor                         |
      | false             | This will confirm the payment amount as recorded but NOT send a notification to the investor because the call is set up to not send payment notifications |


  Scenario: Verify popup shows under-collected warning when collected is less than call amount
    Given there is a capital call "percentage_called=20;send_payment_notification_flag=true"
    Then the corresponding remittances should be created
    Given the capital calls are approved
    Given the remittances are paid at 80 percent of the call amount
    When I click verify on the first remittance
    Then the verify confirmation popup should contain "The collected amount is less than the call amount. Are you sure you want to verify the remittance?"
    And I proceed with the remittance verification


  Scenario: Verify popup shows over-collected warning when collected is more than call amount
    Given there is a capital call "percentage_called=20;send_payment_notification_flag=true"
    Then the corresponding remittances should be created
    Given the capital calls are approved
    Given the remittances are paid at 120 percent of the call amount
    When I click verify on the first remittance
    Then the verify confirmation popup should contain "The collected amount is more than the call amount. Are you sure you want to verify the remittance?"
    And I proceed with the remittance verification


  Scenario: Verify popup shows no amount warning when collected equals call amount exactly
    Given there is a capital call "percentage_called=20;send_payment_notification_flag=true"
    Then the corresponding remittances should be created
    Given the capital calls are approved
    Given the remittances are paid
    When I click verify on the first remittance
    Then the verify confirmation popup should contain "This will confirm the payment amount as recorded and send a notification"
    And the verify confirmation popup should not contain "Are you sure you want to verify the remittance?"
    And I proceed with the remittance verification


  Scenario: Unverify popup shows simple confirmation message without warning text
    Given there is a capital call "percentage_called=20;send_payment_notification_flag=true"
    Then the corresponding remittances should be created
    Given the capital calls are approved
    Given the remittances are paid
    Given the first remittance is verified
    When I click unverify on the first remittance
    Then the verify confirmation popup should contain "Mark as Unverified?"
    And the verify confirmation popup should not contain "This will confirm the payment amount"
    And I proceed with the remittance verification


  # Business rule: verifying strictly requires the call to be approved — see
  # CapitalRemittance#verified_requires_approval. The dropdown item renders as a disabled,
  # tooltipped span instead of a clickable button. Unlike the previous rule, an already-paid
  # remittance on an unapproved call is ALSO blocked — there's no collected-amount exception.
  Scenario: Verify is greyed out when the call is not approved, even if fully paid
    Given there is a capital call "percentage_called=20"
    Then the corresponding remittances should be created
    Given the remittances are paid
    Then the Verify option should be disabled for the first remittance with tooltip "Cannot verify: the call is not approved."


  # Verifying is a hard precondition for fund unit allocation (DefaultUnitAllocationEngine);
  # the Verify popup should say so whenever the call has unit pricing configured.
  Scenario: Verify popup mentions fund unit eligibility when the call has unit prices configured
    Given there is a capital call "percentage_called=20;send_payment_notification_flag=true"
    And the capital call has unit prices configured
    Then the corresponding remittances should be created
    Given the capital calls are approved
    Given the remittances are paid
    When I click verify on the first remittance
    Then the verify confirmation popup should contain "Once verified, this remittance becomes eligible for fund unit allocation."
    And I proceed with the remittance verification


  # The payments upload carries Verified once per payment row, but the flag belongs to the
  # remittance, so two rows for one folio can disagree. The importer used to keep whichever row came
  # last, silently, so a stray "No" under a "Yes" cancelled a verification with nothing to show for
  # it. Now the remittance is left unverified — the recoverable direction, since verifying emails
  # investors and releases unit allocation — and both the row and the import say why.
  # See ImportCapitalRemittancePayment#record_verified_request.
  @rack_test
  Scenario: Payment rows that disagree about Verified leave the remittance unverified
    Given there is a capital call "percentage_called=20"
    Then the corresponding remittances should be created
    Given the capital calls are approved
    When I import two payments for the first remittance with Verified "Yes" and "No"
    Then the payments import should succeed with no failed rows
    And both payments should be recorded on the first remittance
    And the imported remittance should not be verified
    And the payments import should warn that the payment rows disagree about Verified
    And the payments import results should mark the verified rows "Success with warnings"


  # Control for the rule above: the same sheet with both rows agreeing still verifies, so the
  # conflict check is not just refusing everything.
  @rack_test
  Scenario: Payment rows that agree on Verified = Yes verify the remittance
    Given there is a capital call "percentage_called=20"
    Then the corresponding remittances should be created
    Given the capital calls are approved
    When I import two payments for the first remittance with Verified "Yes" and "Yes"
    Then the payments import should succeed with no failed rows
    And both payments should be recorded on the first remittance
    And the imported remittance should be verified
