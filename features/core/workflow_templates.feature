Feature: Workflow Templates
  Admins can define reusable workflow templates with ordered steps and assign them to any object
  (folders, documents, deals, etc.) via a WorkflowAssignment. Non-admins cannot mutate templates.

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

  Scenario Outline: Admin configures which buttons a template locks
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Lockable Template"
    When I visit the edit page for the workflow template "Lockable Template"
    And I fill in the Locked buttons field with "Approve, Edit"
    And I save the workflow template edit form
    Then the workflow template "Lockable Template" should have gated_button_labels "Approve, Edit"
    And the workflow template show page should list "Approve, Edit" as locked buttons

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

  # ── Enable / disable ──────────────────────────────────────────────────────────
  # Disabling retires a template without deleting it (a template with assignments or history cannot
  # be deleted at all): nothing new is assigned to it or launched on it, while workflows already
  # running carry on from the snapshot taken at their launch.

  Scenario Outline: Admin disables a template from its page
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Retired Review"
    When I visit the workflow template page for "Retired Review"
    And I press "Disable" on the workflow template page
    Then the workflow template "Retired Review" should be disabled
    And the workflow template page should warn that the template is disabled

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Admin enables a disabled template again
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Retired Review"
    And the workflow template "Retired Review" is disabled
    When I visit the workflow template page for "Retired Review"
    And I press "Enable" on the workflow template page
    Then the workflow template "Retired Review" should be enabled

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # E6 — the one consequence of disabling that cannot be seen from this page: which template the
  # records this one's rules matched will be given instead.
  Scenario Outline: The disable confirmation names the template that takes over
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Retired Review" with 1 step "name=Sign-off;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Retired Review" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Retired Review" type "Folder" with conditions "[]" auto_launch false priority 0
    And there is a workflow template "name=Successor Review" with 1 step "name=Sign-off;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Successor Review" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Successor Review" type "Folder" with conditions "[]" auto_launch false priority 10
    When I visit the workflow template page for "Retired Review"
    Then the disable confirmation should say that records will fall through to "Successor Review"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # E7 — the rules table of a disabled template: dormant and reversible, not dead.
  Scenario Outline: A disabled template says its rules are dormant
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Retired Review" with 1 step "name=Sign-off;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Retired Review" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Retired Review" type "Folder" with conditions "[]" auto_launch false priority 0
    And the workflow template "Retired Review" is disabled
    When I visit the workflow template page for "Retired Review"
    Then the rules note should say the rules are dormant
    And the rule status should be "Dormant"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # E8 — a rule that can never win because an identical catch-all is ahead of it. The blocker is
  # named and linked, because it lives on another template's page.
  Scenario Outline: A shadowed rule is badged with the rule that blocks it
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=First Catch All" with 1 step "name=Sign-off;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "First Catch All" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "First Catch All" type "Folder" with conditions "[]" auto_launch false priority 0
    And there is a workflow template "name=Blocked Template" with 1 step "name=Sign-off;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Blocked Template" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Blocked Template" type "Folder" with conditions "[]" auto_launch false priority 0
    When I visit the workflow template page for "Blocked Template"
    Then the rule status should be "Shadowed"
    And the shadowed rule should name "First Catch All" as the blocker
    When I visit the workflow template page for "First Catch All"
    Then the rule status should be "Active"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # E9 — every rule for a type dormant: no screen would otherwise say that new records of that type
  # are getting nothing.
  Scenario Outline: The template list warns when every rule for a type is dormant
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Only Template" with 1 step "name=Sign-off;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Only Template" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Only Template" type "Folder" with conditions "[]" auto_launch false priority 0
    And the workflow template "Only Template" is disabled
    When I visit the workflow templates page
    Then the page should warn that new folders get no workflow
    When the workflow template "Only Template" is enabled
    And I visit the workflow templates page
    Then the page should not warn that new folders get no workflow

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: A disabled template is not offered when launching a workflow
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Live Review" with 1 step "name=Sign-off;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Live Review" has workflowable_type "Folder"
    And there is a workflow template "name=Retired Review" with 1 step "name=Sign-off;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Retired Review" has workflowable_type "Folder"
    And the workflow template "Retired Review" is disabled
    And the entity has a folder "name=Picker Folder"
    When I visit the folder show page for "Picker Folder"
    Then the launch template picker should offer "Live Review"
    And the launch template picker should not offer "Retired Review"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: A workflow cannot be launched on a disabled template
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Retired Review" with 1 step "name=Sign-off;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the entity has a folder "name=Launch Folder"
    And the folder "Launch Folder" has workflow template "Retired Review"
    And the workflow template "Retired Review" is disabled
    When I launch the workflow for folder "Launch Folder"
    Then I should see a workflow launch error
    And the folder "Launch Folder" should not have an active workflow instance

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

  # ── Add / Remove step rows on the edit page (Stimulus nested-form controller) ──
  # These drive the actual browser JS rather than creating steps directly via the
  # model, since a model-level test would not catch the Stimulus controller being
  # missing (the regression this covers).

  @javascript
  Scenario Outline: Add Step inserts a new blank step row without a page reload
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Add Step Template" with 1 step "name=Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    When I visit the edit page for the workflow template "Add Step Template"
    And I click "Add Step" on the workflow template edit page
    Then a new step row should appear on the page

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  @javascript
  Scenario Outline: Removing an existing step marks it for destruction instead of deleting it outright
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Remove Step Template" with 2 steps:
      | name      | states            | quorum_rule | on_reject_rule | actors |
      | Step One  | Approved,Rejected | any_one     | stop           | admin  |
      | Step Two  | Approved,Rejected | any_one     | stop           | admin  |
    When I visit the edit page for the workflow template "Remove Step Template"
    And I remove the last step row via its remove button
    Then the last step row should be hidden and marked for destruction
    When I save the workflow template edit form
    Then the template should have 1 step

    Examples:
      | user | entity              |
      |      | entity_type=Company |
