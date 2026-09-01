Feature: Task Due Date Filtering
  As a user
  I want to filter tasks by due date
  To focus on what is overdue or coming up

  Background:
    Given Im logged in as a user "first_name=John;email=employee@example.com" for an entity "name=Acme Fund;entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there are following board tasks due in each period

  @javascript
  Scenario: Filter tasks by due date from the index page dropdown
    When I go to the tasks page
    And I select "Overdue" from the due date filter dropdown
    Then I should see "Overdue task"
    And I should not see "Task due this week"
    And I should not see "Task due this month"
    When I select "Due This Month" from the due date filter dropdown
    Then I should see "Task due this month"
    And I should not see "Overdue task"
    And I should not see "Task due next month"

  # The due date filter is a plain param (not a ransack predicate), so it has
  # to be carried explicitly across the List <-> Board links, same as any
  # other filter — this proves that wiring rather than just TaskList itself.
  @javascript
  Scenario: Switching from the list to the board keeps the due date filter
    When I go to the tasks page
    And I select "Due This Month" from the due date filter dropdown
    And I click on "Board"
    Then I should see "Task due this month" in the "Todo" board column
    And I should not see "Overdue task" in the "Todo" board column

  # Regression: the stat cards used to compute their own scope from scratch,
  # which (a) ignored due_filter entirely and (b) turned an unselected board
  # select ("assigned_to_id=") into `WHERE assigned_to_id = ''`, zeroing every
  # card outright — see _stats.html.erb.
  @javascript
  Scenario: Board stat cards reflect the due date filter
    When I go to the tasks board page
    And I select "Overdue" from the board "due_filter" filter
    Then I should see "1" in the "Delayed" stat card
