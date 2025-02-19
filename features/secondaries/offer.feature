Feature: Offer
  Can create and view a offers as a company employee


Scenario Outline: Place an offer
  Given there is a user "first_name=John" for an entity "entity_type=Company"
  Given there is an existing investor "investor_name=Seller" with "1" users
  Given Im logged in as an investor
  Given there is a sale "<sale>"
  Given I have "Seller" access to the sale
  And I am at the sales details page
  Then when I place an offer "<offer>" from the offers tab
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
    |name=Grand Sale;percent_allowed=100  |quantity=100;price=1000        | 100            |
    |name=Winter Sale;percent_allowed=100 |quantity=50;price=1000         | 50             |



Scenario Outline: Approve offers as a company
  Given Im logged in as a user "" for an entity "<entity>"
  And the user has role "approver,company_admin"
  Given there is an existing investor "investor_name=Seller" with "1" users
  Given there is a sale "<sale>"
  And there is an "unapproved" offer "quantity=100;price=1000" for each investor
  And I am at the sales details page
  Then I should see all the offers
  And the sales total_offered_quantity should be "0"
  And When I approve the offers the offers should be approved
  And the sales total_offered_quantity should be "100"
Examples:
    |entity               |sale                                 |
    |entity_type=Company  |name=Grand Sale;percent_allowed=100  |
    |entity_type=Company  |name=Winter Sale;percent_allowed=100 |



@import
Scenario Outline: Import offer to sale
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
  Given there is a sale "<sale>"
  Given Im logged in as a user "first_name=Emp1" for an entity "entity_type=Investor;pan=1234567"
  Given my firm is an investor in the company
  And the investor has "Seller" access rights to the sale    
  And I am at the sales details page
  Then when I place an offer "<offer>" from the offers tab
  Then I should see the offer details
  Given Offer PAN verification is enabled
  And I add pan details to the offer
  Then Pan Verification is triggered
  And when the offer name is updated
  Then Pan Verification is triggered
  And when the offer PAN is updated
  Then Pan Verification is triggered


Examples:
|sale                                      |offer	                        |
    |name=Grand Sale;percent_allowed=100   |quantity=100;price=1000        |


Scenario Outline: Offer Bank verification
    Given there is a user "" for an entity "entity_type=Company"
    Given there is an existing investor "investor_name=Seller" with "1" users
    Given Im logged in as an investor
    Given there is a sale "<sale>"
    Given I have "Seller" access to the sale
    And I am at the sales details page
    Given Offer Bank verification is enabled
    Then when I place an offer "<offer>" from the offers tab
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
      |sale                                  | offer	             |
      |name=Grand Sale;percent_allowed=100   |quantity=100;price=1000        |

Scenario Outline: Offer Approval Notification
  Given Im logged in as a user "first_name=Test1" for an entity "name=Urban;entity_type=Company"
  Given the user has role "company_admin"
  And Given I upload an investors file for the company
  And Given I upload an investor access file for employees
  Given there is a sale "name=Summer Sale"
  And Given I upload a offer file "offers_no_holdings.xlsx"
  Then I should see the "Import in progress"
  And the offers must have the data in the sheet
  And when the offers are approved
  And offer approval notification is sent
  Then the notification should be sent successfully
  And the sale offered quantity should be "120"
