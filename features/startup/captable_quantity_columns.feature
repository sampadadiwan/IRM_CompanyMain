Feature: Cap Table Quantity Columns Visibility
  As a startup owner or dashboard user
  I want to control the visibility of quantity columns in the cap table widget
  So that I can customize the cap table display based on my needs

  Background:
    Given Im logged in as a user "" for an entity "name=Startup Inc;entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "investor_name=Startup Inc;category=Portfolio Company"
    And there are the following investments for "Startup Inc":
      | investor_name | category | investment_type | funding_round | quantity | price | investment_date |
      | Startup Inc   | Self     | Equity          | Seed          | 1000000  | 0.01  | 2024-01-01      |
      | John Doe      | Employee | Equity          | Seed          | 100000   | 0.1   | 2024-02-01      |
      | VC Fund       | Other    | Convertible     | Series A      | 200000   | 1.0   | 2025-01-01      |

  Scenario: View cap table with both quantity columns visible (default)
    When I go to the captable with params ""
    Then I should see the horizontal cap table table
    And I should see the quantity actual column header
    And I should see the quantity diluted column header

  Scenario: View cap table with show_quantity_actual=true and show_quantity_diluted=true
    When I go to the captable with params "show_quantity_actual=true&show_quantity_diluted=true"
    Then I should see the horizontal cap table table
    And I should see the quantity actual column header
    And I should see the quantity diluted column header

  Scenario: Hide both quantity columns
    When I go to the captable with params "show_quantity_actual=false&show_quantity_diluted=false"
    Then I should see the horizontal cap table table
    And I should not see the quantity actual column header
    And I should not see the quantity diluted column header

  Scenario: Show only quantity actual column
    When I go to the captable with params "show_quantity_actual=true&show_quantity_diluted=false"
    Then I should see the horizontal cap table table
    And I should see the quantity actual column header
    And I should not see the quantity diluted column header

  Scenario: Show only quantity diluted column
    When I go to the captable with params "show_quantity_actual=false&show_quantity_diluted=true"
    Then I should see the horizontal cap table table
    And I should not see the quantity actual column header
    And I should see the quantity diluted column header

  Scenario: Hide only quantity actual column
    When I go to the captable with params "show_quantity_actual=false"
    Then I should see the horizontal cap table table
    And I should not see the quantity actual column header
    And I should see the quantity diluted column header

  Scenario: Hide only quantity diluted column
    When I go to the captable with params "show_quantity_diluted=false"
    Then I should see the horizontal cap table table
    And I should see the quantity actual column header
    And I should not see the quantity diluted column header
