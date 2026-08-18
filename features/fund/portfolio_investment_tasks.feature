Feature: Portfolio Investment Tasks
  As a fund manager
  I want to track tasks against a portfolio investment
  So that follow-up work on an investment lives on the investment itself

  # Mirrors how tasks hang off an Investor and a Capital Commitment: Task#owner
  # is polymorphic, the investment page gets a Tasks tab, and the same tab links
  # through to the kanban board scoped to that investment.
  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And there is a fund "name=Test fund" for the entity
    And there are "1" portfolio investments "quantity=200"
    And I have a portfolio investment

  Scenario: The portfolio investment page offers a Tasks tab
    When I go to the portfolio investment page
    Then the portfolio investment page should offer a Tasks tab

  Scenario: The tasks tab lists only this investment's tasks
    Given the portfolio investment has the following tasks:
      | details                     | status |
      | Collect the audited accounts | todo   |
      | Chase the board pack         | todo   |
    And there is an unrelated task "Reconcile the bank statement"
    When I open the portfolio investment tasks tab
    Then I should see "Collect the audited accounts"
    And I should see "Chase the board pack"
    And I should not see "Reconcile the bank statement"

  # The owner-type select offers only User/Investor, so without the hidden-field
  # path a new task from this tab would fall back to User and detach itself from
  # the investment the moment it was saved.
  Scenario: Creating a task from the tab attaches it to the investment
    When I open the portfolio investment tasks tab
    And I open the new task form from the portfolio investment tasks tab
    Then the task owner fields should be hidden but carry the portfolio investment
    When I save the task with details "Collect the audited accounts"
    Then the task "Collect the audited accounts" should be owned by the portfolio investment

  # Same regression as deal investor tasks: opening the task on its own page must
  # not re-own it to whoever edited it.
  Scenario: Editing the task from its own page keeps the investment as its owner
    Given the portfolio investment has the following tasks:
      | details                      | status |
      | Collect the audited accounts | todo   |
    When I edit the task "Collect the audited accounts" from its own page and save
    Then the task "Collect the audited accounts" should be owned by the portfolio investment

  Scenario: The tasks tab links to a board scoped to the investment
    Given the portfolio investment has the following tasks:
      | details                      | status      |
      | Collect the audited accounts | todo        |
      | Chase the board pack         | in_progress |
    When I open the portfolio investment tasks tab
    Then the tasks tab should offer a board link for the portfolio investment
    When I go to the tasks board page for the portfolio investment
    Then the board title should name the portfolio investment
    And I should see "Collect the audited accounts" in the "Todo" board column
    And I should see "Chase the board pack" in the "In Progress" board column

  Scenario: Deleting the investment removes its tasks
    Given the portfolio investment has the following tasks:
      | details                      | status |
      | Collect the audited accounts | todo   |
    When the portfolio investment is destroyed
    Then no tasks should remain for the portfolio investment
