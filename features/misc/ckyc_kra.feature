Feature: CKYC and KRA Verification

  As an employee or company admin
  I want to verify investor KYC using CKYC and KRA services
  So that I can efficiently onboard investors with verified data

  Background:
    Given an entity with a fund and an investor exists

  @ckyc
  Scenario: Create KYC with CKYC enabled - Successful verification
    Given CKYC is enabled for the entity with a valid FI code
    When I navigate to the new individual KYC page
    And I fill in "PAN" with "ABCDE1234F"
    And I fill in "phone" with "1234567890"
    And I click the "Next" button
    Then I should be on the OTP entry page
    When I enter a valid OTP
    Then I should be on the CKYC/KRA assign page
    And I should see the message "CKYC Data found"
    When I click the "Select CKYC Data" button
    Then I should see the message "Investor kyc was successfully updated"
    And the KYC form should be populated with the CKYC data
    When I save the KYC form
    Then I should be on the KYC details page
    And the page should display the correct KYC details

  @ckyc
  Scenario: Create KYC with CKYC enabled - Continue without verification
    Given CKYC is enabled for the entity with a valid FI code
    When I navigate to the new individual KYC page
    And I fill in "PAN" with "ABCDE1234F"
    And I click the "Continue without CKYC/KRA" button
    Then I should be on the Investor KYC edit page
    And the "PAN" field should be pre-filled with the valid PAN

  @kra
  Scenario: Create KYC with KRA enabled - Successful verification
    Given KRA is enabled for the entity with a valid FI code
    When I navigate to the new individual KYC page
    And I fill in "PAN" with "ABCDE1234F"
    And I fill in "birth_date" with "01/01/1994"
    And I click the "Next" button
    Then I should be on the "KRA result" page
    And I should see the message "KRA Data found"
    When I click the "Select KRA Data" button
    Then I should see the message "Investor kyc was successfully updated"
    And the KYC form should be populated with the KRA data
    When I save the KYC form
    Then I should be on the KYC details page
    And the page should display the correct KYC details

  @ckyc @kra
  Scenario: Create KYC with CKYC and KRA enabled - All inputs provided
    Given CKYC and KRA are enabled for the entity with a valid FI code
    When I navigate to the new individual KYC page
    And I fill in "PAN" with "<pan>"
    And I fill in "birth_date" with "<dob>"
    And I fill in "phone" with "<phone>"
    And I click the "Next" button
    Then I should be on the "KRA result" page
    And I should see the message "KRA Data found"
    Then I click the "Continue to CKYC" button
    Then I should be on the OTP entry page
    When I enter a valid OTP
    Then I should be on the CKYC/KRA assign page
    And I should see the message "CKYC Data found"
    And I should see both "CKYC" and "KRA" data sections
    When I click the "Select CKYC Data" button
    Then the KYC form should be populated with the CKYC data
    When I save the KYC form
    Then I should be on the KYC details page
    And the page should display the correct KYC details
    And I select "Assign CKYC/KRA Data" from the KYC actions menu
    Then I should be on the CKYC/KRA assign page
    When I click the "Select KRA Data" button
    Then the KYC form should be populated with the KRA data
    When I save the KYC form
    Then I should be on the KYC details page
    And the page should display the correct KYC details

    Examples:
        | pan          | dob          | phone          |
        | ABCDE1234F   | 01/01/1995   | 1234567890   |

 @ckyc
  Scenario Outline: Create KYC with CKYC enabled - Input validations
    Given CKYC is enabled for the entity with a valid FI code
    When I navigate to the new individual KYC page
    And I fill in "PAN" with "<pan>"
    And I fill in "phone" with "<phone>"
    And I click the "Next" button
    Then I should be on the Investor KYC edit page
    And I should see the message "<error_message>"

    Examples:
      | pan        | phone      | error_message                         |
      |            | 1234567890 |CKYC/KRA skipped as PAN is not provided         |
      | ABCDE1234F |            | No CKYC/KRA Data found |

  @ckyc
  Scenario: Create KYC with CKYC enabled - Continue without verification
    Given CKYC is enabled for the entity with a valid FI code
    When I navigate to the new individual KYC page
    And I fill in "PAN" with "ABCDE1234F"
    And I click the "Continue without CKYC/KRA" button
    Then I should be on the Investor KYC edit page
    And the "PAN" field should be pre-filled with the valid PAN

  @kra
  Scenario: Create KYC with KRA enabled - Successful verification
    Given KRA is enabled for the entity with a valid FI code
    When I navigate to the new individual KYC page
    And I fill in "PAN" with "ABCDE1234F"
    And I fill in "birth_date" with "01/01/1994"
    And I click the "Next" button
    Then I should be on the "KRA result" page
    And I should see the message "KRA Data found"
    When I click the "Select KRA Data" button
    Then I should see the message "Investor kyc was successfully updated"
    And the KYC form should be populated with the KRA data
    When I save the KYC form
    Then I should be on the KYC details page
    And the page should display the correct KYC details

  @kra
  Scenario Outline: Create KYC with KRA enabled - Input validations
    Given KRA is enabled for the entity with a valid FI code
    When I navigate to the new individual KYC page
    And I fill in "PAN" with "<pan>"
    And I fill in "birth_date" with "<dob>"
    And I click the "Next" button
    Then I should be on the "<page>" page
    And I should see the message "<error_message>"

    Examples:
      | pan          | dob          | error_message                | page |
      |            | 01/01/1995 | CKYC/KRA skipped as PAN is not provided | Investor KYC edit |
      | ABCDE1234F |            | KRA Data could not be fetched as Date Of Birth is missing. | KRA result |

  @ckyc @kra
  Scenario: Create KYC with CKYC and KRA enabled - All inputs provided
    Given CKYC and KRA are enabled for the entity with a valid FI code
    When I navigate to the new individual KYC page
    And I fill in "PAN" with "ABCDE1234F"
    And I fill in "birth_date" with "01/01/1994"
    And I fill in "phone" with "1234567890"
    And I click the "Next" button
    Then I should be on the "KRA result" page
    And I should see the message "KRA Data found"
    And I click the "Continue to CKYC" button
    Then I should be on the OTP entry page
    When I enter a valid OTP
    Then I should be on the CKYC/KRA assign page
    And I should see the message "CKYC Data found"
    And I should see both "CKYC" and "KRA" data sections
    When I click the "Select CKYC Data" button
    Then the KYC form should be populated with the CKYC data
    When I save the KYC form
    Then the page should display the correct CKYC details

  @ckyc
  Scenario: Edit and refetch CKYC data with a new phone number
    Given CKYC is enabled for the entity with a valid FI code
    When I navigate to the new individual KYC page
    And I fill in "PAN" with "ABCDE1234F"
    And I fill in "phone" with "1234567890"
    And I click the "Next" button
    Then I should be on the OTP entry page
    When I enter a valid OTP
    Then I should be on the CKYC/KRA assign page
    And I should see the message "CKYC Data found"
    When I click the "Select CKYC Data" button
    Then I should see the message "Investor kyc was successfully updated"
    And the KYC form should be populated with the CKYC data
    When I save the KYC form
    Then I should be on the KYC details page
    And the page should display the correct KYC details
    When I am on the show page for "ckyc"
    And I click the "Re-fetch" button
    Then I should be on the OTP entry page
    When I enter a valid OTP
    Then I should be on the KYC data show page
    And I should see the message "CKYC Data found"
    And I click the "Edit" button
    Then I should be on the KYC data edit page
    When I fill in kyc data "phone" with "1234567890"
    And I click the "Save" button
    Then I should be on the OTP entry page
    And I should see the message "OTP has been sent to the registered mobile number"
    When I enter a valid OTP
    Then I should be on the KYC data show page
    And I should see the message "CKYC Data found"
    When I navigate to the "Kyc Data" tab for the investor kyc
    And I click the "New CKYC Data" button
    And I fill in kyc data "PAN" with "ABCDE1234A"
    And I fill in kyc data "phone" with "1234567890"
    And I click the "Save" button
    Then I should be on the OTP entry page
    When I enter a valid OTP
    Then I should be on the KYC data show page
    And I should see the message "CKYC Data found"

  @kra
  Scenario: Edit and Refetch KRA data with new DOB
    Given KRA is enabled for the entity with a valid FI code
    When I navigate to the new individual KYC page
    And I fill in "PAN" with "ABCDE1234F"
    And I fill in "birth_date" with "01/01/1994"
    And I click the "Next" button
    Then I should be on the "KRA result" page
    And I should see the message "KRA Data found"
    When I click the "Select KRA Data" button
    Then I should see the message "Investor kyc was successfully updated"
    And the KYC form should be populated with the KRA data
    When I save the KYC form
    Then I should be on the KYC details page
    And the page should display the correct KYC details
    When I am on the show page for "kra"
    And I click the "Re-fetch" button
    Then I should be on the KYC data show page
    And I should see the message "KRA Data found"
    And I click the "Edit" button
    Then I should be on the KYC data edit page
    When I fill in kyc data "birth_date" with "01/01/1998"
    And I click the "Save" button
    Then I should be on the KYC data show page
    And I should see the message "KRA Data was successfully fetched"
    When I navigate to the "Kyc Data" tab for the investor kyc
    And I click the "New KRA Data" button
    And I fill in kyc data "PAN" with "ABCDE1234B"
    And I fill in kyc data "birth_date" with "01/01/1994"
    And I click the "Save" button
    Then I should be on the KYC data show page
    And I should see the message "KRA Data fetched successfully"

  @investor @ckyc @kra
  Scenario: Investor completes KYC process after receiving a request
    And CKYC and KRA are enabled for the entity with a valid FI code
    And the investor has a verified user with KYC permissions
    And I send a KYC request to the investor
    Given I log out
    When I log in as the investor user
    And I follow the KYC link from the email
    Then I should be on the KYC edit page for fetching ckyc/kra data
    When I fill in "PAN" with "ABCDE1234F"
    And I fill in "birth_date" with "01/01/1994"
    And I fill in "phone" with "1234567890"
    And I click the "Next" button
    Then I should be on the "KRA result" page
    And I should see the message "KRA Data found"
    And I click the "Continue to CKYC" button
    Then I should be on the OTP entry page
    When I enter a valid OTP
    Then I should be on the CKYC/KRA assign page
    And I should see the message "CKYC Data found"
    When I click the "Select CKYC Data" button
    Then I should be on the Investor KYC edit page
    Then I fill in the form and it is populated with the CKYC data
    When I save the KYC form
    Then I should be on the KYC details page
    And the page should display the correct CKYC details
    And I go to assign ckyc/kra data
    Then I should be on the CKYC/KRA assign page
    And the "Select CKYC Data" button should be disabled
    And the "Select KRA Data" button should be disabled
    When I click the "Continue without Selecting" button
    Then I should be on the Investor KYC edit page
    When I save the KYC form
    Then I should be on the KYC details page
    And the page should display the original CKYC details

