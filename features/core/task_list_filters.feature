Feature: Tasks List Filters
  As a user
  I want the tasks list to offer the same filters as the kanban board
  So I can narrow a long list without switching to the board and back

  # The list used to offer category and due date only, while the board had six
  # selects (assignee, stakeholder, contact, tag, category, due date) — even
  # though TaskList applies every one of them whichever view is rendering. Both
  # now render tasks/_filter_bar.

  Background:
    Given Im logged in as a user "first_name=John;email=admin@example.com" for an entity "name=Acme Fund;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing investor "investor_name=Blue Fort Capital"
    And there is a contact "maya@bluefort.com" named "Maya Kapoor" for the investor
    And there are following board tasks for the entity:
      | details          | status | stakeholder | contact           | assigned_to       | tags  |
      | Draft the LPA    | todo   |             |                   |                   | legal |
      | Call the auditor | todo   |             |                   | admin@example.com |       |
      | Chase signatures | todo   | yes         | maya@bluefort.com |                   |       |
      | Send the deck    | todo   | yes         |                   |                   |       |

  @javascript
  Scenario: Filter the tasks list by assignee
    When I go to the tasks page
    And I select "John" from the task "assigned_to_id" filter
    Then I should see "Call the auditor"
    And I should not see "Draft the LPA"

  @javascript
  Scenario: Filter the tasks list by stakeholder and contact
    When I go to the tasks page
    And I pick "Blue Fort Capital" in the stakeholder filter
    Then I should see "Chase signatures"
    And I should not see "Draft the LPA"
    When I select "Maya Kapoor (maya@bluefort.com)" from the task "touch_point_id" filter
    Then I should see "Chase signatures"
    And I should not see "Send the deck"

  @javascript
  Scenario: Filter the tasks list by tag
    When I go to the tasks page
    And I select "legal" from the task "q[tags_cont]" filter
    Then I should see "Draft the LPA"
    And I should not see "Call the auditor"

  # The list's category select offered the static Task::CATEGORIES list, so a
  # free-text category a task actually carried (the "Other" fallback) could not
  # be filtered on at all. Both views now offer the categories in use.
  @javascript
  Scenario: The category filter offers a category that only exists as free text
    Given there are following tasks for the entity:
      | details             | category  |
      | Renew the ISO audit | ISO 27001 |
    When I go to the tasks page
    Then the tasks list should offer the category "ISO 27001"
    When I select "ISO 27001" from the task "q[category_eq]" filter
    Then I should see "Renew the ISO audit"
    And I should not see "Draft the LPA"

  # A record's own tasks tab has its stakeholder fixed by that scope, and
  # TaskList ignores investor_id once owner_id is set — the select would be a
  # dead control there. Its contacts are still worth filtering by.
  Scenario: A stakeholder's own tasks tab offers contacts but no stakeholder select
    When I go to the tasks page for the investor
    Then the tasks list should not offer a stakeholder filter
    And the tasks list should offer a contact filter

  # The tabs load the list into a turbo frame the host page names, and every one
  # of those frames is declared target="_top" — so a form inside one reloads the
  # whole page unless it names its frame back. Filtering a tab has to refresh
  # the tab, not the page around it.
  @javascript
  Scenario: Filtering inside a stakeholder's Tasks tab refreshes only the tab
    Given there are following board tasks for the entity:
      | details        | status | stakeholder | assigned_to       |
      | Review the SPA | todo   | yes         | admin@example.com |
    When I open the investor's Tasks tab
    Then I should see "Chase signatures"
    When I remember the current page load
    And I select "John" from the task "assigned_to_id" filter in the tab
    Then I should see "Review the SPA"
    And I should not see "Chase signatures"
    And the page should not have reloaded
