Feature: Recurring Task Generation
  In order to manage long-term responsibilities
  As a user
  I want recurring tasks to be automatically generated for future dates

  Background:
    Given there is a user "" for an entity ""

  @javascript
  Scenario: Successfully generating recurring tasks until the end of the quarter
    Given a task recurrence rule exists for entity with:
      | details               | FREQ=WEEKLY;INTERVAL=1 |
      | category              | Compliance             |
      | start_date            | 2026-02-12             |
    When the recurring task generator job runs
    Then there should be 20 tasks created for the recurrence rule
    And each task should have the correct original_start_date
    And the task recurrence rule should have generated_until set to the end of the quarter

  @javascript
  Scenario: Do not duplicate existing tasks
    Given a task recurrence rule exists for entity with:
      | details               | FREQ=MONTHLY;INTERVAL=1 |
      | category              | Finance                 |
      | start_date            | 2026-02-01              |
    And a task already exists for the recurrence rule on "2026-02-01"
    When the recurring task generator job runs
    Then there should be only 5 tasks in total for the recurrence rule
    And no task should be duplicated for "2026-02-01"

  @javascript
  Scenario: Respect end_date of recurrence rule
    Given a task recurrence rule exists for entity with:
      | details               | FREQ=DAILY;INTERVAL=1 |
      | category              | Ops                   |
      | start_date            | 2026-02-01            |
      | end_date              | 2026-02-05            |
    When the recurring task generator job runs
    Then there should be exactly 5 tasks created for the recurrence rule

  @javascript
  Scenario: Creating and Editing recurring and non-recurring tasks via UI
    Given Im logged in as a user "" for an entity "name=Acme Corp"
    Given the user has role "company_admin"
    And I am at the tasks page

    # 1. Create a recurring task (One-click checkbox)
    When I click "New Task" within ".task_header"
    And I fill in task "task_details" with "Monthly Report"
    And I check "make_recurring"
    And I select "Monthly" from "recurrence_pattern"
    And I fill in task "recurrence_interval" with "1"
    And I click "Save" within ".task_form"
    Then I should see "Task was successfully created."
    And the last task should be recurring

    # 2. Create a non-recurring task
    When I click "New Task" within ".task_header"
    And I fill in task "task_details" with "One-time Task"
    # Ensure checkbox is visible but not checked
    And "make_recurring" should be visible
    And "make_recurring" should not be checked
    And I click "Save" within ".task_form"
    Then I should see "Task was successfully created."
    And the last task should not be recurring

    # 3. Edit a non-recurring task and make it recurring
    When I click "Edit" for the task "One-time Task"
    And I check "make_recurring"
    And I select "Weekly" from "recurrence_pattern"
    And I click "Save" within ".task_form"
    Then I should see "Task was successfully updated."
    And the task "One-time Task" should be recurring

    # 4. Edit a recurring task and make it non-recurring
    When I click "Edit" for the task "Monthly Report"
    And I uncheck "make_recurring"
    And I click "Save" within ".task_form"
    Then I should see "Task was successfully updated."
    And the task "Monthly Report" should not be recurring

  @javascript
  Scenario: Delete entire series of recurring tasks
    Given Im logged in as a user "" for an entity "name=Acme Corp"
    Given the user has role "company_admin"
    And a task recurrence rule exists for entity with:
      | details               | FREQ=DAILY;INTERVAL=1 |
      | category              | Ops                   |
      | start_date            | 2026-02-01            |
    And the recurring task generator job runs
    And I am at the tasks page

    When I click "Show" for the task "FREQ=DAILY;INTERVAL=1"
    Then I should see "Delete Series"

    When I click "Delete Series"
    # The confirmation popup is handled by click->confirm#popup, which usually needs accept_confirm in capybara
    # In some cucumber setups, confirmation is auto-accepted or handled by a step
    Then I should see "Entire task series was successfully destroyed."
    And there should be 0 tasks created for the recurrence rule
