Feature: Embedded eSigning signing page
  A signer who can sign opens a CapHive page that hosts Digio's signing panel and starts it with an explicit
  click. The page is identical on a phone, never carries a token, and refuses everyone who cannot sign.
  (openspec/changes/embedded-esign-digio, design.md#worked-examples H2, H3, E5, E6, E9, E11-E15, E19)

  Background:
    Given Orion Capital has sent the "Subscription Agreement" for eSignature to Priya, Rahul and Vikram

  Scenario: H2 - The signing page shows the signer's context
    Given the Digio panel stub is installed
    When I open the agreement as "priya@lpfund.com"
    And I press "Sign now" in the embedded signing flow
    Then I should see the signing page for "Subscription Agreement" signing as "priya@lpfund.com"
    And I should see the signer place "Signer 1 of 3 - Investor Signatory" and the method "Aadhaar eSign"
    And I should see the buttons "Start signing" and "Back to document"

  Scenario: H3 - Start signing opens the panel with the document and the signer only
    Given the Digio panel stub is installed
    When I open the agreement as "priya@lpfund.com"
    And I press "Sign now" in the embedded signing flow
    And I press "Start signing" in the embedded signing flow
    Then the Digio panel should have been started with document "DID2312191801389959UDGNBWGRGCSC1" and signer "priya@lpfund.com"
    And the Digio panel should have been created for the "sandbox" environment in an iframe

  Scenario: E11 - A non-signer cannot open the signing page by its address
    Given there is another investor user "someone.else@otherlp.com"
    When I open the signing page of "priya@lpfund.com" as "someone.else@otherlp.com"
    Then I should be refused with "This signature request is not available for your account."
    And I should not see the text "Subscription Agreement"

  Scenario: E12 - A signer who has already signed is told so
    Given Priya has signed
    When I open the signing page of "priya@lpfund.com" as "priya@lpfund.com"
    Then I should see the signing message "You have already signed this document."
    And I should not see the button "Start signing"

  Scenario: E13 - The panel cannot be loaded
    Given the Digio script cannot be loaded
    When I open the agreement as "priya@lpfund.com"
    And I press "Sign now" in the embedded signing flow
    And I press "Start signing" in the embedded signing flow
    Then I should see the signing message "We couldn't load the signing panel. Please check your connection and try again, or use the link in the email from Digio."
    And the page should offer "Try again" again

  Scenario: E14 - The same flow on a phone-width screen
    Given the browser is phone width
    And the Digio panel stub is installed
    When I open the agreement as "priya@lpfund.com"
    And I press "Sign now" in the embedded signing flow
    And I press "Start signing" in the embedded signing flow
    Then the Digio panel should have been started with document "DID2312191801389959UDGNBWGRGCSC1" and signer "priya@lpfund.com"

  Scenario: E15 - The request to Digio asks for no access token
    When the agreement is sent to Digio
    Then the request to Digio should not ask for an access token

  Scenario: E19 - The sandbox panel is used in a sandbox environment
    Given the Digio panel stub is installed
    When I open the agreement as "priya@lpfund.com"
    And I press "Sign now" in the embedded signing flow
    Then Digio's script should have been requested from "https://ext.digio.in/sdk/v11/digio.js"

  Scenario: E5 - A support user impersonating the signer is refused on the signing page
    When a support user impersonates "priya@lpfund.com" and requests the signing page
    Then the impersonated request should be refused

  Scenario: E6 - A cancelled document shows it is no longer waiting for signatures
    Given the agreement was cancelled
    When I open the signing page of "priya@lpfund.com" as "priya@lpfund.com"
    Then I should see the signing message "This document is no longer waiting for signatures."
    And I should not see the button "Start signing"

  Scenario: E9 - Out of turn the signing page offers no way to start
    When I open the signing page of "rahul@orioncap.com" as "rahul@orioncap.com"
    Then I should see the signing message "It isn't your turn to sign yet. You'll be able to sign after the previous signer has signed."
    And I should not see the button "Start signing"
