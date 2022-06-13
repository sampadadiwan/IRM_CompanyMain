Feature: Interest
  Can create and view an interest as a secondary buyer

Scenario Outline: Create new interest
  Given there is a user "<user>" for an entity "<entity>"
  Given there are "2" employee investors
  Given there is a sale "<sale>"
  Given there is a FundingRound "name=Series A"
  And there is a holding "approved=true;orig_grant_quantity=110;investment_instrument=Equity" for each employee investor
  And there is an "approved" offer "quantity=110" for each employee investor
  Given Im logged in as a user "first_name=Buyer" for an entity "entity_type=Advisor"
  And I am at the sales details page
  Then I should see only relevant sales details
  Then I should not see the private files
  Then I should not see the holdings
  Then when I create an interest "quantity=100;price=150"
  Then I should see the interest details
  And I am at the sales details page
  Then I should see the interest details
  And when the interest sale is finalized
  And I edit the interest ""
  Then I should see the interest details
  
  
Examples:
    |user	    |entity               |sale                                                                     |quantity	|
    |  	        |entity_type=Startup  |visible_externally=true;percent_allowed=100;min_price=120;max_price=180;price_type=Price Range  |100        |
    |  	        |entity_type=Startup  |visible_externally=true;percent_allowed=100;min_price=130;max_price=200;price_type=Price Range  |200        |


Scenario Outline: Create new interest and check obfuscation
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given there are "2" employee investors
  Given there is a sale "<sale>"
  Given there is a FundingRound "name=Series A"
  And there is a holding "approved=true;orig_grant_quantity=110;investment_instrument=Equity" for each employee investor
  And there is an "approved" offer "quantity=110;approved=1" for each employee investor
  Given an interest "quantity=100;price=150" from some entity "entity_type=Advisor"
  And I am at the sales details page
  And I click "Interest"
  Then I should see the interest details
  And I click "Show"
  Then I should see the interest details
  And I am at the sales details page
  And I click "Interest"
  And I click "Shortlist"
  Then the interest should be shortlisted
  
  
Examples:
    |user	    |entity               |sale                                                                     |quantity	|
    |  	        |entity_type=Startup  |visible_externally=true;percent_allowed=100;min_price=120;max_price=180  |100        |
    |  	        |entity_type=Startup  |visible_externally=true;percent_allowed=100;min_price=130;max_price=200  |200        |


Scenario Outline: Create new interest which is escrow approved
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given there are "2" employee investors
  Given there is a sale "<sale>"
  Given there is a FundingRound "name=Series A"
  And there is a holding "approved=true;orig_grant_quantity=110;investment_instrument=Equity" for each employee investor
  And there is an "approved" offer "quantity=110;approved=1" for each employee investor
  Given an interest "quantity=100;price=150;escrow_deposited=true" from some entity "entity_type=Advisor"
  And I am at the sales details page
  And I click "Interest"
  Then I should see the interest details
  
  
Examples:
    |user	    |entity               |sale                                                                     |quantity	|
    |  	        |entity_type=Startup  |visible_externally=true;percent_allowed=100;min_price=120;max_price=180  |100        |
    |  	        |entity_type=Startup  |visible_externally=true;percent_allowed=100;min_price=130;max_price=200  |200        |
