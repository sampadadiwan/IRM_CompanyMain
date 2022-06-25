Feature: Deal Investor
  Can create and view a deal investor as a startup

Scenario Outline: Create new deal
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given there is an existing investor "name=Sequoia"
  And there exists a deal "<deal>" for my startup
  And I visit the deal details page
  When I create a new deal investor "<deal_investor>"
  Then I should see the "<msg>"
  And a deal investor should be created
  And I should see the deal investor details on the details page
  And I should see the deal investor in all deal investors page

  Examples:
  	|user	      |deal_investor              |entity               |deal                             |msg	|
  	|  	        |primary_amount_cents=10000 |entity_type=Startup  |name=Series A;amount_cents=10000 |Deal investor was successfully created|
    |  	        |primary_amount_cents=12000 |entity_type=Startup  |name=Series B;amount_cents=12000 |Deal investor was successfully created|


Scenario Outline: View Deal Investors in a deal
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given there are "3" existing investor ""
  And there exists a deal "<deal>" for my startup
  And I visit the deal details page
  And when I start the deal
  And there are "3" deal_investors for the deal
  And I should see the deal investors in the deal details page

  Examples:
  	|user	      |deal_investor              |entity               |deal                             |msg	|
  	|  	        |primary_amount_cents=10000 |entity_type=Startup  |name=Series A;amount_cents=10000 |Deal investor was successfully created|
    |  	        |primary_amount_cents=12000 |entity_type=Startup  |name=Series B;amount_cents=12000 |Deal investor was successfully created|



Scenario Outline: View Deal Stages in a deal
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given there is an existing investor "name=Sequoia"
  And there exists a deal "<deal>" for my startup
  And there are "2" deal_investors for the deal
  And I visit the deal details page
  And when I start the deal
  And I visit the deal details page
  And I should see the deal investors in the deal details page
  And I should see the deal stages in the deal details page

  Examples:
  	|user	      |deal_investor              |entity               |deal                             |msg	|
  	|  	        |primary_amount_cents=10000 |entity_type=Startup  |name=Series A;amount_cents=10000 |Deal investor was successfully created|
    |  	        |primary_amount_cents=12000 |entity_type=Startup  |name=Series B;amount_cents=12000 |Deal investor was successfully created|



Scenario Outline: View Deal Stages in a deal
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given there is an existing investor "name=Sequoia"
  And there exists a deal "<deal>" for my startup
  And there are "2" deal_investors for the deal
  And I visit the deal details page
  And when I start the deal
  And the deal activites are completed
  And I visit the deal details page
  And I should see the deal investors in the deal details page
  And I should see the deal stages in the deal details page

  Examples:
  	|user	      |deal_investor              |entity               |deal                             |msg	|
  	|  	        |primary_amount_cents=10000 |entity_type=Startup  |name=Series A;amount_cents=10000 |Deal investor was successfully created|
    |  	        |primary_amount_cents=12000 |entity_type=Startup  |name=Series B;amount_cents=12000 |Deal investor was successfully created|



Scenario Outline: View Deal Stages in a deal
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given there is an existing investor "name=Sequoia"
  And there exists a deal "<deal>" for my startup
  And there are "1" deal_investors for the deal
  And I visit the deal details page
  And when I start the deal
  And I visit the deal details page
  And I complete an activity
  Then the activity must be completed

  Examples:
  	|user	      |deal_investor              |entity               |deal                             |msg	|
  	|  	        |primary_amount_cents=10000 |entity_type=Startup  |name=Series A;amount_cents=10000 |Deal investor was successfully created|
    |  	        |primary_amount_cents=12000 |entity_type=Startup  |name=Series B;amount_cents=12000 |Deal investor was successfully created|


Scenario Outline: Create new deal investor document
  Given there is a user "<user>" for an entity "<entity>"
  Given there is an existing investor "name=Sequoia" with "1" users
  And there exists a deal "<deal>" for my startup
  Given there is a deal investor with name "Sequoia"
  Given Im logged in as an investor
  When I view the deal investor details
  Then I should see the deal investor details on the details page
  When I create a new document "name=TestDoc"
  And an document should be created
  And the deal investor document details must be setup right
  When I view the deal investor details
  And I should see the document details on the details page

  Examples:
  	|user	      |deal_investor              |entity               |deal                             |msg	|
  	|  	        |primary_amount_cents=10000 |entity_type=Startup  |name=Series A;amount_cents=10000 |Deal investor was successfully created|
    |  	        |primary_amount_cents=12000 |entity_type=Startup  |name=Series B;amount_cents=12000 |Deal investor was successfully created|
