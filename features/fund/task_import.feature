Feature: Import Task
  Can bulk import tasks and recurring tasks

@import
Scenario: Import tasks and recurring tasks
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And Given I upload a "tasks.xlsx" file for "Task"
  Then There should be "2" tasks created with data in "tasks.xlsx"
  And There should be "1" task recurrence rules created with data in "tasks.xlsx"

  And Given I upload a "tasks_update.xlsx" file for "Task"
  Then There should be "2" tasks created with data in "tasks_update.xlsx"
  And There should be "1" task recurrence rules created with data in "tasks_update.xlsx"
