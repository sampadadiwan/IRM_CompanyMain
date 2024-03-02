Feature: Sale Access
  Can access sale as a company

Scenario Outline: Access Sale as an employee
  Given there is a user "<user>" for an entity "<entity>"
  Given the user has role "<role>"
  Given there is a sale "<sale>"
  And I am "<given>" employee access to the sale
  And the sale access right has access "<crud>"  
  And I should have "show" access to the sale "true"
  And I should have "update" access to the sale "true"
  And I should have "destroy" access to the sale "true"
  And I should have "finalize_offer_allocation" access to the sale "true"
  And I should have "finalize_interest_allocation" access to the sale "true"
  And I should have "owner" access to the sale "true"
  And I should have "buyer" access to the sale "false"
  And I should have "seller" access to the sale "false"
  And I should have "see_private_docs" access to the sale "true"  
  And I should have "offer" access to the sale "false"
  And I should have "show_interest" access to the sale "false"
  And given there is a document "name=Test" for the sale 
  And I should have access to the document  

  Examples:
  	|user	    |entity               |sale             | role            | given | crud  |
    |  	        |entity_type=Company  |name=Grand Sale  | company_admin | yes   |       |
    |  	        |entity_type=Company  |name=Winter Sale | company_admin | no    |       |


Scenario Outline: Access Sale as an employee
  Given there is a user "first_name=Test" for an entity "<entity>"
  Given the user has role "<role>"
  Given there is a sale "<sale>"
  And I am "<given>" employee access to the sale
  And the sale access right has access "<crud>"  
  Then user "<should>" have "<access>" access to the sale
  Examples:
  	|entity               |sale             | role            | given | crud  | should| access |
    |entity_type=Company  |name=Grand Sale  | company_admin | yes   |       | true  | show,update,destroy,see_private_docs  |
    |entity_type=Company  |name=Grand Sale  | company_admin | yes   |       | false  | buyer,seller,offer,show_interest  |
    |entity_type=Company  |name=Winter Sale | company_admin | no    |       | true  | show,update,destroy,see_private_docs  |
    |entity_type=Company  |name=Winter Sale | company_admin | no    |       | false  | buyer,seller,offer,show_interest  |
    |entity_type=Company  |name=Grand Sale  | employee       | yes   |create,read,update,destroy | true  | show,update,destroy,see_private_docs  |
    |entity_type=Company  |name=Grand Sale  | employee       | yes   |create,read,update,destroy | false  | buyer,seller,offer,show_interest |
    |entity_type=Company  |name=Grand Sale  | employee       | yes   |  | false  | update,destroy,buyer,seller,offer,show_interest  |
    
Scenario Outline: Access Sale as an advisor
  Given there is a user "first_name=Test" for an entity "<entity>"
  Given there is a sale "<sale>"
  Given there is an existing investor entity "entity_type=Investor Advisor" with employee "first_name=Advisor"
  And advisor is "<given>" advisor access to the sale
  Given the advisor has role "<role>"
  And the sale access right has access "<crud>"  
  Then user "<should>" have "<access>" access to the sale
  Examples:
  	|entity               |sale             | role            | given | crud  | should| access |
    |entity_type=Company  |name=Grand Sale  | advisor       | yes   |create,read,update,destroy | true  | show,update,destroy,see_private_docs  |
    |entity_type=Company  |name=Grand Sale  | advisor       | yes   |create,read,update,destroy | false  | buyer,seller,offer,show_interest |
    |entity_type=Company  |name=Grand Sale  | advisor       | yes   |  | false  | update,destroy,buyer,seller,offer,show_interest  |
    


Scenario Outline: Access sale as Other User
  Given there is a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a sale "<sale>"
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor"
  And another user should have "show" access to the sale "false"
  And another user should have "offer" access to the sale "false"
  And another user should have "owner" access to the sale "false"
  And another user should have "finalize_offer_allocation" access to the sale "false"
  And another user should have "finalize_interest_allocation" access to the sale "false"
  And another user should have "buyer" access to the sale "false"
  And another user should have "seller" access to the sale "false"
  And another user should have "see_private_docs" access to the sale "false"  
  And another user should have "show_interest" access to the sale "false"
  And given there is a document "name=Test" for the sale 
  And another user has "false" access to the document 

  Examples:
  	|user	    |entity               |sale             |
    |  	        |entity_type=Company  |name=Grand Sale  |
    |  	        |entity_type=Company  |name=Winter Sale |

