Feature: LP Obligation Matrix UI
  As counsel / a fund manager
  I want to review, approve, and fire side letter obligations from the matrix
  So that the review gate and lifecycle are operable without leaving the browser

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And a fund with a capital commitment exists
    And there is a side letter obligation support agent

  Scenario: Counsel approves a pending obligation from the matrix
    Given a pending "one_time" obligation owned by team "finance" due in 30 days
    When I visit the obligation matrix
    Then I should see the obligation row "Test obligation" with status "Pending review"
    When I approve the obligation from the matrix
    Then the obligation should be approved
    And I should see the obligation row "Test obligation" with status "Active"

  Scenario: Filter the matrix by review status
    Given a pending "one_time" obligation owned by team "finance" due in 30 days
    And an approved armed obligation owned by team "legal" titled "Co-invest right"
    When I visit the obligation matrix filtered by review status "approved"
    Then I should see "Co-invest right" in the matrix
    And I should not see "Test obligation" in the matrix

  Scenario: Fire an armed obligation from the matrix
    Given an approved armed obligation owned by team "legal" titled "Key person notice"
    When I visit the obligation matrix
    And I fire the obligation with due date 5 days from now
    Then exactly 1 task should exist for the obligation
    And the obligation task should be due in 5 days
