Feature: Document
  Can create and view a document as a company

Scenario Outline: Create new document
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given the entity has a folder "name=Test Folder"
  And I am at the documents page
  When I create a new document "<document>"
  Then I should see the "Document was successfully saved"
  And an document should be created
  And I should see the document details on the details page
  And I should see the document in all documents page

  Examples:
  	|user	    |entity               |document                                     |
  	|  	        |entity_type=Company  |name=Q1 Summary;download=true;printing=false |
    |  	        |entity_type=Company  |name=Strategy;download=true;printing=true    |

Scenario Outline: Create document with as_of date shows in the document grid
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given the entity has a folder "name=Test Folder"
  And I am at the documents page
  When I create a new document "<document>" with as_of "<as_of>"
  Then I should see the "Document was successfully saved"
  And the document should have as_of date "<as_of>"
  And the document grid should show the as_of date for the document

  Examples:
    |user  |entity               |document                                      |as_of      |
    |      |entity_type=Company  |name=Q1 Statement;download=true;printing=false|2025-03-31 |
    |      |entity_type=Company  |name=Annual Report;download=false;printing=true|2024-12-31 |

Scenario Outline: Check Document File validation
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given the entity has a folder "name=Test Folder"
  And I am at the documents page
  When I create a new document "<document>" with no file
  Then I should see the document file validation error on creation
  Given I click on "Close"
  Given I upload a valid file for the document
  And I click on "Save"
  Then I should see the "Document was successfully saved"
  Given I go to edit the document
  And I fill the document form
  And I click on "Save"
  Then I should see the "Document was successfully saved"
  Given I remove the file from the document
  Given I go to edit the document
  And I fill the document form
  And I click on "Save"
  Then I should see the document file validation error on update
  Given I upload a valid file for the document
  And I click on "Save"
  Then I should see the "Document was successfully saved"
  And I should see the document details on the details page
  And I should see the document in all documents page

  Examples:
  	|user	    |entity               |document                                     |
    |  	        |entity_type=Company  |name=Strategy;download=true;printing=true    |


Scenario Outline: Create new document with folder access
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given the entity has a folder "name=Test Folder"
  Given the folder has access rights "<access_rights>"
  And I am at the documents page
  When I create a new document "<document>" in folder "Test Folder"
  Then I should see the "Document was successfully saved"
  And an document should be created
  Then the document should have the same access rights as the folder

  Examples:
  	|user	    |entity               |document                   |access_rights	|
  	|  	      |entity_type=Company  |name=Q1 Summary|access_type=Folder;access_to_category=Lead Investor|
    |  	      |entity_type=Company  |name=Strategy  |access_type=Folder;access_to_category=Board|

Scenario Outline: Create new document with folder access later
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given the entity has a folder "name=Test Folder"
  Given the entity has a child folder "name=Child Folder"
  And I am at the documents page
  When I create a new document "<document>" in folder "Child Folder"
  Then I should see the "Document was successfully saved"
  And an document should be created
  Given the folder has access rights "<access_rights>"
  Then the document should have the same access rights as the folder

  Examples:
  	|user	    |entity               |document                   |access_rights	|
  	|  	      |entity_type=Company  |name=Q1 Summary|access_type=Folder;access_to_category=Lead Investor;cascade=true|
    |  	      |entity_type=Company  |name=Strategy  |access_type=Folder;access_to_category=Board;cascade=true|

Scenario Outline: Add deal document
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And there exists a deal "<deal>" for my company
  Given there is an existing investor "" with "1" users
  Given the investors are added to the deal
  And I visit the deal details page
  When I click the last "Documents" link
  When I create a new document "<document>" in folder "Overview"
  And an document should be created
  And an email must go out to the investors for the document
  And the deal document details must be setup right
  And I visit the deal details page
  When I click the last "Documents" link
  And I should see the document in all documents page

Examples:
  	|user	      |entity               |deal          |document	       |
  	|  	        |entity_type=Company  |name=Series A |name=Deal Summary;send_email=true|
    |  	        |entity_type=Company  |name=Series B |name=Deal Details;send_email=true|

Scenario Outline: Add deal investor document
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And there exists a deal "<deal>" for my company
  Given there is an existing investor ""
  And there are "1" deal_investors for the deal
  And I visit the deal investor details page
  When I create a new document "<document>"
  And an document should be created
  And the deal investor document details must be setup right
  And I visit the deal investor details page
  And I should see the document in all documents page

Examples:
  	|user	      |entity               |deal          |document	       |
  	|  	        |entity_type=Company  |name=Series A |name=Deal Summary|
    |  	        |entity_type=Company  |name=Series B |name=Deal Details|


