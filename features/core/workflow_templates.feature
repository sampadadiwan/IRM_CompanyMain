Feature: Workflow Templates
  Admins can define reusable workflow templates with ordered steps and assign them to folders.
  Non-admins cannot mutate templates.

  # ── Template CRUD ────────────────────────────────────────────────────────────

  Scenario Outline: Admin creates a workflow template with two steps
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    When I create a workflow template "name=Two-Stage Review;reminder_interval_days=3"
    And I add a step "name=Legal Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop" to the template
    And I add a step "name=CFO Sign-off;states=Approved,Rejected;quorum_rule=all;on_reject_rule=previous_step" to the template
    Then the workflow template "Two-Stage Review" should exist
    And the template should have 2 steps
    And step 1 should be named "Legal Review"
    And step 2 should be named "CFO Sign-off"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Admin edits a workflow template name
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Old Name"
    When I update the workflow template name to "New Name"
    Then the workflow template "New Name" should exist
    And the workflow template "Old Name" should not exist

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Admin deletes a template that is not in use
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Deletable Template"
    When I delete the workflow template "Deletable Template"
    Then the workflow template "Deletable Template" should not exist

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Access control ────────────────────────────────────────────────────────────

  Scenario Outline: Non-admin cannot create a workflow template
    Given Im logged in as a user "<user>" for an entity "<entity>"
    When I try to create a workflow template "name=Blocked Template"
    Then I should be denied access

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Folder assignment ────────────────────────────────────────────────────────

  Scenario Outline: Admin assigns a workflow template to a folder
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=LP Review"
    And the entity has a folder "name=LP Documents"
    When I assign the workflow template "LP Review" to the folder "LP Documents"
    Then the folder "LP Documents" should have workflow template "LP Review"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Admin removes a workflow template from a folder
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=LP Review"
    And the entity has a folder "name=LP Documents"
    And the folder "LP Documents" has workflow template "LP Review"
    When I remove the workflow template from the folder "LP Documents"
    Then the folder "LP Documents" should have no workflow template

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Actor assignment ──────────────────────────────────────────────────────────

  Scenario Outline: Admin assigns actors to a step
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And the entity has employees
    And there is a workflow template "name=LP Review"
    When I add a step "name=Review;actors=Alice,Bob;quorum_rule=all" to the template
    Then step 1 should have actor "Alice"
    And step 1 should have actor "Bob"
    And step 1 should have 2 actors

    Examples:
      | user | entity              |
      |      | entity_type=Company |
