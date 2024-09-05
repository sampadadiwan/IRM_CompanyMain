Feature: Events
	Creates events affiliated to any module

Scenario Outline: Create an event for deal
	Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the deals page
  When I have Boards Permissions
  When I create a new deal "<deal>"
  Then I should see the "<msg>"
  And an deal should be created
  And I create an event for deal
  And I add an event for today's date
  And I click on the Sample Event and validate the event creation

  Examples:
  	|user	      |entity               |deal                             |msg	|
  	|  	        |entity_type=Company  |name=Series A;amount_cents=10000 |Deal was successfully created|
    |  	        |entity_type=Company  |name=Series B;amount_cents=12000 |Deal was successfully created|