Feature: Workflow Instance Lifecycle
  Admins can launch a folder-level workflow instance and advance it through steps.
  Actors respond via the in-app UI. Non-admins cannot launch or override workflows.

  # ── Launch ───────────────────────────────────────────────────────────────────

  Scenario Outline: Admin launches a workflow for a folder
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=LP Review" with 1 step "name=Initial Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the entity has a folder "name=LP Documents"
    And the folder "LP Documents" has workflow template "LP Review"
    When I launch the workflow for folder "LP Documents"
    Then the folder "LP Documents" should have an active workflow instance
    And the active instance should be at step 1

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Cannot launch a second workflow while one is active
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=LP Review" with 1 step "name=Initial Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the entity has a folder "name=LP Documents"
    And the folder "LP Documents" has workflow template "LP Review"
    And the folder "LP Documents" has an active workflow instance for "LP Review"
    When I try to launch another workflow for folder "LP Documents"
    Then I should see a workflow launch error

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Actor response & any_one quorum ──────────────────────────────────────────

  Scenario Outline: Actor responds and any_one quorum resolves the step
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Two-Stage Review" with 2 steps:
      | name            | states             | quorum_rule | on_reject_rule | actors |
      | Initial Review  | Approved,Rejected  | any_one     | stop           | admin  |
      | Final Sign-off  | Approved,Rejected  | any_one     | stop           | admin  |
    And the entity has a folder "name=LP Docs"
    And the folder "LP Docs" has workflow template "Two-Stage Review"
    And the folder "LP Docs" has an active workflow instance for "Two-Stage Review"
    When the actor submits "Approved" on the current step of the active instance for "LP Docs"
    Then the active instance for "LP Docs" should be at step 2

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Final step completion ─────────────────────────────────────────────────────

  Scenario Outline: Final step approved completes the workflow
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Single Step Review" with 1 step "name=Approval;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the entity has a folder "name=Docs"
    And the folder "Docs" has workflow template "Single Step Review"
    And the folder "Docs" has an active workflow instance for "Single Step Review"
    When the actor submits "Approved" on the current step of the active instance for "Docs"
    Then the active instance for "Docs" should have status "complete"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Rejection rules ───────────────────────────────────────────────────────────

  Scenario Outline: on_reject_rule stop halts the workflow
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Stop Review" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the entity has a folder "name=Halt Folder"
    And the folder "Halt Folder" has workflow template "Stop Review"
    And the folder "Halt Folder" has an active workflow instance for "Stop Review"
    When the actor submits "Rejected" on the current step of the active instance for "Halt Folder"
    Then the active instance for "Halt Folder" should have status "rejected"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: on_reject_rule restart resets the instance to step 1
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Restart Review" with 2 steps:
      | name    | states             | quorum_rule | on_reject_rule | actors |
      | Step 1  | Approved,Rejected  | any_one     | stop           | admin  |
      | Step 2  | Approved,Rejected  | any_one     | restart        | admin  |
    And the entity has a folder "name=Restart Folder"
    And the folder "Restart Folder" has workflow template "Restart Review"
    And the folder "Restart Folder" has an active workflow instance for "Restart Review" at step 2
    When the actor submits "Rejected" on the current step of the active instance for "Restart Folder"
    Then the active instance for "Restart Folder" should be at step 1
    And all previous actor responses for the instance should be archived

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: on_reject_rule previous_step reverts to the prior step
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Revert Review" with 2 steps:
      | name    | states             | quorum_rule | on_reject_rule  | actors |
      | Step 1  | Approved,Rejected  | any_one     | stop            | admin  |
      | Step 2  | Approved,Rejected  | any_one     | previous_step   | admin  |
    And the entity has a folder "name=Revert Folder"
    And the folder "Revert Folder" has workflow template "Revert Review"
    And the folder "Revert Folder" has an active workflow instance for "Revert Review" at step 2
    When the actor submits "Rejected" on the current step of the active instance for "Revert Folder"
    Then the active instance for "Revert Folder" should be at step 1

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── all quorum + tiebreaker ───────────────────────────────────────────────────

  Scenario Outline: all quorum with conflicting responses enters tiebreaker mode
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a second actor "actor2" in the entity
    And there is a workflow template "name=All Quorum" with 1 step "name=Review;states=Approved,Rejected;quorum_rule=all;on_reject_rule=stop;actors=admin,actor2"
    And the entity has a folder "name=All Quorum Folder"
    And the folder "All Quorum Folder" has workflow template "All Quorum"
    And the folder "All Quorum Folder" has an active workflow instance for "All Quorum"
    When the actor "admin" submits "Approved" on the current step
    And the actor "actor2" submits "Rejected" on the current step
    Then the instance resolution for "All Quorum Folder" should be "tiebreaker"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Admin archive ─────────────────────────────────────────────────────────────

  Scenario Outline: Admin archives an active instance to allow template removal
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Archivable Review" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the entity has a folder "name=Archive Folder"
    And the folder "Archive Folder" has workflow template "Archivable Review"
    And the folder "Archive Folder" has an active workflow instance for "Archivable Review"
    When I archive the active workflow for folder "Archive Folder"
    Then the active instance for "Archive Folder" should have status "archived"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Cannot remove template while instance active ───────────────────────────────

  Scenario Outline: Cannot remove template while workflow is in progress
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Locked Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the entity has a folder "name=Locked Folder"
    And the folder "Locked Folder" has workflow template "Locked Template"
    And the folder "Locked Folder" has an active workflow instance for "Locked Template"
    When I try to remove the workflow template from folder "Locked Folder"
    Then the folder "Locked Folder" should still have workflow template "Locked Template"

    Examples:
      | user | entity              |
      |      | entity_type=Company |
