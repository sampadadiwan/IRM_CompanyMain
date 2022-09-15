Feature: Approval
  Can create and view a approval as a startup

Scenario Outline: Create new approval
  Given Im logged in as a user "<user>" for an entity "<entity>"
  And I am at the approvals page
  When I create a new approval "<approval>"
  Then I should see the "<msg>"
  And an approval should be created
  And I should see the approval details on the details page
  And I should see the approval in all approvals page

  Examples:
  	|user	    |entity               |approval                 |msg	|
  	|  	        |entity_type=Startup  |title=Test approval      |Approval was successfully created|
    |  	        |entity_type=Startup  |title=MErger Approval    |Approval was successfully created|



Scenario Outline: Edit approval
  Given Im logged in as a user "<user>" for an entity "<entity>"
  And I am at the approvals page
  When I create a new approval "<approval>"
  Then I should see the "<msg>"
  And an approval should be created
  When I edit the approval "title=Updated Title"
  And I should see the approval details on the details page
  And I should see the approval in all approvals page

  Examples:
  	|user	    |entity               |approval                 |msg	|
  	|  	        |entity_type=Startup  |title=Test approval      |Approval was successfully created|
    |  	        |entity_type=Startup  |title=MErger Approval    |Approval was successfully created|


Scenario Outline: Grant Access Rights to approval
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "approver"
  Given there is an existing investor "name=Accel" with "2" users
  Given there is an approval "<approval>" for the entity
  Given the investors are added to the approval  
  When I visit the approval details page
  Then the approval responses are generated with status "Pending"  
  When the approval is approved
  Then the investor gets the approval notification

  Examples:
  	|user	    |entity               |approval                 |msg	|
  	|  	        |entity_type=Startup  |title=Test approval      |Approval was successfully created|
    |  	        |entity_type=Startup  |title=Merger Approval    |Approval was successfully created|
