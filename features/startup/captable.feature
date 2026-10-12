@rack_test
Feature: Cap Table Generation
  As a startup owner
  I want to see my cap table and ownership trends
  So that I can track dilution over time

  Background:
    Given Im logged in as a user "" for an entity "name=Startup Inc;entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "investor_name=Startup Inc;category=Portfolio Company"

  Scenario: View incremental cap table
    Given there are the following investments for "Startup Inc":
      | investor_name | category | investment_type | funding_round | quantity | price | investment_date |
      | Startup Inc   | Self     | Equity          | Seed          | 1000000  | 0.01  | 2024-01-01      |
      | John Doe      | Employee | Equity          | Seed          | 100000   | 0.1   | 2024-02-01      |
      | VC Fund       | Other    | Convertible     | Series A      | 200000   | 1.0   | 2025-01-01      |
    When I go to the captable of the portfolio company
    Then I should see "Seed" funding round cap table
    And I should see "Series A" funding round cap table
    And I should see "100.0%" total percentage for "Seed"

  Scenario: View horizontal cap table
    Given there are the following investments for "Startup Inc":
      | investor_name | category | investment_type | funding_round | quantity | price | investment_date |
      | Startup Inc   | Self     | Equity          | Seed          | 1000000  | 0.01  | 2024-01-01      |
      | John Doe      | Employee | Equity          | Seed          | 100000   | 0.1   | 2024-02-01      |
    When I go to the captable of the portfolio company
    Then I should see the horizontal cap table table
    And I should see "Startup Inc" with "90.9%" stake in "Seed" round
