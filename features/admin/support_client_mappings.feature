Feature: Support Client Mappings
  As an admin or support user
  I want to manage support client mappings
  So that entity-user support relationships are correctly enforced

  Background:
    Given a user exists with role "support"
    And an entity exists with employees
    And a support client mapping exists linking the user to the entity

  Scenario: Mapping string representation
    When I call to_s on the support client mapping
    Then I should see the support mapping "<user> - <entity>"

  Scenario: Enable support
    Given the mapping is disabled
    When I enable the mapping
    Then the mapping should be enabled
    And the entity should have enable_support permission
    And all employees should have enable_support set to true

  Scenario: Disable expired support
    Given the mapping is enabled
    And it has an end_date in the past
    When I call disable_expired
    Then the mapping should be disabled
    And the entity should not have enable_support permission

  Scenario: Switch user entity
    Given the mapping is enabled
    When I call switch
    Then the user's entity should be updated to the mapped entity
    And the user should gain the company_admin role

  Scenario: Revert user entity
    Given the mapping is enabled
    And the user has switched
    When I call revert
    Then the user's entity should be reset to the original
    And the user should have the support role
    And the company_admin role should be removed

  Scenario: Status reporting
    Given the mapping is enabled
    And the user has switched
    When I check the mapping status
    Then it should be "Switched"
    When the user reverts
    Then it should be "Reverted"

  Scenario: Allow login as
    Given the mapping has user_emails "a@test.com, b@test.com"
    And enable_user_login is true
    When I call allow_login_as with "a@test.com"
    Then it should return true
    When I call allow_login_as with "c@test.com"
    Then it should return false