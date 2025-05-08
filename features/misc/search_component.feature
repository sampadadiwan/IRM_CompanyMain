Feature: SearchComponent
  Test behavior of the Search Component


Scenario Outline: Create investors and search with search component
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And Given I upload an investors file for the company
  And the investors have approved investor access
  And Given I upload an investor kyc "investor_kycs.xlsx" for employees
  Then I should see the "Import in progress"
  Then There should be "4" investor kycs created
  When I go to the Investor Kycs index page
  And I filter the investors with "<filter>"
  Then I should see the filtered investors with "<filter>"
  And I filter the investors with "<filter2>"
  Then I should see the filtered investors with "<filter2>"
Examples:
  |filter  |filter2|
  |Import 1|Import 2|
