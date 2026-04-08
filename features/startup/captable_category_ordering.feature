Feature: Cap Table Category Ordering
  As a startup owner or dashboard user
  I want to control the order of categories in the cap table
  So that I can customize the display to emphasize specific investor groups

  Background:
    Given Im logged in as a user "" for an entity "name=Startup Inc;entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "investor_name=Startup Inc;category=Portfolio Company"
    And there are the following investments for "Startup Inc":
      | investor_name | category       | investment_type | funding_round | quantity | price | investment_date |
      | Startup Inc   | Self           | Equity          | Seed          | 1000000  | 0.01  | 2024-01-01      |
      | John Doe      | Employee       | Equity          | Seed          | 100000   | 0.1   | 2024-02-01      |
      | VC Fund       | Founder        | Convertible     | Series A      | 500000   | 1.0   | 2025-01-01      |
      | Angel One     | Other          | Equity          | Seed          | 50000    | 0.1   | 2024-03-01      |

  Scenario: Default ordering by fully diluted quantity (descending)
    When I go to the captable with params ""
    Then I should see the horizontal cap table table
    And I should see categories in quantity-based order

  Scenario: Custom order - Founders first
    When I go to the captable with params "category_order=Self,Employee,Founder,Other"
    Then I should see the horizontal cap table table
    And I should see category "Self" before category "Employee"
    And I should see category "Employee" before category "Founder"
    And I should see category "Founder" before category "Other"

  Scenario: Custom order using plural names
    When I go to the captable with params "category_order=Employees,Others,Founders"
    Then I should see the horizontal cap table table
    And I should see category "Employee" before category "Other"
    And I should see category "Other" before category "Founder"

  Scenario: Partial custom order
    When I go to the captable with params "category_order=Self,Founder"
    Then I should see the horizontal cap table table
    And I should see category "Self" before category "Founder"
    And I should see category "Founder" before category "Employee"

  Scenario: Investor-focused order
    When I go to the captable with params "category_order=Founder,Other,Self,Employee"
    Then I should see the horizontal cap table table
    And I should see category "Founder" before category "Other"
    And I should see category "Other" before category "Self"
    And I should see category "Self" before category "Employee"

  Scenario: Combined - custom order with hidden columns
    When I go to the captable with params "category_order=Self,Employee,Other,Founder&show_quantity_diluted=false"
    Then I should see the horizontal cap table table
    And I should see category "Self" before category "Employee"
    And I should not see the quantity diluted column header
    And I should see the quantity actual column header
