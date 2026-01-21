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
  	|true  	    |entity_type=Company  |name=Test | access_type=Document;access_to_investor_id=1;metadata=All          | approved=1 |
    |true  	    |entity_type=Company  |name=Test | access_type=Document;access_to_category=Lead Investor;metadata=All | approved=1 |
	  |false      |entity_type=Company  |name=Test | access_type=Document;access_to_investor_id=1;metadata=All          | approved=0 |
    |false      |entity_type=Company  |name=Test | access_type=Document;access_to_category=Co-Investor;metadata=All   | approved=1 |
	  |false      |entity_type=Company  |name=Test | access_type=Document;access_to_investor_id=1;metadata=All          | approved=0 |
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


Scenario Outline: Access Generated Document as Other User
  Given there is a user "<user>" for an entity "<entity>"
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor;pan=12345678"
  And another entity is an investor "category=LP;pan=12345678" in entity
  And given there is a document "<document>" for the entity
  Then another user has "false" access to the document
  And investor has access right "<access_right>" in the document
  And another user has investor access "approved=1" in the investor
  Then another user has "false" access to the document
  Given the document is approved
  Then another user has "true" access to the document

  Examples:
  	|user	    |entity               |document                         | access_right     |
  	|  	      |entity_type=Company  |name=Test;from_template_id=1 | access_type=Document;access_to_category=LP |
    |  	      |entity_type=Company  |name=Test;from_template_id=1 | access_type=Document;access_to_category=LP |

Scenario Outline: Cascade Delete Access Rights to Investor
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And given there is a Folder "<folder>" for the entity
  And the folder has a subfolder "<subfolder>"
  And given there is a document "<document>" under the folder
  Given I create a new Stakeholder "investor_name=Good Investor;primary_email=goodinv@email.com;category=LP" and save
  Given Investor "Good Investor" has a user with email "<email>"
  Given I log out
  Given I log in with email "<email>"
  When I go to see the investor documents of the entity
  Then I cannot see the documents
  When I go to see the document
  Then I should see the "Access Denied"
  Given investor has access right "<access_right>" in the folder
  When I go to see the investor documents of the entity
  Then I should see the documents
  When I go to see the document
  Then I should see the documents details
  Given folders access right is deleted
  When I go to see the investor documents of the entity
  Then I cannot see the documents
  When I go to see the document
  Then I should see the "Access Denied"
  Examples:
  |user	      |entity               |folder |subfolder |document |email | access_right |
  |  	        |entity_type=Company  |name=topmost|name=subfolder|name=testdoc|good1@email.com|access_type=Folder;access_to_investor_id=1;cascade=true|
  |  	        |entity_type=Company  |name=topmost|name=subfolder|name=testdoc|good2@email.com|access_type=Folder;access_to_category=LP;cascade=true|
