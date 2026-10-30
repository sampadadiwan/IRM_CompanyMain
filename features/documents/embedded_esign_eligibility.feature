Feature: Embedded eSigning eligibility
  A logged-in signer is offered "Sign now" on a document that is waiting for their signature, only when
  Embedded eSigning is on for the document's entity, their login email is the signer's email, and it is
  their turn. (openspec/changes/embedded-esign-digio, design.md#worked-examples H1, E1-E10, E16)

  Background:
    Given Orion Capital has sent the "Subscription Agreement" for eSignature to Priya, Rahul and Vikram

  Scenario: H1 - A matching signer is offered Sign now
    When I open the agreement as "priya@lpfund.com"
    Then I should see the signature banner "Your signature is requested on this document."
    And the banner should have a "Sign now" button

  Scenario: E1 - The email match ignores letter case
    Given the signer "priya@lpfund.com" is stored with the email "Priya@LPFund.com"
    When I open the agreement as "priya@lpfund.com"
    Then the banner should have a "Sign now" button

  Scenario: E2 - A user who is not a signer is not offered anything
    Given there is another investor user "someone.else@otherlp.com"
    When I open the agreement as "someone.else@otherlp.com"
    Then I should not see a signature banner

  Scenario: E3 - Switch off hides everything
    Given Embedded eSigning is "off" for Orion Capital
    When I open the agreement as "priya@lpfund.com"
    Then I should not see a signature banner

  Scenario: E4 - The switch is per entity
    Given Other Co has a similar agreement sent to Priya with Embedded eSigning off
    When I open the agreement of "Orion Capital" as "priya@lpfund.com"
    Then the banner should have a "Sign now" button
    When I open the agreement of "Other Co" as "priya@lpfund.com"
    Then I should not see a signature banner

  Scenario: E5 - A support user impersonating the signer cannot sign
    When a support user impersonates "priya@lpfund.com" and opens the agreement
    Then the impersonated response should not show a signature banner

  Scenario: E6 - A cancelled document is not signable
    Given the agreement was cancelled
    When I open the agreement as "priya@lpfund.com"
    Then I should not see a signature banner

  Scenario: E7 - An employee signer sees Sign now on their own row only
    Given Priya has signed
    And Rahul is a company admin at Orion Capital
    When I open the agreement as "rahul@orioncap.com"
    Then the Signatures tab should offer "Sign now" on the row of "rahul@orioncap.com" only

  Scenario: E8 - A signer whose turn has not come sees the banner without a button
    When I open the agreement as "rahul@orioncap.com"
    Then I should see the signature banner "Your signature is requested on this document. You can sign after the previous signer has signed."
    And the banner should not have a "Sign now" button

  Scenario: E10 - Without a signing order every pending signer can sign
    Given the agreement does not enforce a signing order
    When I open the agreement as "priya@lpfund.com"
    Then the banner should have a "Sign now" button
    When I open the agreement as "rahul@orioncap.com"
    Then the banner should have a "Sign now" button

  Scenario: E16 - Documents sent before the switch was turned on can be signed
    Given Embedded eSigning is "off" for Orion Capital
    And Embedded eSigning is "on" for Orion Capital
    When I open the agreement as "priya@lpfund.com"
    Then the banner should have a "Sign now" button
