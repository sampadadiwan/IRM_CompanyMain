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
    |user	      |entity                          |sale                                     |quantity	|
    |  	        |entity_type=Company;pan=123456  |name=Grand Sale;show_holdings=true  |100        |
    |  	        |entity_type=Company;pan=123456  |name=Winter Sale;show_holdings=true |200        |



Scenario Outline: Place an offer
  Given there is a user "first_name=John" for an entity "entity_type=Company"
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
    |sale                                                    |offer	             | total_quantity |
    |name=Grand Sale;percent_allowed=100;show_holdings=true  |quantity=100        | 100            |
    |name=Winter Sale;percent_allowed=100;show_holdings=true |quantity=50         | 50             |



Scenario Outline: Place a wrong offer
  Given there is a user "" for an entity "entity_type=Company"
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
    |sale                                                        |offer	              | msg |
    |name=Grand Sale;percent_allowed=50;show_holdings=true  |quantity=100;approved=false        | Over Allowed Percentage |
    |name=Winter Sale;percent_allowed=50;show_holdings=true |quantity=200;approved=false        | is > total holdings   |



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
    |  	        |entity_type=Company  |name=Grand Sale;percent_allowed=100  |100        |
    |  	        |entity_type=Company  |name=Winter Sale;percent_allowed=100 |200        |


@import
Scenario Outline: Import offer to sale
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
  Given the user has role "company_admin"
  And Given I upload an investors file for the company
  # And Given I upload an investor access file for employees
  Given there is a sale "name=Summer Sale;price_type=Variable Price;min_price=100;max_price=200"
  Given a esop pool "name=Pool 1" is created with vesting schedule "12:20,24:30,36:50"
  And Given I upload a holdings file
  Then I should see the "Import in progress"
  And when the holdings are approved
  And Given I upload a offer file "offers.xlsx"
  Then I should see the "Import in progress"
  And the offers must have the data in the sheet
  And when the offers are approved
  And the sale offered quantity should be "120"



@import
Scenario Outline: Import offer to sale without holdings
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
  Given the user has role "company_admin"
  And Given I upload an investors file for the company
  And Given I upload an investor access file for employees
  Given there is a sale "name=Summer Sale;price_type=Variable Price;min_price=100;max_price=200"
  And Given I upload a offer file "offers_no_holdings.xlsx"
  Then I should see the "Import in progress"
  And the offers must have the data in the sheet
  And the offer investors must have access rights to the sale
  And when the offers are approved
  And the sale offered quantity should be "120"

Scenario Outline: Offer PAN verification
  Given there is a user "" for an entity "entity_type=Company"
  Given there are "2" employee investors
  Given Im logged in as an employee investor
  Given there is a FundingRound "name=Series A"
  And there is a holding "approved=true;orig_grant_quantity=100;investment_instrument=Equity" for each employee investor
  Given there is a sale "<sale>"
  Given I have "Seller" access to the sale
  And I am at the sales details page
  Then when I place an offer "<offer>"
  Then I should see the offer details
  Given Offer PAN verification is enabled
  And I add pan details to the offer
  Then Pan Verification is triggered
  And when the offer name is updated
  Then Pan Verification is triggered
  And when the offer PAN is updated
  Then Pan Verification is triggered


Examples:
    |sale                                                     |offer	             |
    |name=Grand Sale;percent_allowed=100;show_holdings=true   |quantity=100        |


Scenario Outline: Offer Bank verification
    Given there is a user "" for an entity "entity_type=Company"
    Given there are "2" employee investors
    Given Im logged in as an employee investor
    Given there is a FundingRound "name=Series A"
    And there is a holding "approved=true;orig_grant_quantity=100;investment_instrument=Equity" for each employee investor
    Given there is a sale "<sale>"
    Given I have "Seller" access to the sale
    And I am at the sales details page
    Given Offer Bank verification is enabled
    Then when I place an offer "<offer>"
    Then I should see the offer details
    And I add bank details to the offer
    And Bank Verification is triggered
    And when the offer name is updated
    Then Bank Verification is triggered
    And when the offer Bank Account number is updated
    Then Bank Verification is triggered
    And when the offer Bank IFSC is updated
    Then Bank Verification is triggered

  Examples:
      |sale                                                     | offer	             |
      |name=Grand Sale;percent_allowed=100;show_holdings=true   |quantity=100        |

Scenario Outline: Offer Approval Notification
  Given Im logged in as a user "first_name=Test1" for an entity "name=Urban;entity_type=Company"
  Given the user has role "company_admin"
  And Given I upload an investors file for the company
  # And Given I upload an investor access file for employees
  Given there is a sale "name=Summer Sale"
  Given a esop pool "name=Pool 1" is created with vesting schedule "12:20,24:30,36:50"
  And Given I upload a holdings file
  Then I should see the "Import in progress"
  And when the holdings are approved
  And Given I upload a offer file "offers.xlsx"
  Then I should see the "Import in progress"
  And the offers must have the data in the sheet
  And when the offers are approved
  And offer approval notification is sent
  Then the notification should be sent successfully
  And the sale offered quantity should be "120"
