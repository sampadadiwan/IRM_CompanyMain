Feature: Document
  Can create and view a document as a company

Scenario Outline: Create new document
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the entity has a folder "name=Test Folder"
  And I am at the documents page
  When I create a new document "<document>"
  Then I should see the "Document was successfully created"
  And an document should be created
  And I should see the document details on the details page
  And I should see the document in all documents page

  Examples:
  	|user	    |entity               |document                                     |
  	|  	        |entity_type=Company  |name=Q1 Summary;download=true;printing=false |
    |  	        |entity_type=Company  |name=Strategy;download=true;printing=true    |


Scenario Outline: Create new document
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the entity has a folder "name=Test Folder"
  Given the folder has access rights "<access_rights>"
  And I am at the documents page
  When I create a new document "<document>"
  Then I should see the "Document was successfully created"
  And an document should be created
  Then the document should have the same access rights as the folder

  Examples:
  	|user	    |entity               |document                   |access_rights	|
  	|  	      |entity_type=Company  |name=Q1 Summary;folder_id=1|access_type=Folder;access_to_category=Lead Investor|
    |  	      |entity_type=Company  |name=Strategy;folder_id=1  |access_type=Folder;access_to_category=Board|

Scenario Outline: Add deal document
  Given Im logged in as a user "<user>" for an entity "<entity>"
  And there exists a deal "<deal>" for my company
  And I visit the deal details page
  When I click "Deal Docs"
  When I create a new document "<document>"
  And an document should be created
  And the deal document details must be setup right
  And I visit the deal details page
  When I click "Deal Docs"
  And I should see the document in all documents page

Examples:
  	|user	      |entity               |deal          |document	       |
  	|  	        |entity_type=Company  |name=Series A |name=Deal Summary|
    |  	        |entity_type=Company  |name=Series B |name=Deal Details|

Scenario Outline: Add deal investor document
  Given Im logged in as a user "<user>" for an entity "<entity>"
  And there exists a deal "<deal>" for my company
  Given there is an existing investor "name=Sequoia"
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
  And I am at the sales page
  Given there is a sale "<sale>"
  When I visit the sale details page
  When I click the tab "Documents" 
  When I create a new document "<document>"
  And an document should be created
  And the sale document details must be setup right
  And I visit the sale details page
  When I click the tab "Documents"
  And I should see the document in all documents page


  Examples:
  	|user	      |entity               |sale             |document	|
  	|  	        |entity_type=Company  |name=Grand Sale  |name=Doc1111|
    |  	        |entity_type=Company  |name=Winter Sale |name=Doc2222|


Scenario Outline: Add Offer documents
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given there is a sale "<sale>"
  Given there are "1" employee investors
  Given there is a FundingRound "name=Series A"
  And there is a holding "orig_grant_quantity=100;investment_instrument=Equity" for each employee investor
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
  Given there is a sale "<sale>"
  Given there are "1" employee investors
  Given there is a FundingRound "name=Series A"
  And there is a holding "orig_grant_quantity=100;investment_instrument=Equity" for each employee investor
  Given there are offers "quantity=50;approved=true" for the sale
  Given there are "1" interests "quantity=50;short_listed=true" for the sale
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
