Feature: Task Category Filtering
  As a user
  I want to filter tasks by category
  To manage my workload effectively

  Background:
    Given Im logged in as a user "first_name=John;email=employee@example.com" for an entity "name=Acme Fund;entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there are following tasks for the entity:
      | details        | category   |
      | Finance task 1 | Finance    |
      | Ops task 1     | Ops        |
      | IR task 1      | IR         |
      | Other task 1   | Other      |

  @javascript
  Scenario: Filter tasks by category from the index page dropdown
    When I go to the tasks page
    And I select "Finance" from the category filter dropdown
    Then I should see "Finance task 1"
    And I should not see "Ops task 1"

  @javascript
  Scenario: Filter tasks by category from the sidebar menu
    When I go to the dashboard page
    And I click on "Tasks" in the sidebar
    And I click on "All Tasks" in the sidebar
    And I click on "Finance Tasks" in the sidebar
    Then I should see "Finance task 1"
    And I should not see "Ops task 1"

  @javascript
  Scenario: Stats should respect category filter
    When I go to the tasks page
    And I select "Finance" from the category filter dropdown
    Then I should see "0" in the "Completed" stat card
    And I should see "1" in the "Incomplete" stat card
