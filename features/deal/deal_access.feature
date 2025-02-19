Feature: Access
  Can access models as a company

Scenario Outline: Access Deal employee
  Given there is a user "<user>" for an entity "<entity>"
  Given the user has role "<role>"
  And given there is a deal "<deal>" for the entity
  And I have "<deal_access>" access to the deal
  And I have "true" access to the deal data room
  And given there is a document "name=Test" for the deal
  And I have "<doc_access>" access to the document

  Examples:
  	|user	    |entity               |deal                     | role | deal_access | doc_access |
  	|  	      |entity_type=Company  |name=Series A;amount_cents=100 | company_admin | true | true |
    |  	      |entity_type=Company  |name=Series B;amount_cents=120 | company_admin | true | true |
    # |  	      |entity_type=Company  |name=Series A;amount_cents=100 | employee | true | true |
    # |  	      |entity_type=Company  |name=Series B;amount_cents=120 | employee | true | true |


Scenario Outline: Access Deal employee
  Given there is a user "" for an entity "<entity>"
  Given the user has role "<role>"
  And given there is a deal "<deal>" for the entity
  And I am "<given>" employee access to the deal
  And I have "<deal_access>" access to the deal
  And I have "true" access to the deal data room
  And given there is a document "name=Test" for the deal
  And I have "<doc_access>" access to the document

  Examples:
  	|given	    |entity               |deal                     | role | deal_access | doc_access |
    | yes 	    |entity_type=Company  |name=Series A;amount_cents=100 | employee | true | true |
    | yes       |entity_type=Company  |name=Series B;amount_cents=120 | employee | true | true |

Scenario Outline: Access Deal as Other User
  Given there is a user "<user>" for an entity "<entity>"
  And given there is a deal "<deal>" for the entity
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor"
  And another user "false" have access to the deal
  And another user "false" have access to the deal data room
  And given there is a document "name=Test" for the deal
  And another user has "false" access to the document

  Examples:
  	|user	    |entity               |deal                     |
  	|  	      |entity_type=Company  |name=Series A;amount_cents=100 |
    |  	      |entity_type=Company  |name=Series B;amount_cents=120 |


Scenario Outline: Access Deal as Investor without access
  Given there is a user "<user>" for an entity "<entity>"
  And given there is a deal "<deal>" for the entity
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor"
  And another entity is an investor "category=Lead Investor" in entity
  And another entity is a deal_investor "status=Active" in the deal
  Then another user "false" have access to the deal
  And another user "false" have access to the deal data room
  And given there is a document "name=Test" for the deal
  And another user has "false" access to the document

  Examples:
  	|user	    |entity               |deal                     |
  	|  	      |entity_type=Company  |name=Series A;amount_cents=100 |
    |  	      |entity_type=Company  |name=Series B;amount_cents=120 |


Scenario Outline: Access Deal as Investor with access
  Given there is a user "" for an entity "<entity>"
  And given there is a deal "<deal>" for the entity
  Given there is another user "first_name=Investor" for another entity "name=Another Entity;pan=X5CA4DB71K;entity_type=Investor"
  And another entity is an investor "pan=X5CA4DB71K;category=Lead Investor" in entity
  And another entity is a deal_investor "status=Active" in the deal
  And investor has access right "<access_right>" in the deal
  And another user has investor access "<investor_access>" in the investor
  Then another user "<should>" have access to the deal
  Then another user "<should>" have access to the deal data room
  And given there is a document "name=Test" for the deal
  And another user has "<should>" access to the document

  Examples:
  	|should	    |entity               |deal                     | access_right                                      | investor_access |
  	|false  	  |entity_type=Company  |name=Series A;amount_cents=100 | access_type=Deal;access_to_investor_id=1          | approved=1 |
    |false  	  |entity_type=Company  |name=Series B;amount_cents=120 | access_type=Deal;access_to_category=Co-Investor | approved=1 |
	  |false      |entity_type=Company  |name=Series A;amount_cents=100 | access_type=Deal;access_to_investor_id=1          | approved=1 |
    |false      |entity_type=Company  |name=Series B;amount_cents=120 | access_type=Deal;access_to_category=Co-Investor   | approved=1 |
	  |false      |entity_type=Company  |name=Series A;amount_cents=100 | access_type=Deal;access_to_investor_id=1          | approved=0 |
    |false      |entity_type=Company  |name=Series B;amount_cents=120 | access_type=Deal;access_to_category=Lead Investor | approved=0 |



