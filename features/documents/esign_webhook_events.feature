Feature: Digio webhook events
  Digio's notifications are read by event type: signed, failed and rejected each have their own effect, an
  event we do not know behaves as before, and Digio is always answered with success.
  (openspec/changes/embedded-esign-digio, design.md#worked-examples H6-H8, E21-E28)

  Background:
    Given Orion Capital has sent the "Subscription Agreement" for eSignature to Priya, Rahul and Vikram
    And support alerts are captured

  Scenario: H6 - A signed notification updates the signer who signed
    When Digio posts a "doc.signed" notification with signers:
      | signer             | status    |
      | priya@lpfund.com   | signed    |
      | rahul@orioncap.com | requested |
      | vikram@lawfirm.in  | requested |
    Then Digio should have been answered successfully
    And the signer "priya@lpfund.com" should be "signed"
    And the signer "rahul@orioncap.com" should be "requested"

  Scenario: H7 - The last signature completes the document
    Given Priya and Rahul have signed
    And the agreement belongs to a fund
    And Digio will return the signed copy
    When Digio posts a "doc.signed" notification with signers:
      | signer             | status |
      | priya@lpfund.com   | signed |
      | rahul@orioncap.com | signed |
      | vikram@lawfirm.in  | signed |
    Then Digio should have been answered successfully
    And the agreement should be "completed"
    And a signed copy of the agreement should have been created

  Scenario: H8 - A rejection marks the signer Rejected and tells support
    When Digio posts a "doc.sign.rejected" notification for "vikram@lawfirm.in"
    Then Digio should have been answered successfully
    And the signer "vikram@lawfirm.in" should be "rejected"
    And the agreement should be "requested"
    And support should have been alerted about "eSign rejected"

  Scenario: E21 - A partially signed document stays waiting
    When Digio posts a "doc.signed" notification with signers:
      | signer             | status    |
      | priya@lpfund.com   | signed    |
      | rahul@orioncap.com | requested |
      | vikram@lawfirm.in  | requested |
    Then the signer "priya@lpfund.com" should be "signed"
    And the agreement should be "requested"

  Scenario: E22 - A failed notification marks the signer failed
    When Digio posts a "doc.sign.failed" notification for "rahul@orioncap.com" with error code "ESP-101"
    Then Digio should have been answered successfully
    And the signer "rahul@orioncap.com" should be "failed"
    And the notification should be recorded in the eSign log

  Scenario: E23 - An event type we do not know is acknowledged and decided by content
    When Digio posts a "doc.expired" notification with signers:
      | signer             | status    |
      | priya@lpfund.com   | signed    |
      | rahul@orioncap.com | requested |
    Then Digio should have been answered successfully
    And the signer "priya@lpfund.com" should be "signed"
    And the signer "rahul@orioncap.com" should be "requested"
    And support should not have been alerted

  Scenario: E24 - A notification with no event type is processed as before
    When Digio posts a notification without an event with signers:
      | signer             | status    |
      | priya@lpfund.com   | signed    |
      | rahul@orioncap.com | requested |
    Then Digio should have been answered successfully
    And the signer "priya@lpfund.com" should be "signed"

  Scenario: E25 - A late rejection cannot undo a signature
    Given Priya has signed
    When Digio posts a "doc.sign.rejected" notification for "priya@lpfund.com"
    Then Digio should have been answered successfully
    And the signer "priya@lpfund.com" should be "signed"
    And the notification should be recorded in the eSign log

  Scenario: E26 - A rejection with no signer list does not fail processing
    When Digio posts a rejection for "vikram@lawfirm.in" that carries no signer list
    Then Digio should have been answered successfully
    And the signer "vikram@lawfirm.in" should be "rejected"

  Scenario: E26b - A rejection-shaped notification without an event does not raise
    When Digio posts a rejection-shaped notification for "vikram@lawfirm.in" without an event
    Then Digio should have been answered successfully
    And the signer "vikram@lawfirm.in" should be "requested"
    And support should have been alerted about "lists no signing_parties"

  Scenario: E27 - A rejection for an email that is not a signer is reported
    When Digio posts a "doc.sign.rejected" notification for "ghost@nowhere.com"
    Then Digio should have been answered successfully
    And support should have been alerted about "signer not found"
    And the signer "priya@lpfund.com" should be "requested"

  Scenario: E28 - A notification for an unknown document is acknowledged and reported
    When Digio posts a notification for the unknown document "DID-DOES-NOT-EXIST"
    Then Digio should have been answered successfully
    And support should have been alerted about "unknown digio document DID-DOES-NOT-EXIST"
    And the signer "priya@lpfund.com" should be "requested"

  Scenario: E28b - A notification that names no document is acknowledged and reported
    When Digio posts a notification without a document
    Then Digio should have been answered successfully
    And support should have been alerted about "eSign webhook not supported"
