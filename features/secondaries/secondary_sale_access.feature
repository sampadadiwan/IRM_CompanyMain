Feature: Sale Access
  Can access sale as a company

Scenario Outline: Access Sale as an employee/company_admin
  Given there is a user "first_name=Test" for an entity "entity_type=Company"
  Given the user has role "<role>"
  Given there is a sale "<sale>"
  And I am "<given>" employee access to the sale
  And the sale access right has access "<crud>"  
  Then user "<should>" have "<access>" access to the sale
  Given there is an existing investor entity "investor_name=Seller;entity_type=Investor" with employee "first_name=Sell"
  Given the investor has "Seller" access rights to the sale
  Given the investor has an offer "quantity=10" for the sale
  And the offer is approved
  Given there is an existing investor entity "investor_name=Buyer;entity_type=Investor" with employee "first_name=Buy" 
  Given the investor has "Buyer" access rights to the sale
  Given the investor has an interest "quantity=10;short_listed_status=short_listed;verified=true" for the sale
  Then user "<should>" have "<offer_access>" access to the offer
  Then user "<should>" have "<interest_access>" access to the interest

  
  Examples:
  	|sale             | role          | given | crud  | should| access | offer_access | interest_access |
    # company_admin role
    |name=Grand Sale;manage_interests=false;manage_offers=false  | company_admin | yes   |       | true  | show,update,destroy,owner,see_private_docs,generate_spa  | show,generate_docs |show,generate_docs,short_list |
    |name=Grand Sale;manage_interests=false;manage_offers=false  | company_admin | yes   |       | false  | buyer,seller,offer,show_interest  | | |
    |name=Winter Sale;manage_interests=false;manage_offers=false | company_admin | no    |       | true  | show,update,destroy,owner,see_private_docs,generate_spa  | show,generate_docs |show,generate_docs,short_list |
    |name=Winter Sale;manage_interests=false;manage_offers=false | company_admin | no    |       | false  | buyer,seller,offer,show_interest  | | |
    # employee role, no access
    |name=Grand Sale;manage_interests=false;manage_offers=false  | employee      | no    |  | false  | show,update,destroy,owner,see_private_docs,generate_spa,buyer,seller,offer,show_interest   |  show,update,generate_docs |show,update,generate_docs,short_list |
    # employee role, with access
    |name=Grand Sale;manage_interests=false;manage_offers=false  | employee      | yes   |create,read,update,destroy | true  | show,update,destroy,owner,see_private_docs,generate_spa | show,generate_docs |show,generate_docs,short_list |
    |name=Grand Sale;manage_interests=false;manage_offers=false  | employee      | yes   |create,read,update,destroy | false  | buyer,seller,offer,show_interest | | |
    |name=Grand Sale;manage_interests=false;manage_offers=false  | employee      | yes   |  | true   | show,owner,see_private_docs   | | |
    |name=Grand Sale;manage_interests=false;manage_offers=false  | employee      | yes   |  | false  | update,destroy,generate_spa,allocate   |  generate_docs |generate_docs,short_list |
    |name=Grand Sale;manage_interests=false;manage_offers=false  | employee      | yes   | create,read,update | true   | show,owner,see_private_docs,update,generate_spa,allocate   | show,generate_docs |show,generate_docs,short_list |
    |name=Grand Sale;manage_interests=false;manage_offers=false  | employee      | yes   | create,read,update | false | destroy   | destroy | destroy |
    # Special case of manage_offers and manage_interests
    |name=Grand Sale;manage_offers=true;manage_interests=true | company_admin | no   |       | true  | offer,show_interest  | show,generate_docs |show,generate_docs,short_list |

Scenario Outline: Access Sale as an advisor
  Given there is a user "first_name=Test" for an entity "<entity>"
  Given there is a sale "<sale>"
  Given there is an existing investor entity "entity_type=Investor Advisor" with employee "first_name=Advisor"
  And advisor is "<given>" advisor access to the sale
  Given the advisor has role "employee"
  Given the advisor has role "<role>"
  And the sale access right has access "<crud>"  
  Then user "<should>" have "<access>" access to the sale
  

  Examples:
  	|entity               |sale             | role            | given | crud  | should| access |
    |entity_type=Company  |name=Grand Sale;manage_interests=false;manage_offers=false  | advisor       | yes   |create,read,update,destroy | true  | show,update,destroy,see_private_docs  |
    |entity_type=Company  |name=Grand Sale;manage_interests=false;manage_offers=false  | advisor       | yes   |create,read,update,destroy | false  | buyer,seller,offer,show_interest |
    |entity_type=Company  |name=Grand Sale;manage_interests=false;manage_offers=false  | advisor       | yes   |  | false  | update,destroy,buyer,seller,offer,show_interest  |
    
Scenario Outline: Access Sale as an RM
  Given there is a user "first_name=Test" for an entity "entity_type=Company"
  Given there is a sale "<sale>"
  Given there is an existing investor entity "entity_type=RM" with employee "first_name=RM1"
  And existing investors have "RM" access rights to the sale
  Given the existing investor user has role "<role>"
  Then existing investor user "<should>" have "<access>" access to the sale
  

  Examples:
  	|sale             | role     | should | access |
    |name=Grand Sale  | rm       | true   | show,offer,show_interest,buyer,seller,offer,show_interest  |
    |name=Grand Sale  | rm       | false  | update,destroy,see_private_docs |

Scenario Outline: Access sale as Other User
  Given there is a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a sale "<sale>"
  Given there is another user "first_name=Investor" for another entity "entity_type=Investor"
  And another user should have "show" access to the sale "false"
  And another user should have "offer" access to the sale "false"
  And another user should have "owner" access to the sale "false"
  And another user should have "allocate" access to the sale "false"
  And another user should have "buyer" access to the sale "false"
  And another user should have "seller" access to the sale "false"
  And another user should have "see_private_docs" access to the sale "false"  
  And another user should have "show_interest" access to the sale "false"
  And given there is a document "name=Test" for the sale 
  And another user has "false" access to the document 

  Examples:
  	|user	    |entity               |sale             |
    |  	        |entity_type=Company  |name=Grand Sale;manage_interests=false;manage_offers=false  |
    |  	        |entity_type=Company  |name=Winter Sale;manage_interests=false;manage_offers=false |



Scenario Outline: Access as Buyer Investor User
  Given there is a user "<user>" for an entity "<entity>"
  Given there is a sale "<sale>"
  Given there is an existing investor entity "name=Sequoia" with employee "first_name=Emp1"
  And existing investors have "Buyer" access rights to the sale
  And employee investor should have "show" access to the sale "true"
  And employee investor should have "allocate" access to the sale "false"
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
  And employee investor should have "allocate" access to the sale "false"
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