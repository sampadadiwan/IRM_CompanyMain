Feature: Deal Investor
  Can create and view a deal investor as a company

Scenario Outline: Create new deal investor
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "name=Sequoia"
  And there exists a deal "<deal>" for my company
  And I visit the deal details page
  When I create a new deal investor "<deal_investor>"
  Then I should see the "<msg>"
  And a deal investor should be created
  And I should see the deal investor details on the details page
  And I should see the deal investor in all deal investors page

  Examples:
  	|user	      |deal_investor              |entity               |deal                             |msg	|
  	|  	        |primary_amount_cents=10000 |entity_type=Company  |name=Series A;amount_cents=10000 |Deal investor was successfully created|
    |  	        |primary_amount_cents=12000 |entity_type=Company  |name=Series B;amount_cents=12000 |Deal investor was successfully created|


Scenario Outline: View Deal Investors in a deal as company_admin
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there are "3" existing investor ""
  And there exists a deal "<deal>" for my company
  And I visit the deal details page
  And when I start the deal
  And there are "3" deal_investors for the deal
  And I should see the deal investors in the deal details page

  Examples:
  	|user	      |deal_investor              |entity               |deal                             |msg	|
  	|  	        |primary_amount_cents=10000 |entity_type=Company  |name=Series A;amount_cents=10000 |Deal investor was successfully created|
    |  	        |primary_amount_cents=12000 |entity_type=Company  |name=Series B;amount_cents=12000 |Deal investor was successfully created|

Scenario Outline: View Deal Investors in a deal as employee
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "<role>"
  Given there are "3" existing investor ""
  And there exists a deal "<deal>" for my company
  And the deal is started
  And there are "3" deal_investors for the deal
  And I am "<given>" employee access to the deal_investors
  And I visit the deal details page  
  Then I "<should>" see the deal investors in the deal details page

  Examples:
  	|role	        |deal_investor              |entity               |deal                             | given| should |
  	|company  	  |primary_amount_cents=10000 |entity_type=Company  |name=Series A;amount_cents=10000 | yes | true |
    |fund_manager |primary_amount_cents=12000 |entity_type=Company  |name=Series B;amount_cents=12000 | yes | true |
    |company  	  |primary_amount_cents=10000 |entity_type=Company  |name=Series A;amount_cents=10000 | no | false |
    |fund_manager |primary_amount_cents=12000 |entity_type=Company  |name=Series B;amount_cents=12000 | no | false |



Scenario Outline: View Deal Stages in a deal
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "name=Sequoia"
  Given there is an existing investor "name=Kalaari"
  And there exists a deal "<deal>" for my company
  And there are "2" deal_investors for the deal
  And I visit the deal details page
  And when I start the deal
  And I visit the deal details page
  And I should see the deal investors in the deal details page
  And I should see the deal stages in the deal details page

  Examples:
  	|user	      |deal_investor              |entity               |deal                             |msg	|
  	|  	        |primary_amount_cents=10000 |entity_type=Company  |name=Series A;amount_cents=10000 |Deal investor was successfully created|
    |  	        |primary_amount_cents=12000 |entity_type=Company  |name=Series B;amount_cents=12000 |Deal investor was successfully created|



Scenario Outline: View Deal Stages in a deal
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "name=Sequoia"
  Given there is an existing investor "name=Kalaari"
  And there exists a deal "<deal>" for my company
  And there are "2" deal_investors for the deal
  And I visit the deal details page
  And when I start the deal
  And the deal activites are completed
  And I visit the deal details page
  And I should see the deal investors in the deal details page
  And I should see the deal stages in the deal details page

  Examples:
  	|user	      |deal_investor              |entity               |deal                             |msg	|
  	|  	        |primary_amount_cents=10000 |entity_type=Company  |name=Series A;amount_cents=10000 |Deal investor was successfully created|
    |  	        |primary_amount_cents=12000 |entity_type=Company  |name=Series B;amount_cents=12000 |Deal investor was successfully created|



Scenario Outline: View Deal Stages in a deal
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "name=Sequoia"
  And there exists a deal "<deal>" for my company
  And there are "1" deal_investors for the deal
  And I visit the deal details page
  And when I start the deal
  Then I should see the "Deal was successfully started"
  And I complete an activity
  Then the activity must be completed

  Examples:
  	|user	      |deal_investor              |entity               |deal                             |msg	|
  	|  	        |primary_amount_cents=10000 |entity_type=Company  |name=Series A;amount_cents=10000 |Deal investor was successfully created|
    |  	        |primary_amount_cents=12000 |entity_type=Company  |name=Series B;amount_cents=12000 |Deal investor was successfully created|


Scenario Outline: Create new deal investor document
  Given there is a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "name=Sequoia" with "1" users
  And there exists a deal "<deal>" for my company
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
  	|  	        |primary_amount_cents=10000 |entity_type=Company  |name=Series A;amount_cents=10000 |Deal investor was successfully created|
    |  	        |primary_amount_cents=12000 |entity_type=Company  |name=Series B;amount_cents=12000 |Deal investor was successfully created|
