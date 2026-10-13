Feature: Workflow Instance Lifecycle
  Admins can launch a workflow instance for any workflowable object (e.g. a folder)
  and advance it through steps via a polymorphic WorkflowAssignment. The same lifecycle
  applies to Folder, InvestorKyc, CapitalCommitment, and Approval objects. Actors respond
  via the in-app UI.

  # ── Launch (Folder) ────────────────────────────────────────────────────────────

  @rack_test
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

  @rack_test
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

  # ── Launch on InvestorKyc ───────────────────────────────────────────────────

  @rack_test
  Scenario Outline: Admin launches a workflow for an investor KYC
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=KYC Review" with 1 step "name=Initial Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the entity has an investor_kyc "name=Test KYC"
    And the investor_kyc "Test KYC" has workflow template "KYC Review"
    When I launch the workflow for investor_kyc "Test KYC"
    Then the investor_kyc "Test KYC" should have an active workflow instance
    And the active instance should be at step 1

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Launch on CapitalCommitment ─────────────────────────────────────────────

  @rack_test
  Scenario Outline: Admin launches a workflow for a capital commitment
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Commitment Review" with 1 step "name=Initial Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the entity has a capital_commitment "name=Test Commitment"
    And the capital_commitment "Test Commitment" has workflow template "Commitment Review"
    When I launch the workflow for capital_commitment "Test Commitment"
    Then the capital_commitment "Test Commitment" should have an active workflow instance
    And the active instance should be at step 1

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Launch on Approval ──────────────────────────────────────────────────────

  @rack_test
  Scenario Outline: Admin launches a workflow for an approval
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Approval Review" with 1 step "name=Initial Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the entity has an approval "name=Test Approval"
    And the approval "Test Approval" has workflow template "Approval Review"
    When I launch the workflow for approval "Test Approval"
    Then the approval "Test Approval" should have an active workflow instance
    And the active instance should be at step 1

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

  @rack_test
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

  @rack_test
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

  @rack_test
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

  @rack_test
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

  @rack_test
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

  # ── Phase 4: Breadcrumb workflow link ─────────────────────────────────────────

  # When an active workflow instance exists the breadcrumb bar shows a kanban icon
  # linking to /workflow_instances/:id. When no instance is active, the icon is absent.

  @rack_test
  Scenario Outline: Breadcrumb shows workflow link when active instance exists
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Breadcrumb Test" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the entity has a folder "name=Nav Folder"
    And the folder "Nav Folder" has workflow template "Breadcrumb Test"
    And the folder "Nav Folder" has an active workflow instance for "Breadcrumb Test"
    When I visit the folder show page for "Nav Folder"
    Then I should see the workflow link in the breadcrumb

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Breadcrumb does not show workflow link when no active instance exists
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And the entity has a folder "name=Plain Folder"
    When I visit the folder show page for "Plain Folder"
    Then I should not see the workflow link in the breadcrumb

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Polymorphic: any workflowable type can have template blocked from removal ──

  @rack_test
  Scenario Outline: Cannot remove template from investor_kyc while workflow is active
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=KYC Lock" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the entity has an investor_kyc "name=Locked KYC"
    And the investor_kyc "Locked KYC" has workflow template "KYC Lock"
    And the investor_kyc "Locked KYC" has an active workflow instance for "KYC Lock"
    When I try to remove the workflow template from investor_kyc "Locked KYC"
    Then the investor_kyc "Locked KYC" should still have workflow template "KYC Lock"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Phase 5: Template type scoping ────────────────────────────────────────────

  # A template scoped to Folder cannot be assigned to an InvestorKyc, and vice versa.
  # Auto-assignment rules trigger on new object creation when matching rules exist.

  Scenario Outline: Cannot assign a Folder-scoped template to an InvestorKyc
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Folder Only Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Folder Only Template" has workflowable_type "Folder"
    And the entity has an investor_kyc "name=Type Test KYC"
    When I try to assign template "Folder Only Template" to investor_kyc "Type Test KYC"
    Then the investor_kyc "Type Test KYC" should not have a workflow template

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  @rack_test
  Scenario Outline: A matching auto-assignment rule assigns the template to a new folder
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Auto Folder Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Auto Folder Template" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Auto Folder Template" type "Folder" with conditions "[]" auto_launch false priority 0
    When a new folder "name=Auto Assigned Folder" is created for the entity
    Then the folder "Auto Assigned Folder" should have workflow template "Auto Folder Template"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Auto-assignment rule with a condition only matches when attribute matches
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Conditioned Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Conditioned Template" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Conditioned Template" type "Folder" with conditions '[{"attribute":"name","operator":"eq","value":"Special Folder"}]' auto_launch false priority 0
    When a new folder "name=Ordinary Folder" is created for the entity
    Then the folder "Ordinary Folder" should not have a workflow template

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  @rack_test
  Scenario Outline: Auto-assignment rule with auto_launch launches a workflow instance immediately
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=Auto Launch Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Auto Launch Template" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Auto Launch Template" type "Folder" with conditions "[]" auto_launch true priority 0
    When a new folder "name=Auto Launch Folder" is created for the entity
    Then the folder "Auto Launch Folder" should have an active workflow instance

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Full-stack UI launch ──────────────────────────────────────────────────────
  # Every other launch scenario in this file calls WorkflowInstanceService directly,
  # which skips WorkflowInstancesController#create entirely — including the Pundit
  # `authorize @instance` call. This scenario drives the real "Launch Workflow"
  # modal in a browser so the controller + policy path actually gets exercised.

  Scenario Outline: Admin launches a workflow from the folder's Launch Workflow modal
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=LP Review" with 1 step "name=Initial Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the entity has a folder "name=LP Documents"
    And the folder "LP Documents" has workflow template "LP Review"
    When I visit the folder show page for "LP Documents"
    And I open the Workflow tab
    And I launch the workflow "LP Review" from the launch modal
    Then I should see a flash notice containing "Workflow launched"
    And the folder "LP Documents" should have an active workflow instance

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Full-stack UI navigation from the index list ──────────────────────────────
  # Every other show-page assertion in this file loads instance data at the model
  # level. This scenario clicks "View" from /workflow_instances the way a real user
  # would, so a Turbo Frame regression (nested link never breaking out of the index's
  # own turbo_frame_tag) actually gets caught instead of silently passing.

  @rack_test
  Scenario Outline: Viewing an instance from the workflow instances index opens the full page
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is a workflow template "name=LP Review" with 1 step "name=Initial Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the entity has a folder "name=LP Documents"
    And the folder "LP Documents" has workflow template "LP Review"
    And the folder "LP Documents" has an active workflow instance for "LP Review"
    When I visit the workflow instances index page
    And I click "View" for the instance on folder "LP Documents"
    Then I should land on the workflow instance show page for "LP Documents"
    And I should not see "Content missing"

    Examples:
      | user | entity              |
      |      | entity_type=Company |
