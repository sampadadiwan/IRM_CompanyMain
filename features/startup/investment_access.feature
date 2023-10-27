Feature: Access
  Can access models as a company

Scenario Outline: Access Investment employee
  Given there is a user "<user>" for an entity "<entity>"
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor;pan=12345678"
  And another entity is an investor "category=Lead Investor;pan=12345678" in entity
  And given there is a investment "<investment>" for the entity 
  And I should have access to the investment
  And I should have access to the aggregate_investment

  Examples:
  	|user	    |entity               |investment                     |
  	|  	      |entity_type=Company  |quantity=100 |
    |  	      |entity_type=Company  |quantity=120 |


Scenario Outline: Access Investment as Other User
  Given there is a user "<user>" for an entity "<entity>"
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor;pan=12345678"
  And another entity is an investor "category=Lead Investor;pan=12345678" in entity
  And given there is a investment "<investment>" for the entity 
  Then another user has "false" access to the investment
  Then another user has "false" access to the aggregate_investment

  Examples:
  	|user	    |entity               |investment                     |
  	|  	      |entity_type=Company  |quantity=100 |
    |  	      |entity_type=Company  |quantity=120 |


Scenario Outline: Access Investment as Investor without access
  Given there is a user "<user>" for an entity "<entity>"
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor;pan=12345678"
  And another entity is an investor "category=Lead Investor;pan=12345678" in entity
  And given there is a investment "<investment>" for the entity 
  Then another user has "false" access to the investment
  Then another user has "false" access to the aggregate_investment

  Examples:
  	|user	    |entity               |investment                     |
  	|  	      |entity_type=Company  |quantity=100 |
    |  	      |entity_type=Company  |quantity=120 |


Scenario Outline: Access Investment as Investor with access
  Given there is a user "" for an entity "<entity>"
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor;pan=12345678"
  And another entity is an investor "category=Lead Investor;pan=12345678" in entity
  And given there is a investment "<investment>" for the entity 
  And investor has access right "<access_right>" in the investment
  And another user has investor access "<investor_access>" in the investor
  And another user has "<should>" access to the investment 
  And another user has "<should>" access to the aggregate_investment 

  Examples:
  	|should	    |entity               |investment   | access_right                    | investor_access |
  	|true  	    |entity_type=Company  |category=Lead Investor;quantity=100;investment_instrument=Equity | access_type=Investment;access_to_investor_id=4;metadata=All          | approved=1 |
    |true  	    |entity_type=Company  |category=Lead Investor;quantity=120;investment_instrument=Equity | access_type=Investment;access_to_category=Lead Investor;metadata=All | approved=1 |
	  |false      |entity_type=Company  |category=Lead Investor;quantity=100;investment_instrument=Equity | access_type=Investment;access_to_investor_id=1;metadata=All          | approved=1 |
    |false      |entity_type=Company  |category=Lead Investor;quantity=120;investment_instrument=Preferred | access_type=Investment;access_to_category=Co-Investor;metadata=All   | approved=1 |
	  |false      |entity_type=Company  |category=Lead Investor;quantity=100;investment_instrument=Preferred | access_type=Investment;access_to_investor_id=4;metadata=All          | approved=0 |
    |false      |entity_type=Company  |category=Lead Investor;quantity=120;investment_instrument=Preferred | access_type=Investment;access_to_category=Lead Investor;metadata=All | approved=0 |



Scenario Outline: Access Investment as Investor without investor access
  Given there is a user "" for an entity "<entity>"
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor;pan=12345678"
  And another entity is an investor "category=Lead Investor;pan=12345678" in entity
  And given there is a investment "<investment>" for the entity 
  And investor has access right "<access_right>" in the investment
  And another user has "<should>" access to the investment 
  And another user has "<should>" access to the aggregate_investment 

  Examples:
  	|should	    |entity               |investment   | access_right     |
  	|false      |entity_type=Company  |quantity=100 | access_type=Investment;access_to_investor_id=1 |
    |false      |entity_type=Company  |quantity=120 | access_type=Investment;access_to_category=Lead Investor |


Scenario Outline: Access Investment as Investor without access right
  Given there is a user "" for an entity "<entity>"
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor;pan=12345678"
  And another entity is an investor "category=Lead Investor;pan=12345678" in entity
  And given there is a investment "<investment>" for the entity 
  And another user has investor access "<investor_access>" in the investor
  And another user has "<should>" access to the investment 
  And another user has "<should>" access to the aggregate_investment 

  Examples:
  	|should	    |entity               |investment                     | investor_access     |
  	|false      |entity_type=Company  |quantity=100 | approved=1 |
    |false      |entity_type=Company  |quantity=120 | approved=1 |
