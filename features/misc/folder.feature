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
