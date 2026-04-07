Feature: Support Client Mapping Edge Cases
  As an admin or support user
  I want to ensure support client mappings handle edge cases correctly
  So that the system remains stable and secure even in unusual scenarios

  Background:
    Given a user exists with role "support"
    And an entity exists with employees
    And a support client mapping exists linking the user to the entity

  Scenario: Support user is locked in when mapping is disabled while switched
    Given the mapping is enabled
    And the user has switched
    When the mapping is disabled
    Then calling revert should raise an error "Cannot revert a disabled mapping"

  Scenario: Concurrent mappings for the same entity
    Given another user exists with role "support"
    And another support client mapping exists linking that user to the same entity
    And both mappings are enabled
    When I disable the first mapping
    Then the first mapping should be disabled
    And the entity should still have enable_support permission
    And all employees should still have enable_support set to true

  Scenario: Reverting with missing original entity information
    Given the mapping is enabled
    And the user has switched
    And the user's original entity information is lost
    Then calling revert should raise an error "No previous entity to revert to"

  Scenario: Switching when entity support is manually disabled
    Given the mapping is enabled
    And the entity's support permission is manually disabled
    Then calling switch should raise an error "Cannot switch a disabled mapping"

  Scenario: Support role removed while switched
    Given the mapping is enabled
    And the user has switched
    When the user's support role is removed
    Then the user should still be able to revert via the mapping

  Scenario: Deleting the last mapping should disable entity support
    Given the mapping is enabled
    When I delete the mapping
    Then the entity should not have enable_support permission
    And all employees should have enable_support set to false
