Feature: Workflow Instance Reset
  An admin can reset an active workflow instance back to step 1.
  The reset:
    - moves current_step_position back to 1
    - archives all active actor responses from the old run
    - creates a "reset" audit entry in the state-change trail
    - re-notifies the step-1 actors so they know to vote again
    - is blocked for instances that are not active (archived, complete, rejected)

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"

  # ── Back to step 1 ─────────────────────────────────────────────────────────────

  Scenario Outline: Reset moves a mid-workflow instance back to step 1
    Given there is a workflow template "name=Two-Stage Reset" with 2 steps:
      | name      | states             | quorum_rule | on_reject_rule | actors |
      | Step One  | Approved,Rejected  | any_one     | stop           | admin  |
      | Step Two  | Approved,Rejected  | any_one     | stop           | admin  |
    And the entity has a folder "name=Reset Me"
    And the folder "Reset Me" has workflow template "Two-Stage Reset"
    And the folder "Reset Me" has an active workflow instance for "Two-Stage Reset" at step 2
    When I reset the active workflow for folder "Reset Me"
    Then the active instance should be at step 1

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Responses are archived ─────────────────────────────────────────────────────

  Scenario Outline: Reset archives all active actor responses from the previous run
    Given there is a workflow template "name=Two-Stage Response" with 2 steps:
      | name      | states             | quorum_rule | on_reject_rule | actors |
      | Review    | Approved,Rejected  | any_one     | stop           | admin  |
      | Sign-off  | Approved,Rejected  | any_one     | stop           | admin  |
    And the entity has a folder "name=Response Folder"
    And the folder "Response Folder" has workflow template "Two-Stage Response"
    And the folder "Response Folder" has an active workflow instance for "Two-Stage Response"
    And the actor submits "Approved" on the current step of the folder "Response Folder"
    When I reset the active workflow for folder "Response Folder"
    Then all previous actor responses for the instance should be archived

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Audit entry ─────────────────────────────────────────────────────────────────

  Scenario Outline: Reset records a "reset" state-change audit entry
    Given there is a workflow template "name=Single Audit" with 1 step "name=Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the entity has a folder "name=Audit Folder"
    And the folder "Audit Folder" has workflow template "Single Audit"
    And the folder "Audit Folder" has an active workflow instance for "Single Audit"
    When I reset the active workflow for folder "Audit Folder"
    Then the active instance should have a reset audit entry

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Re-notification after reset ────────────────────────────────────────────────

  Scenario Outline: Reset re-notifies step-1 actors so they know to vote again
    Given there is a workflow template "name=Notify Reset" with 2 steps:
      | name      | states             | quorum_rule | on_reject_rule | actors |
      | Review    | Approved,Rejected  | any_one     | stop           | admin  |
      | Sign-off  | Approved,Rejected  | any_one     | stop           | admin  |
    And the entity has a folder "name=Notify Folder"
    And the folder "Notify Folder" has workflow template "Notify Reset"
    And the folder "Notify Folder" has an active workflow instance for "Notify Reset" at step 2
    When I reset the active workflow for folder "Notify Folder"
    Then the step-1 actors should have received a re-notification email

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Status is preserved as active ─────────────────────────────────────────────

  Scenario Outline: Instance stays active after reset (not completed or rejected)
    Given there is a workflow template "name=Stay Active" with 2 steps:
      | name      | states             | quorum_rule | on_reject_rule | actors |
      | Step One  | Approved,Rejected  | any_one     | stop           | admin  |
      | Step Two  | Approved,Rejected  | any_one     | stop           | admin  |
    And the entity has a folder "name=Active Folder"
    And the folder "Active Folder" has workflow template "Stay Active"
    And the folder "Active Folder" has an active workflow instance for "Stay Active" at step 2
    When I reset the active workflow for folder "Active Folder"
    Then the active instance for "Active Folder" should have status "active"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Cannot reset a non-active instance ────────────────────────────────────────

  Scenario Outline: Cannot reset an archived workflow instance
    Given there is a workflow template "name=Blocked Reset" with 1 step "name=Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the entity has a folder "name=Archived Folder"
    And the folder "Archived Folder" has workflow template "Blocked Reset"
    And the folder "Archived Folder" has an active workflow instance for "Blocked Reset"
    When I archive the active workflow for folder "Archived Folder"
    And I try to reset the active workflow for folder "Archived Folder"
    Then I should see a workflow reset error

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Full reset cycle: advance, reset, re-advance ──────────────────────────────

  Scenario Outline: After reset, actors can re-vote and advance the workflow again
    Given there is a workflow template "name=Full Cycle" with 2 steps:
      | name      | states             | quorum_rule | on_reject_rule | actors |
      | Step One  | Approved,Rejected  | any_one     | stop           | admin  |
      | Step Two  | Approved,Rejected  | any_one     | stop           | admin  |
    And the entity has a folder "name=Cycle Folder"
    And the folder "Cycle Folder" has workflow template "Full Cycle"
    And the folder "Cycle Folder" has an active workflow instance for "Full Cycle"
    And the actor submits "Approved" on the current step of the folder "Cycle Folder"
    When I reset the active workflow for folder "Cycle Folder"
    Then the active instance should be at step 1
    And all previous actor responses for the instance should be archived
    When the actor submits "Approved" on the current step of the folder "Cycle Folder"
    Then the active instance for "Cycle Folder" should be at step 2

    Examples:
      | user | entity              |
      |      | entity_type=Company |
