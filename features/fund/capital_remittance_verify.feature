Feature: Capital Remittance Verify Confirmation Popup
  When a user clicks "Verify" on a capital remittance, the confirmation popup
  displays contextual warnings based on the capital call's notification settings
  and whether the collected amount matches the call amount.

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
    Given the remittances are paid at 80 percent of the call amount
    When I click verify on the first remittance
    Then the verify confirmation popup should contain "The collected amount is less than the call amount. Are you sure you want to verify the remittance?"
    And I proceed with the remittance verification


  Scenario: Verify popup shows over-collected warning when collected is more than call amount
    Given there is a capital call "percentage_called=20;send_payment_notification_flag=true"
    Then the corresponding remittances should be created
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
    Given the remittances are paid
    Given the first remittance is verified
    When I click unverify on the first remittance
    Then the verify confirmation popup should contain "Mark as Unverified?"
    And the verify confirmation popup should not contain "This will confirm the payment amount"
    And I proceed with the remittance verification


  # Business rule: verifying is blocked once the call is unapproved and nothing has been
  # collected yet (see CapitalRemittance#verified_requires_approval_or_collection). The
  # dropdown item renders as a disabled, tooltipped span instead of a clickable button.
  Scenario: Verify is greyed out when the call is not approved and nothing has been collected
    Given there is a capital call "percentage_called=20"
    Then the corresponding remittances should be created
    Then the Verify option should be disabled for the first remittance with tooltip "Cannot verify: the call is not approved and no amount has been collected for this remittance yet."


  # Verify popup surfaces CapitalRemittance#payment_notification_blocked_reasons — here the
  # call is unapproved (default) but the remittance has been paid, so Verify itself is
  # allowed, yet the payment-confirmation email would not go out.
  Scenario: Verify popup explains that no payment confirmation will be sent when the call is not approved
    Given there is a capital call "percentage_called=20;send_payment_notification_flag=true"
    Then the corresponding remittances should be created
    Given the remittances are paid
    When I click verify on the first remittance
    Then the verify confirmation popup should contain "NOT send a notification to the investor because the call is not approved"
    And I proceed with the remittance verification


  # Verifying is a hard precondition for fund unit allocation (DefaultUnitAllocationEngine);
  # the Verify popup should say so whenever the call has unit pricing configured.
  Scenario: Verify popup mentions fund unit eligibility when the call has unit prices configured
    Given there is a capital call "percentage_called=20;send_payment_notification_flag=true"
    And the capital call has unit prices configured
    Then the corresponding remittances should be created
    Given the remittances are paid
    When I click verify on the first remittance
    Then the verify confirmation popup should contain "Once verified, this remittance becomes eligible for fund unit allocation."
    And I proceed with the remittance verification
