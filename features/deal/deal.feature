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
  And the deal data room should be setup

  Examples:
  	|user	      |entity               |deal                             |msg	|
  	|  	        |entity_type=Company;enable_deals=true  |name=Series A;amount_cents=10000 |Deal was successfully created|
    |  	        |entity_type=Company;enable_deals=true  |name=Series B;amount_cents=12000 |Deal was successfully created|

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
  	|  	        |entity_type=Company;enable_deals=true  |name=Series A;amount_cents=10000 |Deal was successfully created|
    |  	        |entity_type=Company;enable_deals=true  |name=Series B;amount_cents=12000 |Deal was successfully created|

Scenario Outline: Currency Units
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the deals page
  When I create a new deal "<deal>"
  Then I should see the "<msg>"
  And an deal should be created
  And I should see the deal in all deals page
  And I should be able to change currency units

  Examples:
    |user	      |entity                                 |deal                                                   |msg	|
    |  	        |entity_type=Company;enable_deals=true  |name=Series R;amount_cents=100000000 |Deal was successfully created|

Scenario: Deal notifications can be toggled from the form
  Given Im logged in as a user "" for an entity "entity_type=Company"
  Given the user has role "company_admin"
  And I am at the deals page
  When I create a new deal "name=Notification Deal;amount_cents=25000"
  Then I should see the "Deal was successfully created"
  And an deal should be created
  And the deal should have notifications enabled
  When I disable deal notifications
  Then I should see the "Deal was successfully updated"
  And the deal should have notifications disabled

Scenario: Deal investor statuses are saved and can be updated
  Given Im logged in as a user "<user>" for an entity "entity_type=Company"
  Given the user has role "company_admin"
  And I am at the deals page
  When I create a new deal "<deal>"
  Then I should see the "<msg>"
  And an deal should be created
  When I edit the deal investor statuses to "Interested, Committed, Closed"
  Then I should see the "<update_msg>"
  And the deal should have investor statuses "Interested, Committed, Closed"
  Examples:
    |user	      |role               |entity                                 |deal                                                                     |msg	                        |update_msg                   |
    |  	        |company_admin      |entity_type=Company;enable_deals=true  |name=Status Deal;amount_cents=36000;deal_investor_status=New, Interested |Deal was successfully created|Deal was successfully updated|
