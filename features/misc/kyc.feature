Feature: Kyc imports and such

@import
Scenario Outline: Import KYCs - with Form Tag
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C1" for the entity
  Given there is a FormType "name=IndividualKyc;tag=Default" with custom fields "Fathers Name, Mothers Name, Age, Agreement Unit Type,Custom Field 1, Custom field 2"
  Given there is a FormType "name=IndividualKyc;tag=Gift City" with custom fields "Gift City ID, Agreement Unit Type, Custom Field 1, Custom field 2"
  Given there is a FormType "name=NonIndividualKyc;tag=Default" with custom fields "Agreement Unit Type, Custom Field 1, Custom field 2"
  And Given I upload an investors file for the fund
  And Given import file "investor_kycs_with_tags.xlsx" for "InvestorKyc"
  Then There should be "4" investor kycs created
  And the investor kycs must have the data in the sheet "investor_kycs_with_tags.xlsx"
  And there are "2" records for the form type "IndividualKyc"
  And there are "1" records for the form type "NonIndividualKyc"



@import
Scenario Outline: Import KYCs - No Form Tag
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C1" for the entity
  And Given I upload an investors file for the fund
  And Given import file "investor_kycs.xlsx" for "InvestorKyc"
  Then There should be "4" investor kycs created
  And the investor kycs must have the data in the sheet "investor_kycs.xlsx"
  And there are "1" records for the form type "IndividualKyc"
  And there are "1" records for the form type "NonIndividualKyc"

Scenario Outline: Cannot create KYC without Stakeholder
  Given Im logged in as a user "first_name=Testuser" for an entity "name=Urban1;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given the entity has aml enabled "true"
  Given there is an existing investor "investor_name=Investor 11"
  When I navigate to the new "Individual" KYC page
  And I click the "Next" button
  Then I get the error that StakeHolder cant be blank
  Then I select the investor for the KYC
  And I click the "Next" button
  And I click the "Next" button
  And I click the "Save" button
  Then I should see the "Investor kyc was successfully saved"


@import
Scenario Outline: Import investor kycs
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And Given I upload an investors file for the company
  And the investors have approved investor access
  And Given import file "investor_kycs.xlsx" for "InvestorKyc"
  Then I should see the "Import in progress"
  Then There should be "4" investor kycs created
  And the investor kycs must have the data in the sheet "investor_kycs.xlsx"
  And the imported data must have the form_type updated
  And the approved investor access should receive a notification
  And Given import file "investor_kycs_update.xlsx" for "InvestorKyc"
  Then I should see the "Import in progress"
  Then There should be "4" investor kycs created
  And the investor kycs must have the data in the sheet "investor_kycs_update.xlsx"
  And Given import file "import_kyc_docs/test.zip" for "KycDocs"
  Then I should see the documents attached to the correct kycs

Scenario Outline: Bulk Actions on kycs
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And Given I upload an investors file for the company
  And the investors have approved investor access
  And Given import file "investor_kycs.xlsx" for "InvestorKyc"
  Given I filter the "investor_kycs" by "verified=false"
  And I trigger the bulk action for "Verify"
  Then I should see the "Verify completed"
  Then the kycs should be verified
  Given I filter the "investor_kycs" by "verified=true"
  And I trigger the bulk action for "Unverify"
  Then I should see the "Unverify completed"
  Then the kycs should be unverified
  Given I filter the "investor_kycs" by "verified=false"
  And I trigger the bulk action for "Send Reminder"
  Then I should see the "SendReminder completed"
  Then the kycs users should receive the kyc reminder email



Scenario Outline: Create investor kyc - no ckyc
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing investor "investor_name=Investor 1"
  Given I create a new InvestorKyc "PAN=ABCD9876F" with files "Upload PAN / Tax ID,Upload Address Proof,Upload Cancelled Cheque / Bank Statement" for ""
  Then I should see the "Investor kyc was successfully saved."
  And I should see the kyc documents "Upload PAN / Tax ID,Upload Address Proof"
  Then mock UpdateDocumentFolderPathJob job
  Then Folder path should be present and correct
  And when I upload the document for the kyc
  Then I should see the "Document was successfully saved."
  Then I should see the investor kyc details on the details page


Scenario Outline: Create investor kyc
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing investor "name=Investor 1" with "1" users
  Given the investor entity has no "enable_kycs" permissions
  Given a InvestorKyc is created with details "<kyc>" by "<investor_user>"
  And I visit the investor kyc page
  Then I should see the investor kyc details on the details page
  Then the kyc form should be sent "<kyc_form_sent>" to the investor
  And the investor entity should have "enable_kycs" permissions
  And notification should be sent "<kyc_update_notification>" to the employee for kyc update
  And when I Send KYC reminder for the kyc
  Then the kyc form reminder should be sent "true" to the investor

  Examples:
    |kyc_form_sent| kyc                                     | investor_user | kyc_update_notification |
    |true         | PAN=ABCD9870;send_kyc_form_to_user=true | false         | false |
    |false        | PAN=ABCD9876;send_kyc_form_to_user=false| false         | false |
    |false        | PAN=ABCD9876;send_kyc_form_to_user=false| true          | true  |
