Feature: Cash Flow Expense Estimator
  As a fund manager
  I want expenses to be forecast using the best available historical method
  So that cash runway calculations reflect realistic future outflows

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is a fund "" for the entity
    And a cash flow support agent is configured for the entity

  Scenario: No historical expense data returns zero forecast
    Given the fund has no expense account entries
    When I run the expense estimator for 90 days
    Then the estimation method should be "no_data"
    And the estimated total should be 0

  Scenario: One month of data uses last snapshot method
    Given the fund has expense account entries for 1 month
    When I run the expense estimator for 90 days
    Then the estimation method should be "last_snapshot"
    And the estimated total should be greater than 0

  Scenario: Two months of data uses weighted average method
    Given the fund has expense account entries for 2 months
    When I run the expense estimator for 90 days
    Then the estimation method should be "weighted_average"
    And the estimated total should be greater than 0

  Scenario: Three months of data uses weighted average method
    Given the fund has expense account entries for 3 months
    When I run the expense estimator for 90 days
    Then the estimation method should be "weighted_average"

  Scenario: Four or more months of data uses linear regression
    Given the fund has expense account entries for 6 months
    When I run the expense estimator for 90 days
    Then the estimation method should be "linear_regression"
    And the estimated total should be greater than 0

  Scenario: Growing expense trend produces increasing monthly predictions
    Given the fund has growing expense account entries for 6 months
    When I run the expense estimator for 90 days
    Then the estimation method should be "linear_regression"
    And each monthly prediction should be greater than the previous
