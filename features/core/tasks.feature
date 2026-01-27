Feature: Tasks
  As a user
  I want to manage tasks
  So that I can keep track of my work

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"

  Scenario: Create a new task
    Given I am at the tasks page
    When I create a new task with details "Complete the audit report" and due date "2026-12-31"
    Then a task should be created with details "Complete the audit report"
    And I should see "Complete the audit report"

  Scenario: Filter tasks by completion status
    Given the following tasks exist:
      | details            | completed |
      | Task 1 (Done)      | true      |
      | Task 2 (Pending)   | false     |
    And I am at the tasks page
    When I filter by "Incomplete"
    Then I should see "Task 2 (Pending)"
    And I should not see "Task 1 (Done)"
    When I filter by "Show All"
    Then I should see "Task 1 (Done)"
    And I should see "Task 2 (Pending)"

  Scenario: Task notification
    Given I am at the tasks page
    When I create a new task and assign it to "me" with details "Complete the audit report"
    Then an email should be sent to "me" with subject "Complete the audit report, Status: Open"
