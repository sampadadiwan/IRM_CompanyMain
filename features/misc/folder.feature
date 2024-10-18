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

Scenario Outline: Update a folder's name
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given the entity has a folder "name=Test Folder"
  Then the folder should have no owner
  Then the folder should have no access_rights
  Given the folder has children "<child_folders>"
  And folder "B" has sub-folders "<sub_folders_for_B>"
  Then I update the folder's name
  Then I children folder path should be updated

  Examples:
    |user     |entity               | child_folders | sub_folders_for_B | new_name       |
    |         |entity_type=Company  | A/B/C/D       | B1/B2/B3          | Updated Folder |


Scenario Outline: Create new deal document folder
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the deals page
  When I have Boards Permissions
  When I create a new deal "<deal>"
  Then I should see the "<msg>"
  And an deal should be created
  And an document folder should be present
  Then I edit the name of the deal
  Then Path of folder and children should change

  Examples:
    |user       |entity               |deal                             |msg  |
    |           |entity_type=Company  |name=Series A;amount_cents=10000 |Deal was successfully created|
    |           |entity_type=Company  |name=Series B;amount_cents=12000 |Deal was successfully created|

Scenario Outline: Deal has wrong folder path
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the deals page
  When I have Boards Permissions
  When I create a new deal "<deal>"
  Then I should see the "<msg>"
  And an deal should be created
  And an document folder should be present
  Then I mock the folder path to be wrong
  Then UpdateDocumentFolderPathJob job is triggered
  Then Path of folder and children should change

  Examples:
    |user       |entity               |deal                             |msg  |
    |           |entity_type=Company  |name=Series A;amount_cents=10000 |Deal was successfully created|
    |           |entity_type=Company  |name=Series B;amount_cents=12000 |Deal was successfully created|