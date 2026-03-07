Feature: User Access Rights Cache Reset
  In order to ensure access rights are correctly cached
  As a company admin
  I want to be able to reset the access rights cache for a user

  Scenario: Reset access rights cache for an employee
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"
    And an employee exists for the entity
    And I am at the users page
    And I click on the employee's name
    Then I should see "Reset Access Rights Cache"
    When I click on "Reset Access Rights Cache"
    Then I should see "Access rights cache reset has been enqueued"
    And a background job "ResetAccessRightsCacheJob" should be enqueued
