Feature: Tasks Kanban Board
  As a user
  I want a kanban board view of my tasks
  So I can see and update their workflow status at a glance

  Background:
    Given Im logged in as a user "first_name=John;email=admin@example.com" for an entity "name=Acme Fund;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing investor "investor_name=Blue Fort Capital"
    And there is a contact "maya@bluefort.com" named "Maya Kapoor" for the investor
    And there are following board tasks for the entity:
      | details          | status      | stakeholder | contact           | assigned_to       | tags   |
      | Draft the LPA    | todo        |             |                   |                   | legal  |
      | Call the auditor | todo        |             |                   | admin@example.com |        |
      | Chase signatures | in_progress | yes         | maya@bluefort.com |                   |        |
      | Send the deck    | todo        | yes         |                   |                   |        |
      | File the report  | done        |             |                   |                   |        |

  Scenario: Tasks appear on the board grouped by status
    When I go to the tasks board page
    Then I should see "Draft the LPA" in the "Todo" board column
    And I should see "Chase signatures" in the "In Progress" board column
    And I should see "File the report" in the "Done" board column
    And I should not see "File the report" in the "Todo" board column

  Scenario: Switch between the list and board views
    When I go to the tasks page
    And I click on "Board"
    Then I should see "Tasks Board"
    When I click on "List"
    Then I should see the tasks list

  @javascript
  Scenario: Filter the board by assignee
    When I go to the tasks board page
    And I select "John" from the board "assigned_to_id" filter
    Then I should see "Call the auditor" in the "Todo" board column
    And I should not see "Draft the LPA" in the "Todo" board column

  @javascript
  Scenario: Filter the board by stakeholder and contact
    When I go to the tasks board page
    And I select "Blue Fort Capital" from the board "investor_id" filter
    Then I should see "Chase signatures" in the "In Progress" board column
    And I should not see "Draft the LPA" in the "Todo" board column
    When I select "Maya Kapoor (maya@bluefort.com)" from the board "touch_point_id" filter
    Then I should see "Chase signatures" in the "In Progress" board column
    And I should not see "Send the deck" in the "Todo" board column

  @javascript
  Scenario: Filter the board by tag
    When I go to the tasks board page
    And I select "legal" from the board "q[tags_cont]" filter
    Then I should see "Draft the LPA" in the "Todo" board column
    And I should not see "Call the auditor" in the "Todo" board column

  @javascript
  Scenario: Dragging a card to Done completes the task without emailing anyone
    When I go to the tasks board page
    And I drag the "Draft the LPA" board card to the "Done" column
    Then I should see "Draft the LPA" in the "Done" board column
    And the task "Draft the LPA" should be completed
    And no new task emails should have been sent

  @javascript
  Scenario: Completing a task from the list moves its card to Done
    When I go to the tasks page
    And I toggle the completed checkbox for the task "Draft the LPA"
    And I go to the tasks board page
    Then I should see "Draft the LPA" in the "Done" board column

  @javascript
  Scenario: Un-completing a task from the list moves its card back to To Do
    When I go to the tasks page showing all tasks
    And I toggle the completed checkbox for the task "File the report"
    And I go to the tasks board page
    Then I should see "File the report" in the "Todo" board column
