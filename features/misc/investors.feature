Feature: Investor
  Can create and view an investor as a company

Scenario Outline: Create new investor
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the investor page
  When I create a new investor "<investor>"
  Then I should see the "<msg>"
  And an investor should be created
  And an investor entity should be created
  And I should see the investor details on the details page

  Examples:
  	|user	      |entity               |investor     |msg	|
  	|  	        |entity_type=Company  |category=LP |Investor was successfully created|
    |  	        |entity_type=Company  |category=LP |Investor was successfully created|

Scenario Outline: Investor email validation error
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the investor page
  When I create a new investor "<investor>"
  Then I should see the "<msg>"

  Examples:
  	|user	      |entity               |investor     |msg	|
    |  	        |entity_type=Company  |category=LP;primary_email=abcg@gmail.com,xyz@yahoo.com |cannot contain commas, colons, or semicolons|
    |  	        |entity_type=Company  |category=LP;primary_email=abcg@gmail.com:xyz@yahoo.com |cannot contain commas, colons, or semicolons|

Scenario Outline: Create new investor
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the investor page
  When I create a new investor "<investor>"
  Then I should see the "<msg>"
  And an investor should be created
  And an investor entity should be created
  And I should see the investor details on the details page

  Examples:
  	|user	      |entity               |investor     |msg	|
  	|  	        |entity_type=Company  |category=LP |Investor was successfully created|
    |  	        |entity_type=Company  |category=LP |Investor was successfully created|


Scenario Outline: Update investor
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the investor page
  When I create a new investor "<investor>"
  When I update the investor "<investor_update>"
  Then I should see the "<msg>"
  Then I should see the investor details on the details page

  Examples:
  	|user	      |entity               |investor    | investor_update  | msg	|
  	|  	        |entity_type=Company  |category=LP | tag_list=Cool    | Investor was successfully updated|
    |  	        |entity_type=Company  |category=LP | tag_list=Cool    | Investor was successfully updated|

Scenario Outline: Send KYC notification
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the investor page
  When I create a new investor "<investor>"
  Then I should see the "<msg>"
  And an investor should be created
  And an investor entity should be created
  And I should see the investor details on the details page
  And I can send KYC reminder to approved users
  Then Notifications are created for KYC Reminders

  Examples:
    |user	      |entity               |investor     |msg	|
    |  	        |entity_type=Company  |name=valory |Investor was successfully created|

Scenario Outline: Send KYC notification error
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the investor page
  When I create a new investor "<investor>"
  Then I should see the "<msg>"
  And an investor should be created
  And an investor entity should be created
  And I should see the investor details on the details page
  And I cannot send KYC reminder as no approved users are present

  Examples:
    |user	      |entity               |investor     |msg	|
    |  	        |entity_type=Company  |name=Radiant |Investor was successfully created|


Scenario Outline: Create new investor from exiting entity
  Given Im logged in as a user "first_name=Mohith" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor entity "<investor>"
  And I am at the investor page
  When I create a new investor "<investor>" for the existing investor entity
  Then I should see the "<msg>"
  And an investor should be created
  And an investor entity should not be created
  And I should see the investor details on the details page

  Examples:
  	|entity              |investor                         |msg	|
  	|entity_type=Company |investor_name=Accelo;primary_email=a@b.c   |Investor was successfully created|
    |entity_type=Company |investor_name=Bearings;primary_email=a@b.c |Investor was successfully created|

@import
Scenario Outline: Import investor access
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
  Given the user has role "company_admin"
  And Given I upload an investors file for the company
  And Given I upload an investor access file for employees
  Then I should see the "Import in progress"
  Then There should be "7" investor access created
  And the investor accesses must have the data in the sheet

@import
Scenario Outline: Import investor kycs
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And Given I upload an investors file for the company
  And the investors have approved investor access
  And Given I upload an investor kyc "investor_kycs.xlsx" for employees
  Then I should see the "Import in progress"
  Then There should be "4" investor kycs created
  And the investor kycs must have the data in the sheet "investor_kycs.xlsx"
  And the imported data must have the form_type updated
  And the approved investor access should receive a notification
  And Given I upload an investor kyc "investor_kycs_update.xlsx" for employees
  Then I should see the "Import in progress"
  Then There should be "4" investor kycs created
  And the investor kycs must have the data in the sheet "investor_kycs_update.xlsx"

Scenario Outline: Bulk Actions on kycs
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And Given I upload an investors file for the company
  And the investors have approved investor access
  And Given I upload an investor kyc "investor_kycs.xlsx" for employees
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

@import
Scenario Outline: Import investors
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
  Given the user has role "company_admin"
  And Given I upload an investors file for the company
  Then I should see the "Import in progress"
  Then There should be "6" investors created
  And the investors must have the data in the sheet
  And Given import file "investors update.xlsx" for "Investor"
  And the investors must have the data in the sheet

@import
Scenario Outline: Import Fund investors
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=Tech Fund" for the entity
  And Given I upload an investors file for the fund
  Then There should be "6" investors created
  And the investors must have the data in the sheet
  And the investors must be added to the fund

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


Scenario: Investor Entity Update
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the deals page
  When I have Boards Permissions
  When I create a new deal "<deal>"
  Then I should see the "<msg>"
  And an deal should be created
  Given I click on the Add Item and create a new Stakeholder "investor_name=Good Investor;primary_email=goodinv@email.com" and save
  Given I click on the Add Item and select "<investor1>" Investor and save
  Given I give deal access to "<investor1>"
  Given Investor "Good Investor" has a user with email "good1@email.com"
  Given the investor has investor notice entry
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor"
  And I update the investors investor entity id
  Then investor entity id should be updated in expected objects


  Examples:
  |user	      |entity               |deal                             |msg	| investor1 |
  |  	        |entity_type=Company  |name=Series A;amount_cents=10000 |Deal was successfully created|Good Investor|
