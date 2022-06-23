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
