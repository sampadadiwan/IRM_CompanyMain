Feature: Secondary Sale
  Can create and view a sale as a startup

Scenario Outline: Create new sale
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the sales page
  When I create a new sale "<sale>"
  Then I should see the "<msg>"
  And an sale should be created
  And I should see the sale details on the details page
  And I should see the sale in all sales page

  Examples:
  	|user	    |entity               |sale             |msg	|
  	|  	        |entity_type=Startup  |name=Grand Sale  |Secondary sale was successfully created|
    |  	        |entity_type=Startup  |name=Winter Sale |Secondary sale was successfully created|



Scenario Outline: Create new sale and make visible
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the sales page
  When I create a new sale "<sale>"
  Then I should see the "<msg>"
  And an sale should be created
  And I should see the sale details on the details page
  And when I click the "Make Visible Externally" button
  And when I click the "Proceed" button
  Then the sale should become externally visible

  Examples:
  	|user	      |entity               |sale             |msg	|
  	|  	        |entity_type=Startup  |name=Grand Sale  |Secondary sale was successfully created|
    |  	        |entity_type=Startup  |name=Winter Sale |Secondary sale was successfully created|



Scenario Outline: Sale Allocation
  Given Im logged in as a user "first_name=Emp1" for an entity "entity_type=Startup"
  Given the user has role "company_admin"
  Given there is a sale "<sale>"
  Given there are "2" employee investors
  Given there is a FundingRound "name=Series A"
  And there is a holding "orig_grant_quantity=100;investment_instrument=Equity" for each employee investor
  Given there are offers "<offer>" for the sale
  Given there are "<interest_count>" interests "<interest>" for the sale
  Then when the allocation is done
  Then the sale allocation percentage must be "<allocation_percentage>"
  Then the sale must be allocated correctly
  Then the offers must be allocated correctly
  Then the interests must be allocated correctly
  And the allocations ops sheet must be visible
  And the offers completetion page must be visible

  Examples:
  	|allocation_percentage |interest_count |interest                       |offer	                      |entity                     |sale                                     |
  	| .5                   |1              |quantity=50;short_listed=true  |quantity=50;approved=true  	|entity_type=Advisor        |name=Grand Sale;visible_externally=true;price_type=Fixed Price;final_price=10000;percent_allowed=100  |
    | 1.0                  |2              |quantity=50;short_listed=true  |quantity=50;approved=true  	|entity_type=Advisor        |name=Grand Sale;visible_externally=true;price_type=Fixed Price;final_price=10000;percent_allowed=100  |
    | 1.5                  |3              |quantity=50;short_listed=true  |quantity=50;approved=true  	|entity_type=Advisor        |name=Grand Sale;visible_externally=true;price_type=Fixed Price;final_price=10000;percent_allowed=100  |    
    | .5                   |1              |quantity=50;short_listed=true  |quantity=50;approved=true  	|entity_type=Advisor        |name=Grand Sale;visible_externally=true;price_type=Price Range;min_price=10000;max_price=11000;final_price=10000;percent_allowed=100  |
    | 1.0                  |2              |quantity=50;short_listed=true  |quantity=50;approved=true  	|entity_type=Advisor        |name=Grand Sale;visible_externally=true;price_type=Price Range;min_price=10000;max_price=11000;final_price=10000;percent_allowed=100  |
    | 1.5                  |3              |quantity=50;short_listed=true  |quantity=50;approved=true  	|entity_type=Advisor        |name=Grand Sale;visible_externally=true;price_type=Price Range;min_price=10000;max_price=11000;final_price=10000;percent_allowed=100  |
    


Scenario Outline: Sale To Cap Table
  Given there is a user "first_name=Emp1" for an entity "entity_type=Startup"
  Given the user has role "company_admin"
  Given there is a sale "<sale>"
  Given there are "3" employee investors
  Given there is a FundingRound "name=Series A"
  And there is a holding "approved=true;orig_grant_quantity=100;investment_instrument=Equity" for each employee investor
  Given there are offers "<offer>" for the sale
  Given there are "<interest_count>" interests "<interest>" for the sale
  Then when the allocation is done
  And when the sale is finalized
  And when the cap table is updated from the sale 
  Then there are "<interest_count>" investor investments in the cap table
  Then the employee holdings must be reduced by the sold amount
  And the employee investments must be reduced by the sold amount
  # And the investor investments quantity should be the interest quantity
  
  Examples:
    |interest_count |interest                                            |offer              	                          |entity                     |sale                                     |
  	|1              |quantity=50;short_listed=true;escrow_deposited=true  |quantity=50;approved=true;verified=true |entity_type=Advisor        |name=Grand Sale;visible_externally=true;price_type=Fixed Price;final_price=10000;percent_allowed=100  |
    |2              |quantity=50;short_listed=true;escrow_deposited=true  |quantity=50;approved=true;verified=true  	|entity_type=Advisor        |name=Grand Sale;visible_externally=true;price_type=Fixed Price;final_price=10000;percent_allowed=100  |
    |3              |quantity=50;short_listed=true;escrow_deposited=true  |quantity=50;approved=true;verified=true  	|entity_type=Advisor        |name=Grand Sale;visible_externally=true;price_type=Fixed Price;final_price=10000;percent_allowed=100  |    
    |1              |quantity=50;short_listed=true;escrow_deposited=true  |quantity=50;approved=true;verified=true  	|entity_type=Advisor        |name=Grand Sale;visible_externally=true;price_type=Price Range;min_price=10000;max_price=11000;final_price=10000;percent_allowed=100  |
    |2              |quantity=50;short_listed=true;escrow_deposited=true  |quantity=50;approved=true;verified=true  	|entity_type=Advisor        |name=Grand Sale;visible_externally=true;price_type=Price Range;min_price=10000;max_price=11000;final_price=10000;percent_allowed=100  |
    |3              |quantity=50;short_listed=true;escrow_deposited=true  |quantity=50;approved=true;verified=true  	|entity_type=Advisor        |name=Grand Sale;visible_externally=true;price_type=Price Range;min_price=10000;max_price=11000;final_price=10000;percent_allowed=100  |
    