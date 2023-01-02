Feature: Deal
  Can create and view a deal as a company

Scenario Outline: Create new deal
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the deals page
  When I create a new deal "<deal>"
  Then I should see the "<msg>"
  And an deal should be created
  And I should see the deal details on the details page
  And I should see the deal in all deals page

  Examples:
  	|user	      |entity               |deal                             |msg	|
  	|  	        |entity_type=Company  |name=Series A;amount_cents=10000 |Deal was successfully created|
    |  	        |entity_type=Company  |name=Series B;amount_cents=12000 |Deal was successfully created|

Scenario Outline: Edit deal
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the deals page
  When I create a new deal "<deal>"
  Then I should see the "<msg>"
  And an deal should be created
  And I should see the deal details on the details page
  When I edit the deal "name=Series X;amount_cents=40000"
  And I should see the deal details on the details page

  Examples:
  	|user	      |entity               |deal                             |msg	|
  	|  	        |entity_type=Company  |name=Series A;amount_cents=10000 |Deal was successfully created|
    |  	        |entity_type=Company  |name=Series B;amount_cents=12000 |Deal was successfully created|