Scenario Outline: Access Deal as Investor without investor access
  Given there is a user "" for an entity "<entity>"
  And given there is a deal "<deal>" for the entity
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor;pan=X5CA4DB71K"
  And another entity is an investor "category=Lead Investor;pan=X5CA4DB71K" in entity
  And investor has access right "<access_right>" in the deal
  And another user "<should>" have access to the deal

  Examples:
  	|should	    |entity               |deal                     | access_right     |
  	|false      |entity_type=Company  |name=Series A;amount_cents=100 | access_type=Deal;access_to_investor_id=1 |
    |false      |entity_type=Company  |name=Series B;amount_cents=120 | access_type=Deal;access_to_category=Lead Investor |


Scenario Outline: Access Deal as Investor without access right
  Given there is a user "" for an entity "<entity>"
  And given there is a deal "<deal>" for the entity
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor;pan=X5CA4DB71K"
  And another entity is an investor "category=Lead Investor;pan=X5CA4DB71K" in entity
  And another user has investor access "<investor_access>" in the investor
  And another user "<should>" have access to the deal

  Examples:
  	|should	    |entity               |deal                     | investor_access     |
  	|false      |entity_type=Company  |name=Series A;amount_cents=100 | approved=1 |
    |false      |entity_type=Company  |name=Series B;amount_cents=120 | approved=1 |


Scenario: Deal and Deal Document Folder access overview
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the deals page
  When I have Boards Permissions
  When I create a new deal "<deal>"
  Then I should see the "<msg>"
  And an deal should be created
  Given I click on the Add Item and create a new Stakeholder "investor_name=Good Investor;primary_email=goodinv@email.com" and save
  Given I click on the Add Item and create a new Stakeholder "investor_name=Great Investor;primary_email=greatinv@email.com" and save
  Given I click on the Add Item and select "<investor1>" Investor and save
  Given I click on the Add Item and select "<investor2>" Investor and save
  Given I give deal access to "<investor1>"
  Given I give deal access to "<investor2>"
  When I go to the deal access overview
  Then I should see the "2" "deal" access
  Given I give "folder" access to "<investor1>" from the deal access overview
  Then I should see the "2" "deal" access
  And I should see the "1" "folder" access
  Given I delete "deal" access to "<investor2>" from the deal access overview
  Then I should see the "1" "deal" access
  And I should see the "1" "folder" access
  Given I give "deal" access to "<investor2>" from the deal access overview
  Given I delete "folder" access to "<investor2>" from the deal access overview
  Then I should see the "2" "deal" access
  Then I should see the "0" "folder" access

  Examples:
  |user	      |entity               |deal                             |msg	| investor1 | investor2 |
  |  	        |entity_type=Company  |name=Series A;amount_cents=10000 |Deal was successfully created|Good Investor|Great Investor|


Scenario: Investor Deal and Deal Document Folder access
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the deals page
  When I have Boards Permissions
  When I create a new deal "<deal>"
  Then I should see the "<msg>"
  And an deal should be created
  Given I click on the Add Item and create a new Stakeholder "investor_name=Good Investor;primary_email=goodinv@email.com" and save
  Given Investor "Good Investor" has a user with email "<email>"
  Given user "<email>" has deals enabled
  Given I click on the Add Item and select "<investor1>" Investor and save
  And I view the deal details
  Given I add widgets for the deal
  And I view the deal details
  When I click the last "Documents" link
  When I create a new document "<document>" in folder "Deal Documents"
  Then I should see the "Document was successfully saved"
  Given I give deal access to "<investor1>"
  Given I give "folder" access to "<investor1>" from the deal access overview
  Given I log out
  Given I log in with email "<email>"
  When I go to the deal investors page
  Then I should see the deal card "<deal>"
  When I go to investor deal overview
  Then I can see the deal preview details
  And I click Deal Documents in the overview
  Then I should see the deal documents
  When I click on deals document
  Then I should see the document details
  Given User "<email>" deals folder access is removed
  When I go to investor deal overview
  Then I should not see the deal documents
  Given User "<email>" deals access is removed
  When I go to the deal investors page
  Then I cannot see the deal card "<deal>"

  Examples:
  |user	      |entity               |deal                             |msg	| investor1 | email | document |
  |  	        |entity_type=Company  |name=Series A;amount_cents=10000 |Deal was successfully created|Good Investor|good@email.com|name=Deal Summary|
