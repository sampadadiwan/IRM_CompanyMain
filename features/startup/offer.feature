Feature: Offer
  Can create and view a offers as a company employee

Scenario Outline: See my holdings in a sale
  Given there is a user "<user>" for an entity "<entity>"
  Given there are "2" employee investors
  Given Im logged in as an employee investor
  Given there is a FundingRound "name=Series A"
  And there is a holding "approved=true;orig_grant_quantity=100;investment_instrument=Equity" for each employee investor
  Given there is a sale "<sale>"
  Given I have "Seller" access to the sale  
  And I am at the sales details page
  Then I should see only my holdings
Examples:
    |user	      |entity               |sale                                     |quantity	|
    |  	        |entity_type=Company  |name=Grand Sale;visible_externally=true  |100        |
    |  	        |entity_type=Company  |name=Winter Sale;visible_externally=true |200        |



Scenario Outline: Place an offer
  Given there is a user "<user>" for an entity "<entity>"
  Given there are "2" employee investors
  Given Im logged in as an employee investor
  Given there is a FundingRound "name=Series A"
  And there is a holding "approved=true;orig_grant_quantity=100;investment_instrument=Equity" for each employee investor
  Given there is a sale "<sale>"
  Given I have "Seller" access to the sale  
  And I am at the sales details page
  Then when I place an offer "<offer>"
  Then I should see the offer details
  And I am at the sales details page
  Then I should see the offer in the offers tab
  And when the offer is approved
  Then the sales total_offered_quantity should be "<total_quantity>"
  And when the offer sale is finalized
  And I edit the offer "<offer>"
  Then I should see the offer details
  When I click "Documents"
  When I create a new document "name=TestDoc"
  And an document should be created
  And the offer document details must be setup right
  When I visit the offer details page
  When I click "Documents"
  And I should see the document details on the details page

Examples:
    |user	    |entity               |sale                                                         |offer	             | total_quantity |
    |  	        |entity_type=Company  |name=Grand Sale;visible_externally=true;percent_allowed=100  |quantity=100        | 100            |
    |  	        |entity_type=Company  |name=Winter Sale;visible_externally=true;percent_allowed=100 |quantity=50         | 50             |



Scenario Outline: Place a wrong offer 
  Given there is a user "<user>" for an entity "<entity>"
  Given there are "2" employee investors
  Given Im logged in as an employee investor
  Given there is a FundingRound "name=Series A"
  And there is a holding "approved=true;orig_grant_quantity=100;investment_instrument=Equity" for each employee investor
  Given there is a sale "<sale>"
  Given I have "Seller" access to the sale  
  And I am at the sales details page
  Then when I place an offer "<offer>"
  Then I should see the "<msg>"

Examples:
    |user	    |entity               |sale                                                        |offer	              | msg |
    |  	      |entity_type=Company  |name=Grand Sale;visible_externally=true;percent_allowed=50  |quantity=100;approved=false        | Over Allowed Percentage |
    |  	      |entity_type=Company  |name=Winter Sale;visible_externally=true;percent_allowed=50 |quantity=200;approved=false        | is > total holdings   |



Scenario Outline: Approve holdings as a company
  Given Im logged in as a user "<user>" for an entity "<entity>"
  And the user has role "approver,company_admin"
  Given there are "2" employee investors
  Given there is a FundingRound "name=Series A"
  And there is a holding "approved=true;orig_grant_quantity=100;investment_instrument=Equity" for each employee investor
  Given there is a sale "<sale>"
  And there is an "unapproved" offer "quantity=100" for each employee investor
  And I am at the sales details page
  Then I should see all the offers
  And the sales total_offered_quantity should be "0"  
  And When I approve the offers the offers should be approved
  And the sales total_offered_quantity should be "200"  
Examples:
    |user	    |entity               |sale                                                         |quantity	|
    |  	        |entity_type=Company  |name=Grand Sale;visible_externally=true;percent_allowed=100  |100        |
    |  	        |entity_type=Company  |name=Winter Sale;visible_externally=true;percent_allowed=100 |200        |



Scenario Outline: Import offer to sale
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
  Given the user has role "company_admin"
  Given there is a sale "name=Summer Sale"
  Given a esop pool "name=Pool 1" is created with vesting schedule "12:20,24:30,36:50"
  And Given I upload a holdings file
  Then I should see the "Import upload was successfully created"
  And when the holdings are approved
  And Given I upload a offer file
  Then I should see the "Import upload was successfully created"
  And when the offers are approved
  And the sale offered quantity should be "100"
