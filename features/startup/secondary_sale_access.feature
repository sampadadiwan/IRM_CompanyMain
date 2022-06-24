Feature: Sale Access
  Can access sale as a startup

Scenario Outline: Access Sale as an employee
  Given there is a user "<user>" for an entity "<entity>"
  Given there is a sale "<sale>"
  And I should have "show" access to the sale "true"
  And I should have "update" access to the sale "true"
  And I should have "destroy" access to the sale "true"
  And I should have "offer" access to the sale "false"
  And I should have "show_interest" access to the sale "false"
  And given there is a document "name=Test" for the sale 
  And I should have access to the document  

  Examples:
  	|user	    |entity               |sale             |
    |  	        |entity_type=Startup  |name=Grand Sale  |
    |  	        |entity_type=Startup  |name=Winter Sale |


Scenario Outline: Access sale as Other User
  Given there is a user "<user>" for an entity "<entity>"
  Given there is a sale "<sale>"
  Given there is another user "first_name=Investor" for another entity "entity_type=VC"
  And another user should have "show" access to the sale "false"
  And I should have "offer" access to the sale "false"
  And I should have "show_interest" access to the sale "false"
  And given there is a document "name=Test" for the sale 
  And another user has "false" access to the document 

  Examples:
  	|user	    |entity               |sale             |
    |  	        |entity_type=Startup  |name=Grand Sale  |
    |  	        |entity_type=Startup  |name=Winter Sale |

Scenario Outline: Access externally visible sale as Other User
  Given there is a user "<user>" for an entity "<entity>"
  Given there is a sale "<sale>"
  Given there is another user "first_name=Investor" for another entity "entity_type=VC"
  And another user should have "show" access to the sale "true"
  And another user should have "offer" access to the sale "false"
  And another user should have "show_interest" access to the sale "true"
  And given there is a document "name=Test" for the sale 
  And another user has "true" access to the document 

  Examples:
  	|user	    |entity               |sale             |
    |  	        |entity_type=Startup  |name=Grand Sale;visible_externally=true  |
    |  	        |entity_type=Startup  |name=Winter Sale;visible_externally=true |


Scenario Outline: Access sale as Holding User
  Given there is a user "<user>" for an entity "<entity>"
  Given there is a sale "<sale>"
  Given there are "1" employee investors
  And employee investor has "Seller" access rights to the sale
  And employee investor should have "show" access to the sale "true"
  And employee investor should have "offer" access to the sale "true"
  And employee investor should have "show_interest" access to the sale "false"
  And given there is a document "name=Test" for the sale 
  And employee investor has "true" access to the document 

  Examples:
  	|user	    |entity               |sale             |
    |  	        |entity_type=Startup  |name=Grand Sale;visible_externally=true  |
    |  	        |entity_type=Startup  |name=Winter Sale;visible_externally=false |

Scenario Outline: Access externally visible sale as Investor User
  Given there is a user "<user>" for an entity "<entity>"
  Given there is a sale "<sale>"
  Given there is an existing investor entity "name=Sequoia" with employee "first_name=Emp1"
  And existing investor has "Buyer" access rights to the sale
  And employee investor should have "show" access to the sale "true"
  And employee investor should have "offer" access to the sale "false"
  And employee investor should have "show_interest" access to the sale "true"
  And given there is a document "name=Test" for the sale 
  And employee investor has "true" access to the document 

  Examples:
  	|user	    |entity               |sale             |
    |  	        |entity_type=Startup  |name=Grand Sale;visible_externally=true  |
    |  	        |entity_type=Startup  |name=Winter Sale;visible_externally=true |    