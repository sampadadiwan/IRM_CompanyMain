Feature: Interest
  Can create and view an interest as a secondary buyer



Scenario Outline: Create new interest for indicative sale
  Given there is a user "<user>" for an entity "<entity>"
  And the user has role "company_admin"
  Given there are "2" employee investors
  Given there is a sale "<sale>"
  Given Im logged in as a user "first_name=Emp1" for an entity "entity_type=Investor;pan=1234567"
  Given my firm is an investor in the company
  And the investor has "Buyer" access rights to the sale  
  And I am at the sales details page
  Then I should see only relevant sales details
  Then I should not see the private files
  Then I should not see the holdings
  Then when I create an interest "quantity=100;price=150"
  Then I should see the interest details
  And I am at the sales details page
  Then I should see the interest details
  And when the interest is shortlisted
  And when the interest sale is finalized
  And I edit the interest ""
  Then I should see the interest details
  When I click "Documents"
  When I create a new document "name=TestDoc"
  And an document should be created
  And the interest document details must be setup right
  And I visit the interest details page
  When I click "Documents"
  And I should see the document details on the details page
  
Examples:
    |user	    |entity               |sale                                                                     |quantity	|
    |  	        |entity_type=Company  |percent_allowed=100;min_price=130;max_price=200;price_type=Price Range;show_quantity=Indicative;indicative_quantity=100000  |200        |
    |  	        |entity_type=Company  |percent_allowed=100;final_price=150;price_type=Fixed Price;show_quantity=Indicative;indicative_quantity=100000  |200        |
