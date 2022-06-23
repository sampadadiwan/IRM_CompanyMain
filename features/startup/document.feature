Feature: Document
  Can create and view a document as a startup

Scenario Outline: Create new document
  Given Im logged in as a user "<user>" for an entity "<entity>"
  And I am at the documents page
  When I create a new document "<document>"
  Then I should see the "Document was successfully created"
  And an document should be created
  And I should see the document details on the details page
  And I should see the document in all documents page

  Examples:
  	|user	    |entity               |document                                     |
  	|  	        |entity_type=Startup  |name=Q1 Summary;download=true;printing=false |
    |  	        |entity_type=Startup  |name=Strategy;download=true;printing=true    |


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
  	|  	        |entity_type=Startup  |name=Q1 Summary;folder_id=1|access_type=Folder;access_to_category=Lead Investor|
    |  	        |entity_type=Startup  |name=Strategy;folder_id=1  |access_type=Folder;access_to_category=Board|

Scenario Outline: Add deal document
  Given Im logged in as a user "<user>" for an entity "<entity>"
  And there exists a deal "<deal>" for my startup
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
  	|  	        |entity_type=Startup  |name=Series A |name=Deal Summary|
    |  	        |entity_type=Startup  |name=Series B |name=Deal Details|

Scenario Outline: Add deal investor document
  Given Im logged in as a user "<user>" for an entity "<entity>"
  And there exists a deal "<deal>" for my startup
  And there are "1" deal_investors for the deal
  And I visit the deal investor details page
  When I create a new document "<document>"
  And an document should be created
  And the deal investor document details must be setup right
  And I visit the deal investor details page
  And I should see the document in all documents page

Examples:
  	|user	      |entity               |deal          |document	       |
  	|  	        |entity_type=Startup  |name=Series A |name=Deal Summary|
    |  	        |entity_type=Startup  |name=Series B |name=Deal Details|

