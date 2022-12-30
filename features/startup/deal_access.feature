Feature: Access
  Can access models as a company

Scenario Outline: Access Deal employee
  Given there is a user "<user>" for an entity "<entity>"
  Given the user has role "<role>"
  And given there is a deal "<deal>" for the entity 
  And I have "<deal_access>" access to the deal
  And given there is a document "name=Test" for the deal 
  And I have "<doc_access>" access to the document  

  Examples:
  	|user	    |entity               |deal                     | role | deal_access | doc_access |
  	|  	      |entity_type=Company  |name=Series A;amount_cents=100 | company_admin | true | true |
    |  	      |entity_type=Company  |name=Series B;amount_cents=120 | company_admin | true | true |
    |  	      |entity_type=Company  |name=Series A;amount_cents=100 | company | false | true |
    |  	      |entity_type=Company  |name=Series B;amount_cents=120 | fund_manager | false | true |


Scenario Outline: Access Deal employee
  Given there is a user "" for an entity "<entity>"
  Given the user has role "<role>"
  And given there is a deal "<deal>" for the entity 
  And I am "<given>" employee access to the deal
  And I have "<deal_access>" access to the deal
  And given there is a document "name=Test" for the deal 
  And I have "<doc_access>" access to the document  

  Examples:
  	|given	    |entity               |deal                     | role | deal_access | doc_access |
    | yes 	    |entity_type=Company  |name=Series A;amount_cents=100 | company | true | true |
    | yes       |entity_type=Company  |name=Series B;amount_cents=120 | fund_manager | true | true |

Scenario Outline: Access Deal as Other User
  Given there is a user "<user>" for an entity "<entity>"
  And given there is a deal "<deal>" for the entity 
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor"
  And another user "false" have access to the deal
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
  And given there is a document "name=Test" for the deal 
  And another user has "false" access to the document 

  Examples:
  	|user	    |entity               |deal                     |
  	|  	      |entity_type=Company  |name=Series A;amount_cents=100 |
    |  	      |entity_type=Company  |name=Series B;amount_cents=120 |


Scenario Outline: Access Deal as Investor with access
  Given there is a user "" for an entity "<entity>"
  And given there is a deal "<deal>" for the entity 
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor"
  And another entity is an investor "category=Lead Investor" in entity
  And another entity is a deal_investor "status=Active" in the deal
  And investor has access right "<access_right>" in the deal
  And another user has investor access "<investor_access>" in the investor
  Then another user "<should>" have access to the deal 
  And given there is a document "name=Test" for the deal 
  And another user has "<should>" access to the document 

  Examples:
  	|should	    |entity               |deal                     | access_right                                      | investor_access |
  	|false  	  |entity_type=Company  |name=Series A;amount_cents=100 | access_type=Deal;access_to_investor_id=3          | approved=1 |
    |false  	  |entity_type=Company  |name=Series B;amount_cents=120 | access_type=Deal;access_to_category=Lead Investor | approved=1 |
	  |false      |entity_type=Company  |name=Series A;amount_cents=100 | access_type=Deal;access_to_investor_id=1          | approved=1 |
    |false      |entity_type=Company  |name=Series B;amount_cents=120 | access_type=Deal;access_to_category=Co-Investor   | approved=1 |
	  |false      |entity_type=Company  |name=Series A;amount_cents=100 | access_type=Deal;access_to_investor_id=3          | approved=0 |
    |false      |entity_type=Company  |name=Series B;amount_cents=120 | access_type=Deal;access_to_category=Lead Investor | approved=0 |



Scenario Outline: Access Deal as Investor without investor access
  Given there is a user "" for an entity "<entity>"
  And given there is a deal "<deal>" for the entity 
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor"
  And another entity is an investor "category=Lead Investor" in entity
  And investor has access right "<access_right>" in the deal
  And another user "<should>" have access to the deal 

  Examples:
  	|should	    |entity               |deal                     | access_right     |
  	|false      |entity_type=Company  |name=Series A;amount_cents=100 | access_type=Deal;access_to_investor_id=1 |
    |false      |entity_type=Company  |name=Series B;amount_cents=120 | access_type=Deal;access_to_category=Lead Investor |


Scenario Outline: Access Deal as Investor without access right
  Given there is a user "" for an entity "<entity>"
  And given there is a deal "<deal>" for the entity 
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor"
  And another entity is an investor "category=Lead Investor" in entity
  And another user has investor access "<investor_access>" in the investor
  And another user "<should>" have access to the deal 

  Examples:
  	|should	    |entity               |deal                     | investor_access     |
  	|false      |entity_type=Company  |name=Series A;amount_cents=100 | approved=1 |
    |false      |entity_type=Company  |name=Series B;amount_cents=120 | approved=1 |
