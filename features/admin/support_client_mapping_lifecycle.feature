Feature: Support Client Mapping Lifecycle and CRUD
  As a super admin
  I want to manage the full lifecycle of support client mappings
  So that support access is strictly controlled and automated

  Background:
    Given a user exists with role "super"
    And a user exists with role "support"
    And an entity exists with employees
    And I am logged in as the super user

  @rack_test
  Scenario: Creating a new support client mapping
    When I create a support client mapping for the support user and entity
    Then the mapping should be created successfully
    And the mapping should be enabled
    And the entity should have enable_support permission
    And all employees should have enable_support set to true

  @rack_test
  Scenario: Updating an existing mapping
    Given a support client mapping exists linking the support user to the entity
    When I update the mapping's end_date to tomorrow
    Then the mapping should be updated successfully
    And the end_date should be tomorrow

  @rack_test
  Scenario: Manually disabling a mapping
    Given a support client mapping exists linking the support user to the entity
    And the mapping is enabled
    When I manually disable the mapping
    Then the mapping should be disabled
    And the entity should not have enable_support permission
    And all employees should have enable_support set to false

  @rack_test
  Scenario: Deleting a mapping (Cascading Cleanup)
    Given a support client mapping exists linking the support user to the entity
    And the mapping is enabled
    When I delete the support client mapping
    Then the mapping should no longer exist
    And the entity should not have enable_support permission
    And all employees should have enable_support set to false

  @rack_test
  Scenario: Automatic expiration via Daily Job
    Given a support client mapping exists linking the support user to the entity
    And the mapping is enabled
    And the mapping's end_date is in the past
    When the SCM daily morning job runs
    Then the mapping should be disabled
    And the entity should not have enable_support permission

  Scenario: Automatic cleanup of old disabled mappings
    Given a support client mapping exists linking the support user to the entity
    And the mapping is disabled
    And the mapping's end_date was 2 weeks ago
    When the SCM daily morning job runs
    Then the mapping should no longer exist
