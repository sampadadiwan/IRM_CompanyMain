Feature: Deal Investor Row Actions
  Every row in the deal's investor grid carries a caret next to the investor name.
  It opens a menu with View / Edit / Add Note / Add Task, each of which drives the
  investor sidepanel.

  The grid sorts on last_interaction_date — a date the user asserts, not a timestamp
  we observe. A note moves its investor only when it carries an "On" date later than
  the one already recorded; a task moves its investor only when it is completed.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"
    And there is an existing investor ""
    And there exists a deal "name=Row Actions Deal;amount_cents=100000" for my company
    And there is a deal investor for the last investor

  Scenario: View a deal investor from the row actions menu
    Given I visit the deal list view
    When I open the row actions menu for the deal investor
    And I choose "View" from the row actions menu
    Then the investor sidepanel should show the deal investor details
    When I expand the deal investor details card
    Then the investor sidepanel should show the deal investor details

  Scenario: Edit a deal investor from the row actions menu
    Given I visit the deal list view
    When I open the row actions menu for the deal investor
    And I choose "Edit" from the row actions menu
    Then the investor sidepanel should show the deal investor edit form
    When I set the deal investor tier to "3" in the sidepanel and save
    Then the deal investor tier should be "3"

  Scenario: Add a note from the row actions menu
    Given I visit the deal list view
    When I open the row actions menu for the deal investor
    And I choose "Add Note" from the row actions menu
    Then the note form should open in the sidepanel
    When I fill in the note details with "Followed up on the term sheet" and save
    Then the deal investor should have a note "Followed up on the term sheet"
    And the note form should be closed

  Scenario: Cancel the note form opened from the row actions menu
    Given I visit the deal list view
    When I open the row actions menu for the deal investor
    And I choose "Add Note" from the row actions menu
    Then the note form should open in the sidepanel
    When I cancel the note form
    Then the note form should be closed
    And the deal investor should have no notes

  Scenario: Add a task from the row actions menu
    Given I visit the deal list view
    When I open the row actions menu for the deal investor
    And I choose "Add Task" from the row actions menu
    Then the task form should open in the sidepanel
    When I fill in the task details with "Send the updated SHA" and save
    Then the deal investor should have a task "Send the updated SHA"
    And the task form should be closed

  Scenario: Cancel the task form opened from the row actions menu
    Given I visit the deal list view
    When I open the row actions menu for the deal investor
    And I choose "Add Task" from the row actions menu
    Then the task form should open in the sidepanel
    When I cancel the task form
    Then the task form should be closed
    And the deal investor should have no tasks

  Scenario: A deal investor with a note dated today sorts to the top of the grid
    Given the deal has investors named "Alpha Capital, Beta Ventures"
    And I visit the deal list view
    And the deal investor "Beta Ventures" should be the first row in the investor grid
    When I open the row actions menu for "Alpha Capital"
    And I choose "Add Note" from the row actions menu
    Then the note form should open in the sidepanel
    When I fill in the note details with "Diligence call done" dated today and save
    And I visit the deal list view
    Then the deal investor "Alpha Capital" should be the first row in the investor grid
    And the deal investor "Alpha Capital" last interaction date should be today

  Scenario: A backdated note does not move the deal investor
    Given the deal has investors named "Epsilon Capital, Zeta Ventures"
    And the deal investor "Zeta Ventures" last interacted "today"
    And I visit the deal list view
    And the deal investor "Zeta Ventures" should be the first row in the investor grid
    When I open the row actions menu for "Epsilon Capital"
    And I choose "Add Note" from the row actions menu
    Then the note form should open in the sidepanel
    When I fill in the note details with "Old meeting minutes" dated "2020-01-01" and save
    And I visit the deal list view
    Then the deal investor "Zeta Ventures" should be the first row in the investor grid

  Scenario: A deal investor sorts to the top only once its task is completed
    Given the deal has investors named "Gamma Partners, Delta Fund"
    And the deal investor "Delta Fund" last interacted "yesterday"
    And I visit the deal list view
    And the deal investor "Delta Fund" should be the first row in the investor grid
    When I open the row actions menu for "Gamma Partners"
    And I choose "Add Task" from the row actions menu
    Then the task form should open in the sidepanel
    When I fill in the task details with "Chase the signed NDA" and save
    And I visit the deal list view
    Then the deal investor "Delta Fund" should be the first row in the investor grid
    And the deal investor "Gamma Partners" should have no last interaction date
    When I complete the task for "Gamma Partners" from the sidepanel
    And I visit the deal list view
    Then the deal investor "Gamma Partners" should be the first row in the investor grid
    And the deal investor "Gamma Partners" last interaction date should be today
