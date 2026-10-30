Feature: Signers are told when it is their turn
  A signer who is a platform user, for an entity with Embedded eSigning on, gets a bell entry and an email when it
  becomes their turn to sign, once per signature request. Nothing here can fail a send or a webhook.
  (openspec/changes/embedded-esign-digio, design.md#worked-examples H9, H10, E29-E35, X12)

  Background:
    Given Orion Capital has approved the "Subscription Agreement" for Priya, Rahul and Vikram but not yet sent it
    And Digio accepts the document
    And Digio's status shows:
      | signer             | status    |
      | priya@lpfund.com   | requested |
      | rahul@orioncap.com | requested |
      | vikram@lawfirm.in  | requested |
    And support alerts are captured

  Scenario: H9 - The first signer is notified when the document is sent
    When Meera sends the agreement for eSignature
    Then "priya@lpfund.com" should have the bell entry "Your signature is requested: Subscription Agreement from Orion Capital"
    And "priya@lpfund.com" should have received the email "Your signature is requested: Subscription Agreement"
    And "rahul@orioncap.com" should have no signing notifications
    And "vikram@lawfirm.in" should have no signing notifications
    And the signer "priya@lpfund.com" should be marked as notified
    And the email gate for "priya@lpfund.com" should be open

  Scenario: H10 - The next signer is notified when the earlier signature is confirmed
    Given Meera has sent the agreement for eSignature
    And Digio's status shows:
      | signer             | status    |
      | priya@lpfund.com   | signed    |
      | rahul@orioncap.com | requested |
      | vikram@lawfirm.in  | requested |
    When the status check runs for the agreement
    Then "rahul@orioncap.com" should have the bell entry "Your signature is requested: Subscription Agreement from Orion Capital"
    And "rahul@orioncap.com" should have received the email "Your signature is requested: Subscription Agreement"
    And "priya@lpfund.com" should have 1 signing notification
    And "vikram@lawfirm.in" should have no signing notifications

  Scenario: E29 - An unordered document notifies every pending signer who is a user
    Given the agreement does not enforce a signing order
    When Meera sends the agreement for eSignature
    Then "priya@lpfund.com" should have 1 signing notification
    And "rahul@orioncap.com" should have 1 signing notification
    And "vikram@lawfirm.in" should have no signing notifications

  Scenario: E30 - Nobody is notified when the switch is off
    Given Embedded eSigning is "off" for Orion Capital
    When Meera sends the agreement for eSignature
    Then "priya@lpfund.com" should have no signing notifications
    And "rahul@orioncap.com" should have no signing notifications
    And no signing email should have been sent

  Scenario: E31 - The notification opens the signing page
    Given the Digio panel stub is installed
    And Meera has sent the agreement for eSignature
    When "priya@lpfund.com" opens the bell entry
    Then I should be on the signing page of "priya@lpfund.com"
    And the bell entry of "priya@lpfund.com" should be read
    And the email to "priya@lpfund.com" should link to the signing page and say Digio's link also works

  Scenario: E32 - A signature confirmed twice notifies the next signer once
    Given Meera has sent the agreement for eSignature
    When Digio posts a "doc.signed" notification with signers:
      | signer             | status    |
      | priya@lpfund.com   | signed    |
      | rahul@orioncap.com | requested |
      | vikram@lawfirm.in  | requested |
    And Digio posts a "doc.signed" notification with signers:
      | signer             | status    |
      | priya@lpfund.com   | signed    |
      | rahul@orioncap.com | requested |
      | vikram@lawfirm.in  | requested |
    And Digio's status shows:
      | signer             | status    |
      | priya@lpfund.com   | signed    |
      | rahul@orioncap.com | requested |
      | vikram@lawfirm.in  | requested |
    And the status check runs for the agreement
    Then "rahul@orioncap.com" should have 1 signing notification
    And "rahul@orioncap.com" should have received 1 signing email

  Scenario: E33 - Re-sending notifies the signers again
    Given Meera has sent the agreement for eSignature
    And Priya has signed and the status was confirmed
    And Digio's status shows:
      | signer             | status    |
      | priya@lpfund.com   | requested |
      | rahul@orioncap.com | requested |
      | vikram@lawfirm.in  | requested |
    When Meera re-sends the agreement for eSignature
    Then "priya@lpfund.com" should have 2 signing notifications
    And the signer "priya@lpfund.com" should be marked as notified

  Scenario: E34 - An investor without email access gets the bell entry only
    Given Priya's investor access has email turned off
    When Meera sends the agreement for eSignature
    Then "priya@lpfund.com" should have 1 signing notification
    And the email gate for "priya@lpfund.com" should be closed

  Scenario: E35 - Switching on does not notify for a document already sent
    Given Embedded eSigning is "off" for Orion Capital
    And Meera has sent the agreement for eSignature
    When Embedded eSigning is "on" for Orion Capital
    Then "priya@lpfund.com" should have no signing notifications
    When Digio's status shows:
      | signer             | status    |
      | priya@lpfund.com   | signed    |
      | rahul@orioncap.com | requested |
      | vikram@lawfirm.in  | requested |
    And the status check runs for the agreement
    Then "rahul@orioncap.com" should have 1 signing notification
    And "priya@lpfund.com" should have no signing notifications

  Scenario: X12 - A notification failure does not block sending or webhooks
    Given the notifier raises when it is used
    When Meera sends the agreement for eSignature
    Then the agreement should be "requested"
    And support should have been alerted about "notifier down"
    When Digio posts a "doc.signed" notification with signers:
      | signer             | status    |
      | priya@lpfund.com   | signed    |
      | rahul@orioncap.com | requested |
      | vikram@lawfirm.in  | requested |
    Then Digio should have been answered successfully
    And the signer "priya@lpfund.com" should be "signed"
    And support should have been alerted about "notifier down"
