Feature: Secondary Sale
  Can create and view a sale as a company

Scenario Outline: Sale Allocation
  Given Im logged in as a user "first_name=Emp1" for an entity "entity_type=Company"
  Given the user has role "company_admin"
  Given there is a sale "<sale>"
  And Given I upload an investors file for the company
  And Given I upload an investor access file for employees
  And Given I upload a offer file "offers_allocate.xlsx"
  And when the offers are approved
  And given I upload an interests file "interests_allocate.xlsx"
  Then when the allocation is done
  Then the sale must be allocated as per the file "matched_allocations.xlsx"
  And the allocations must be visible
  And when the allocations are verified "true"
  Then the allocations must be verified "true"
  And the corresponding offers must verified "true"
  And the corresponding interests must verified "true"
  
  Examples:
  	|sale                                     |
  	|name=Grand Sale;price_type=Price Range;min_price=500000;max_price=1100000|
    