Feature: Cash Flow Assistant Agent
  As a fund manager
  I want the cash flow agent to analyze fund positions and generate reports
  So that I have accurate data to make capital deployment decisions

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is a fund "" for the entity
    And a cash flow support agent is configured for the entity

  Scenario: Fund with healthy cash position produces surplus report
    Given the fund has fresh cash account entries worth 100000000 cents
    And the fund has a proforma investment worth 5000000 cents
    When I run the cash flow agent
    Then a fund report should be saved with status "completed"
    And the fund report should show cash flow status "surplus"
    And the net position should be positive

  Scenario: Fund with stale data is blocked and no calculation is run
    Given the fund has cash account entries that are 45 days old
    When I run the cash flow agent
    Then a fund report should be saved with status "failed"
    And the fund report should show cash flow status "blocked"

  Scenario: Fund with insufficient cash shows shortfall and recommends a capital call
    Given the fund has fresh cash account entries worth 5000000 cents
    And the fund has a proforma investment worth 50000000 cents
    When I run the cash flow agent
    Then a fund report should be saved with status "completed"
    And the fund report should show cash flow status "shortfall"
    And the recommended call amount should be greater than 0

  Scenario: No report recipients configured — email step is skipped
    Given the fund has fresh cash account entries worth 100000000 cents
    And no report recipients are configured
    When I run the cash flow agent
    Then a fund report should be saved with status "completed"
    And no report email should be queued

  Scenario: Recipients configured — report email is queued
    Given the fund has fresh cash account entries worth 100000000 cents
    And report recipients are configured as "manager@example.com"
    When I run the cash flow agent
    Then a fund report should be saved with status "completed"
    And a report email should be queued