Scenario Outline: Add Sale documents
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the sales page
  Given there is a sale "<sale>"
  Given there is an existing investor "" with "1" users
  Given the investors are added to the sale
  When I visit the sale details page
  When I click the tab "Documents"
  When I create a new document "<document>"
  And an document should be created
  And an email must go out to the investors for the document
  And the sale document details must be setup right
  And I visit the sale details page
  When I click the tab "Documents"
  And I should see the document in all documents page


  Examples:
  	|user	      |entity               |sale             |document	|
  	|  	        |entity_type=Company  |name=Grand Sale  |name=Doc1111;send_email=true|
    |  	        |entity_type=Company  |name=Winter Sale |name=Doc2222;send_email=true|


Scenario Outline: Add Offer documents
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a sale "<sale>"
  Given there is an existing investor "" with "1" users
  Given the investors are added to the sale
  Given there are offers "quantity=50;approved=true" for the sale
  When I visit the offer details page
  When I click the tab "Documents"
  When I create a new document "<document>"
  And an document should be created
  Then the offer document details must be setup right
  And I visit the offer details page
  When I click the tab "Documents"
  And I should see the document in all documents page

  Examples:
  	|user	      |entity               |sale             |document	|
  	|  	        |entity_type=Company  |name=Grand Sale  |name=Doc1111|
    |  	        |entity_type=Company  |name=Winter Sale |name=Doc2222|


Scenario Outline: Add Interest documents
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a sale "<sale>"
  Given there is an existing investor "" with "1" users
  Given the investors are added to the sale
  Given there are offers "quantity=50;approved=true" for the sale
  Given there are "1" interests "quantity=50;short_listed_status=short_listed" for the sale
  When I visit the interest details page
  When I click the tab "Documents"
  When I create a new document "<document>"
  And an document should be created
  Then the interest document details must be setup right
  When I visit the interest details page
  When I click the tab "Documents"
  And I should see the document in all documents page

  Examples:
  	|user	      |entity               |sale             |document	|
  	|  	        |entity_type=Company  |name=Grand Sale  |name=Doc1111|
    |  	        |entity_type=Company  |name=Winter Sale |name=Doc2222|

Scenario Outline: Esignature for a Fund Documeent
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "name=Test fund" for the entity
  And user goes to add a new template "<document>" for the fund
  Then user should be able to add esignatures
  Then user should be able to add estamp_stamps
  Then user should be able to save the document

Examples:
  |user	    |entity                       |document   |
  |  	      |entity_type=Investment Fund  |test doc   |

# Scenario Outline: Template disabled unless owner present
#   Given Im logged in as a user "<user>" for an entity "<entity>"
#   Given the user has role "company_admin"
#   Given there is a fund "name=Test fund" for the entity
#   And user goes to add a new document "<document>" for the fund
#   Then the template checkbox is not present

# Examples:
#   |user	    |entity                       |document   |
#   |  	      |entity_type=Investment Fund  |test doc   |

Scenario Outline: Template enabled even if owner is not present
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "name=Test fund" for the entity
  And user goes to add a new document "<document>" for the fund
  Then user should be able to add esignatures without label list
  Then user should be able to add estamp_stamps
  Then user should be able to save the document

Examples:
  |user	    |entity                       |document   |
  |  	      |entity_type=Investment Fund  |test doc   |

@notification
Scenario Outline: Send a document as Custom Notification
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "name=Test fund" for the entity
  And user goes to add a new document "<document>" for the fund
  Then user should be able to save the document
  Given there is a Custom Notification for the entity
  Then user sends a single document using that Custom Notification
  Then user recieves the document in email with a custom notification template

Examples:
  |user     |entity                       |document   |
  |         |entity_type=Investment Fund  |test doc   |

@notification
Scenario: Send a document as Custom Notification with placeholders
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=Test fund" for the entity
  And user goes to add a new document "test doc" for the fund
  Then user should be able to save the document
  Given there is a Custom Notification with placeholders for the entity
  Then user sends a single document using that Custom Notification
  Then the document notification placeholders are resolved correctly

@notification
Scenario: Send a document owned by a capital commitment with placeholders resolved via the commitment
  Given there is a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is a fund "name=Test fund" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  And the first commitment has an investor kyc with full_name "Jane Commitment Investor" and folio_id "FOLIO-99"
  And there is a document "Commitment Statement" owned by the commitment with file "CapHive - GST Certificate.pdf"
  Given there is a Custom Notification with commitment placeholders for the entity
  When the commitment document is sent using that Custom Notification
  Then the document notification commitment placeholders are resolved correctly

@notification
Scenario: Send a document owned by a capital commitment is cc'd to the commitment's cc address
  Given there is a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is a fund "name=Test fund" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
  And Given the commitments have a cc "advisor@gmail.com"
  And the first commitment has an investor kyc with full_name "Jane Commitment Investor" and folio_id "FOLIO-99"
  And there is a document "Commitment Statement" owned by the commitment with file "CapHive - GST Certificate.pdf"
  Given there is a Custom Notification with commitment placeholders for the entity
  When the commitment document is sent using that Custom Notification
  Then the commitment document notification email is cc'd to "advisor@gmail.com"
