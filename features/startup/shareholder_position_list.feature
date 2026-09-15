Feature: Shareholder Positions list view
  As a startup dashboard user
  I want to see every uploaded shareholder position row for a portfolio company
  So I can review exactly what was uploaded, independent of the cap table roll-up

  Background:
    Given Im logged in as a user "" for an entity "name=Startup Inc;entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "investor_name=Startup Inc;category=Portfolio Company"
    And there is an investor named "Jack"

  Scenario: Lists the uploaded shareholder position row as-is, with its raw Fully Diluted and Quantity Actual values
    Given there are the following shareholder positions for "Startup Inc":
      | investor_name | category | position_date | position_amount | quantity_actual |
      | Jack          | Founder  | 2025-01-31    | 10               | 5                |
    When I visit the shareholder positions list for "Startup Inc"
    Then I should see a shareholder position row for "Jack" with category "Founder", fully diluted "10.00", and quantity actual "5.00"
