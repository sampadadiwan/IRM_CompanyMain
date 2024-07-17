Feature: Folder
  Can create and view a folder as a company

Scenario Outline: Create new folder
  Given there is a user "<user>" for an entity "<entity>"
  Given the entity has a folder "name=Test Folder"
  Then the folder should have no owner
  Then the folder should have no access_rights
  And there exists a deal "name=Test Deal" for my company
  Given there is an existing investor "" with "1" users
  Given the investors are added to the deal
  Then the deal document folder should be created
  Then the deal data room should be created
  Then the deal data room should have the correct access_rights
  Given there is an existing investor "" with "1" users
  Given the investors are added to the deal
  Then the deal data room should have the correct access_rights
  Given there is a child folder in the data room
  Then the child folder should have the correct access_rights
  
  
  Examples:
  	|user	    |entity               |
  	|  	        |entity_type=Company  |
    |  	        |entity_type=Company  |



Scenario Outline: Add and delete cascading access rights to folder
  Given there is a user "<user>" for an entity "<entity>"
  Given the entity has a folder "name=Test Folder"
  Then the folder should have no owner
  Then the folder should have no access_rights
  Given the folder has children "<child_folders>"
  Given each folder has a document 
  When the root folder is given access rights
  Then the child folders should have the same access rights
  And the documents should have the same access rights
  When the root folder access right is deleted
  Then the child folders access_rights should be deleted
  And the documents access_rights should be deleted
  
  Examples:
  	|user	    |entity               | child_folders |
  	|  	        |entity_type=Company  | A/B/C/D |
    |  	        |entity_type=Company  | X/Y/Z   |
