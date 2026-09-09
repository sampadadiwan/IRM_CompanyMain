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
    And I select "John" from the task "assigned_to_id" filter
    Then I should see "Call the auditor" in the "Todo" board column
    And I should not see "Draft the LPA" in the "Todo" board column

  @javascript
  Scenario: Filter the board by stakeholder and contact
    When I go to the tasks board page
    And I pick "Blue Fort Capital" in the stakeholder filter
    Then I should see "Chase signatures" in the "In Progress" board column
    And I should not see "Draft the LPA" in the "Todo" board column
    When I select "Maya Kapoor (maya@bluefort.com)" from the task "touch_point_id" filter
    Then I should see "Chase signatures" in the "In Progress" board column
    And I should not see "Send the deck" in the "Todo" board column

  # Regression: a task logged under a stakeholder's PortfolioInvestment ("PI")
  # or CapitalCommitment has owner_type=PortfolioInvestment/CapitalCommitment,
  # not owner_type=Investor — the stakeholder filter must still surface it.
  @javascript
  Scenario: Filter the board by stakeholder includes tasks logged under its PI and Commitment
    Given the investor has a portfolio investment and a capital commitment
    And there are following board tasks for the entity:
      | details                         | status | stakeholder |
      | Chase the PI signoff            | todo   | pi          |
      | Chase the commitment paperwork  | todo   | commitment  |
    When I go to the tasks board page
    And I pick "Blue Fort Capital" in the stakeholder filter
    Then I should see "Chase the PI signoff" in the "Todo" board column
    And I should see "Chase the commitment paperwork" in the "Todo" board column
    And I should not see "Draft the LPA" in the "Todo" board column

  # A deal board is the whole deal: tasks owned by the Deal itself plus tasks
  # owned by every DealInvestor on it.
  Scenario: The deal board shows the deal's own tasks and its investors' tasks together
    Given the investor is in an open deal
    And there are following deal board tasks:
      | details               | owner         | status      |
      | Prepare the data room | deal          | todo        |
      | Chase Blue Fort KYC   | deal_investor | in_progress |
    When I go to the tasks board page for the deal
    Then I should see "Prepare the data room" in the "Todo" board column
    And I should see "Chase Blue Fort KYC" in the "In Progress" board column
    And I should not see "Draft the LPA" in the "Todo" board column
    And the deal tasks tab should offer a board link for the whole deal

  @javascript
  Scenario: Filter the deal board to one investor on the deal
    Given the investor is in an open deal
    And there are following deal board tasks:
      | details               | owner         | status      |
      | Prepare the data room | deal          | todo        |
      | Chase Blue Fort KYC   | deal_investor | in_progress |
    When I go to the tasks board page for the deal
    And I select "Blue Fort Capital" from the task "deal_investor_id" filter
    Then I should see "Chase Blue Fort KYC" in the "In Progress" board column
    And I should not see "Prepare the data room" in the "Todo" board column

  # Active columns read by urgency; Done reads by recency. Undated tasks sink to
  # the bottom — plain due_date ordering puts NULLs first and floated them above
  # genuinely overdue work.
  Scenario: Cards are ordered by urgency, and Done by most recently completed
    Given there are following dated board tasks:
      | details          | status | due_date | completed_on |
      | Overdue by a lot | todo   | -500     |              |
      | Due next week    | todo   | +7       |              |
      | No due date      | todo   |          |              |
      | Finished earlier | done   |          | -8           |
      | Finished today   | done   |          | 0            |
    When I go to the tasks board page
    Then the "Todo" board column should be ordered "Overdue by a lot, Due next week, No due date"
    And the "Done" board column should be ordered "Finished today, Finished earlier"

  Scenario: The board title names what the board is scoped to
    Given the investor is in an open deal
    When I go to the tasks board page for the deal
    Then the board title should name the deal
    When I go to the tasks board page
    Then I should see "Tasks Board"

  Scenario: Board cards open their edit form on the board itself
    When I go to the tasks board page
    Then the "Draft the LPA" board card should open its edit form inline
    And the "Draft the LPA" board card menu should offer Show, Edit and Delete

  @javascript
  Scenario: Deleting from a card menu removes the card and keeps you on the board
    When I go to the tasks board page
    And I delete the "Call the auditor" card from its menu
    Then I should not see "Call the auditor" in the "Todo" board column
    And I should still be on the tasks board

  @javascript
  Scenario: Saving the inline edit updates the card without leaving the board
    When I go to the tasks board page
    And I open the "Draft the LPA" card's edit form
    And I set the task category to "Finance" and save
    Then I should see "Finance" in the "Todo" board column
    And I should still be on the tasks board

  # Show All / Incomplete carry owner_type=Deal alongside deal_id; that must not
  # narrow the deal scope down to the deal's own tasks and hide its investors'.
  Scenario: Show All inside a deal keeps the deal investors' tasks
    Given the investor is in an open deal
    And there are following deal board tasks:
      | details               | owner         | status |
      | Prepare the data room | deal          | todo   |
      | Chase Blue Fort KYC   | deal_investor | todo   |
    When I go to the deal tasks tab and click "Show All"
    Then I should see "Prepare the data room"
    And I should see "Chase Blue Fort KYC"

  # The owner-type select used to omit DealInvestor outside the deal tabs, so the
  # browser fell back to User and saving re-owned the task to the editor.
  Scenario: Editing a deal investor's task from its own page keeps its owner
    Given the investor is in an open deal
    And there are following deal board tasks:
      | details             | owner         | status |
      | Chase Blue Fort KYC | deal_investor | todo   |
    When I edit the task "Chase Blue Fort KYC" from its own page and save
    Then the task "Chase Blue Fort KYC" should still be owned by the deal investor
    And I should see "Chase Blue Fort KYC"

  Scenario: Forms inside a deal investor tab hide the owner fields they cannot change
    Given the investor is in an open deal
    When I open the new task form from the deal investor tab
    Then the task owner fields should be hidden but submitted
    When I open the new note form from the deal investor tab
    Then the note owner fields should be hidden but submitted

  @javascript
  Scenario: Filter the board by tag
    When I go to the tasks board page
    And I select "legal" from the task "q[tags_cont]" filter
    Then I should see "Draft the LPA" in the "Todo" board column
    And I should not see "Call the auditor" in the "Todo" board column

  # Due dates are picked to be unambiguously in one bucket only regardless of
  # what day "today" happens to be when this runs (e.g. overdue by 60 days is
  # always a prior calendar month too, not just "before today").
  @javascript
  Scenario: Filter the board by due date
    Given there are following board tasks due in each period
    When I go to the tasks board page
    And I select "Overdue" from the task "due_filter" filter
    Then I should see "Overdue task" in the "Todo" board column
    And I should not see "Task due this week" in the "Todo" board column
    And I should not see "Task due this month" in the "Todo" board column
    When I select "Due This Month" from the task "due_filter" filter
    Then I should see "Task due this month" in the "Todo" board column
    And I should not see "Overdue task" in the "Todo" board column
    And I should not see "Task due next month" in the "Todo" board column

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
