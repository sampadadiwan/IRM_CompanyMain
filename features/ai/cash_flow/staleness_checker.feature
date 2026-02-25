Feature: Cash Flow Staleness Checker
  As a fund manager
  I want the system to detect stale cash flow data before running analysis
  So that reports are never generated from outdated figures

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is a fund "" for the entity
    And a cash flow support agent is configured for the entity

  Scenario: Fund with fresh cash data is ready
    Given the fund has cash account entries that are 5 days old
    When I run the staleness checker
    Then the fund result status should be "ready"
    And there should be no block reasons

  Scenario: Fund with stale cash data is blocked
    Given the fund has cash account entries that are 45 days old
    When I run the staleness checker
    Then the fund result status should be "blocked"
    And the block reasons should mention "Cash"
    And the block reasons should mention "45d old"

  Scenario: Fund with no cash data at all is blocked
    Given the fund has no cash account entries
    When I run the staleness checker
    Then the fund result status should be "blocked"
    And the block reasons should mention "No cash data"

  Scenario: Fund with stale proforma investment is blocked
    Given the fund has cash account entries that are 5 days old
    And the fund has a proforma investment that is 100 days old
    When I run the staleness checker
    Then the fund result status should be "blocked"
    And the block reasons should mention "Proforma"

  Scenario: Custom staleness threshold is respected
    Given the fund has cash account entries that are 20 days old
    And the staleness threshold for cash is 15 days
    When I run the staleness checker
    Then the fund result status should be "blocked"
    And the block reasons should mention "20d old"