Scenario Outline: Access externally visible sale as Other User
  Given there is a user "<user>" for an entity "<entity>"
  Given there is a sale "<sale>"
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor"
  And another user should have "show" access to the sale "true"
  And another user should have "finalize_offer_allocation" access to the sale "false"
  And another user should have "finalize_interest_allocation" access to the sale "false"
  And another user should have "owner" access to the sale "false"
  And another user should have "buyer" access to the sale "false"
  And another user should have "seller" access to the sale "false"
  And another user should have "see_private_docs" access to the sale "false"  
  And another user should have "offer" access to the sale "false"
  And another user should have "show_interest" access to the sale "true"
  And given there is a document "name=Test" for the sale 
  And another user has "true" access to the document 

  Examples:
  	|user	    |entity               |sale             |
    |  	        |entity_type=Company  |name=Grand Sale;visible_externally=true  |
    |  	        |entity_type=Company  |name=Winter Sale;visible_externally=true |


Scenario Outline: Access sale as Holding User
  Given there is a user "<user>" for an entity "<entity>"
  Given there is a sale "<sale>"
  Given there are "1" employee investors
  And employee investor has "Seller" access rights to the sale
  And employee investor should have "show" access to the sale "true"
  And employee investor should have "finalize_offer_allocation" access to the sale "false"
  And employee investor should have "finalize_interest_allocation" access to the sale "false"
  And employee investor should have "owner" access to the sale "false"
  And employee investor should have "buyer" access to the sale "false"
  And employee investor should have "seller" access to the sale "true"
  And employee investor should have "see_private_docs" access to the sale "false"  
  And employee investor should have "offer" access to the sale "true"
  And employee investor should have "show_interest" access to the sale "false"
  And given there is a document "name=Test" for the sale 
  And employee investor has "true" access to the document 

  Examples:
  	|user	    |entity               |sale             |
    |  	        |entity_type=Company  |name=Grand Sale  |
    |  	        |entity_type=Company  |name=Winter Sale;visible_externally=false |

Scenario Outline: Access as Buyer Investor User
  Given there is a user "<user>" for an entity "<entity>"
  Given there is a sale "<sale>"
  Given there is an existing investor entity "name=Sequoia" with employee "first_name=Emp1"
  And existing investors have "Buyer" access rights to the sale
  And employee investor should have "show" access to the sale "true"
  And employee investor should have "finalize_offer_allocation" access to the sale "false"
  And employee investor should have "finalize_interest_allocation" access to the sale "false"
  And employee investor should have "owner" access to the sale "false"
  And employee investor should have "buyer" access to the sale "true"
  And employee investor should have "seller" access to the sale "false"
  And employee investor should have "see_private_docs" access to the sale "false"  
  And employee investor should have "offer" access to the sale "false"
  And employee investor should have "show_interest" access to the sale "true"
  And given there is a document "name=Test" for the sale 
  And employee investor has "true" access to the document 

  Examples:
  	|user	    |entity               |sale             |
    |  	        |entity_type=Company  |name=Grand Sale;visible_externally=false  |
    |  	        |entity_type=Company  |name=Winter Sale;visible_externally=false |    


Scenario Outline: Access as Seller Investor User
  Given there is a user "<user>" for an entity "<entity>"
  Given there is a sale "<sale>"
  Given there is an existing investor entity "name=Sequoia" with employee "first_name=Emp1"
  And existing investors have "Seller" access rights to the sale
  And employee investor should have "show" access to the sale "true"
  And employee investor should have "finalize_offer_allocation" access to the sale "false"
  And employee investor should have "finalize_interest_allocation" access to the sale "false"
  And employee investor should have "owner" access to the sale "false"
  And employee investor should have "buyer" access to the sale "false"
  And employee investor should have "seller" access to the sale "true"
  And employee investor should have "see_private_docs" access to the sale "false"  
  And employee investor should have "offer" access to the sale "true"
  And employee investor should have "show_interest" access to the sale "false"
  And given there is a document "name=Test" for the sale 
  And employee investor has "true" access to the document 

  Examples:
  	|user	    |entity               |sale             |
    |  	        |entity_type=Company  |name=Grand Sale;visible_externally=false  |
    |  	        |entity_type=Company  |name=Winter Sale;visible_externally=false |    