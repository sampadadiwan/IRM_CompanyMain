Feature: Digio audit trail
  When every signer has signed, Digio's audit trail is filed beside the signed copy. Digio only hands it over once
  the flow is complete, so it is fetched in the background and tried again. Digio's raw responses stay in the eSign
  log, not on the signer rows.
  (openspec/changes/embedded-esign-digio, design.md#worked-examples H11, E36-E39, X13, X14)

  Background:
    Given Orion Capital has sent the "Subscription Agreement" for eSignature to Priya, Rahul and Vikram
    And support alerts are captured
    And Priya and Rahul have signed

  Scenario: H11 - The audit trail is filed beside the signed copy
    Given the agreement belongs to a fund
    And Digio will return the signed copy
    When Digio confirms the last signature
    Then the agreement should be "completed"
    And a signed copy of the agreement should have been created
    And the audit trail should be filed beside the signed copy
    And support should not have been alerted

  Scenario: E36 - A repeated confirmation files one audit trail
    Given the agreement belongs to a fund
    And Digio will return the signed copy
    When Digio confirms the last signature
    And Digio confirms the last signature
    Then 1 audit trail should be filed
    And Digio should have been asked for the audit trail 1 time

  Scenario: E37 - The audit trail is tried again until Digio has it
    Given the agreement belongs to a fund
    And Digio will return the signed copy
    And Digio will refuse the audit trail 2 times, then hand it over
    When Digio confirms the last signature
    Then the audit trail should be filed beside the signed copy
    And Digio should have been asked for the audit trail 3 times
    And support should not have been alerted

  Scenario: E38 - A document with no owner keeps its signed copy and audit trail in its folder
    Given Digio will return the signed copy
    When Digio confirms the last signature
    Then the agreement should be "completed"
    And the signed copy and the audit trail should be in the agreement's folder

  Scenario: E39 - Digio's responses stay in the eSign log, not on the signer rows
    Given Digio's status shows:
      | signer             | status    |
      | priya@lpfund.com   | signed    |
      | rahul@orioncap.com | signed    |
      | vikram@lawfirm.in  | requested |
    When the status check runs for the agreement
    And Digio posts a "doc.sign.failed" notification for "vikram@lawfirm.in" with error code "ESP-101"
    Then the signer "vikram@lawfirm.in" should be "failed"
    And the status check and the notification should be recorded in the eSign log
    And no signer row should hold Digio's responses

  Scenario: X13 - Support is told when the audit trail never arrives
    Given the agreement belongs to a fund
    And Digio will return the signed copy
    And Digio will always refuse the audit trail
    When Digio confirms the last signature
    Then the agreement should be "completed"
    And a signed copy of the agreement should have been created
    And 0 audit trails should be filed
    And support should have been alerted about "Could not download the audit trail"

  Scenario: X14 - A signed copy that cannot be downloaded does not complete the document
    Given the agreement belongs to a fund
    And Digio cannot return the signed copy
    When Digio confirms the last signature
    Then Digio should have been answered successfully
    And the agreement should be "requested"
    And no signed copy of the agreement should exist
    And support should have been alerted about "Could not download the signed copy"
    Given Digio will return the signed copy
    And Digio's status shows:
      | signer             | status |
      | priya@lpfund.com   | signed |
      | rahul@orioncap.com | signed |
      | vikram@lawfirm.in  | signed |
    When the status check runs for the agreement
    Then the agreement should be "completed"
    And a signed copy of the agreement should have been created
    And the audit trail should be filed beside the signed copy
