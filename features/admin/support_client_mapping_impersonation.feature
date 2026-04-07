Feature: Support Client Mapping Impersonation (Switch/Revert)
  As a support user
  I want to switch into a client entity context
  So that I can provide support as if I were a company admin

  Background:
    Given a user exists with role "support"
    And an entity exists with employees
    And a support client mapping exists linking the support user to the entity
    And the mapping is enabled
    And I am logged in as the support user

  Scenario: Successful Switch into Client Entity
    When I switch to the client entity context
    Then my current entity should be the client entity
    And I should have the "company_admin" role
    And my original state should be cached in json_fields

  Scenario: Successful Revert to Original Entity
    Given I have switched to the client entity context
    When I revert to my original entity context
    Then my current entity should be my original entity
    And I should have the "support" role
    And I should not have the "company_admin" role
    And my original state should be cleared from json_fields

  Scenario: Status Reporting (Switched vs Reverted)
    When I check my mapping status
    Then it should be "Reverted"
    When I switch to the client entity context
    And I check my mapping status
    Then it should be "Switched"
    When I revert to my original entity context
    And I check my mapping status
    Then it should be "Reverted"

  Scenario: Login Delegation (allow_login_as)
    Given the mapping has user_emails "allowed@test.com"
    And enable_user_login is true
    When I check if I can login as "allowed@test.com"
    Then it should return true
    When I check if I can login as "blocked@test.com"
    Then it should return false
