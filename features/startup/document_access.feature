Feature: Access
  Can access models as a company

Scenario Outline: Access Document employee
  Given there is a user "<user>" for an entity "<entity>"
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor;pan=12345678"
  And another entity is an investor "category=Lead Investor;pan=12345678" in entity
  And given there is a document "<document>" for the entity 
  And I should not have access to the document

  Examples:
  	|user	    |entity               |document                     |
  	|  	      |entity_type=Company  |name=Test |
    |  	      |entity_type=Company  |name=Test |


Scenario Outline: Access Document as Other User
  Given there is a user "<user>" for an entity "<entity>"
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor;pan=12345678"
  And another entity is an investor "category=Lead Investor;pan=12345678" in entity
  And given there is a document "<document>" for the entity 
  Then another user has "false" access to the document

  Examples:
  	|user	    |entity               |document                     |
  	|  	      |entity_type=Company  |name=Test |
    |  	      |entity_type=Company  |name=Test |


Scenario Outline: Access Document as Investor without access
  Given there is a user "<user>" for an entity "<entity>"
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor;pan=12345678"
  And another entity is an investor "category=Lead Investor;pan=12345678" in entity
  And given there is a document "<document>" for the entity 
  Then another user has "false" access to the document

  Examples:
  	|user	    |entity               |document                     |
  	|  	      |entity_type=Company  |name=Test |
    |  	      |entity_type=Company  |name=Test |


Scenario Outline: Access Document as Investor with access
  Given there is a user "" for an entity "<entity>"
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor;pan=12345678"
  And another entity is an investor "category=Lead Investor;pan=12345678" in entity
  And given there is a document "<document>" for the entity 
  And investor has access right "<access_right>" in the document
  And another user has investor access "<investor_access>" in the investor
  And another user has "<should>" access to the document 

  Examples:
  	|should	    |entity               |document   | access_right                                                         | investor_access |
  	|true  	    |entity_type=Company  |name=Test | access_type=Document;access_to_investor_id=4;metadata=All          | approved=1 |
    |true  	    |entity_type=Company  |name=Test | access_type=Document;access_to_category=Lead Investor;metadata=All | approved=1 |
	  |false      |entity_type=Company  |name=Test | access_type=Document;access_to_investor_id=1;metadata=All          | approved=1 |
    |false      |entity_type=Company  |name=Test | access_type=Document;access_to_category=Co-Investor;metadata=All   | approved=1 |
	  |false      |entity_type=Company  |name=Test | access_type=Document;access_to_investor_id=4;metadata=All          | approved=0 |
    |false      |entity_type=Company  |name=Test | access_type=Document;access_to_category=Lead Investor;metadata=All | approved=0 |



Scenario Outline: Access Document as Investor without investor access
  Given there is a user "" for an entity "<entity>"
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor;pan=12345678"
  And another entity is an investor "category=Lead Investor;pan=12345678" in entity
  And given there is a document "<document>" for the entity 
  And investor has access right "<access_right>" in the document
  And another user has "<should>" access to the document 

  Examples:
  	|should	    |entity               |document   | access_right     |
  	|false      |entity_type=Company  |name=Test | access_type=Document;access_to_investor_id=1 |
    |false      |entity_type=Company  |name=Test | access_type=Document;access_to_category=Lead Investor |


Scenario Outline: Access Document as Investor without access right
  Given there is a user "" for an entity "<entity>"
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor;pan=12345678"
  And another entity is an investor "category=Lead Investor;pan=12345678" in entity
  And given there is a document "<document>" for the entity 
  And another user has investor access "<investor_access>" in the investor
  And another user has "<should>" access to the document 

  Examples:
  	|should	    |entity               |document                     | investor_access     |
  	|false      |entity_type=Company  |name=Test | approved=1 |
    |false      |entity_type=Company  |name=Test | approved=1 |


