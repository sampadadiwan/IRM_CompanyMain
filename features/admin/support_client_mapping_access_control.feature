Feature: Support Client Mapping Access Control (Policy)
  As an admin or support user
  I want to ensure support client mappings are only accessible to authorized users
  So that support access is strictly controlled

  Background:
    Given a user exists with role "super"
    And a user exists with role "support"
    And an entity exists with employees
    And a support client mapping exists linking the support user to the entity
    And the mapping is enabled

  Scenario: Super user can see all mappings
    Given I am logged in as the super user
    When I view the support client mappings index
    Then I should see all mappings in the system

  Scenario: Support user can only see their own mappings
    Given another user exists with role "support"
    And another support client mapping exists linking that user to the same entity
    And I am logged in as the support user
    When I view the support client mappings index
    Then I should only see my own mappings

  Scenario: Unauthorized user cannot see mappings
    Given a user exists with role "employee"
    And I am logged in as the employee user
    When I view the support client mappings index
    Then I should be denied access to the mapping

  Scenario: Support user cannot switch if mapping is disabled
    Given the mapping is disabled
    And I am logged in as the support user
    When I try to switch to the client entity context
    Then I should be denied access to the mapping
