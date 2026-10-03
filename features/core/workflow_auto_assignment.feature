Feature: Workflow Auto-Assignment Rules
  Auto-assignment rules assign a workflow template to a matching object automatically,
  without any admin action. Rules fire on object creation and on subsequent updates.
  Once a template is assigned, further updates do not re-trigger the rule.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"

  # ── On create ─────────────────────────────────────────────────────────────────

  Scenario Outline: Catch-all rule assigns template when any object of the right type is created
    Given there is a workflow template "name=Auto Folder Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Auto Folder Template" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Auto Folder Template" type "Folder" with conditions "[]" auto_launch false priority 0
    When a new folder "name=Any New Folder" is created for the entity
    Then the folder "Any New Folder" should have workflow template "Auto Folder Template"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Condition-matched rule assigns template only when attribute matches on create
    Given there is a workflow template "name=Conditioned Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Conditioned Template" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Conditioned Template" type "Folder" with conditions '[{"attribute":"name","operator":"eq","value":"Special Folder"}]' auto_launch false priority 0
    When a new folder "name=Special Folder" is created for the entity
    Then the folder "Special Folder" should have workflow template "Conditioned Template"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Condition-matched rule does not assign when attribute does not match on create
    Given there is a workflow template "name=Conditioned Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Conditioned Template" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Conditioned Template" type "Folder" with conditions '[{"attribute":"name","operator":"eq","value":"Special Folder"}]' auto_launch false priority 0
    When a new folder "name=Ordinary Folder" is created for the entity
    Then the folder "Ordinary Folder" should not have a workflow template

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Auto-launch rule creates an active instance immediately on create
    Given there is a workflow template "name=Auto Launch Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Auto Launch Template" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Auto Launch Template" type "Folder" with conditions "[]" auto_launch true priority 0
    When a new folder "name=Auto Launch Folder" is created for the entity
    Then the folder "Auto Launch Folder" should have workflow template "Auto Launch Template"
    And the folder "Auto Launch Folder" should have an active workflow instance

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Priority ordering ─────────────────────────────────────────────────────────

  Scenario Outline: Highest-priority rule wins when multiple rules match
    Given there is a workflow template "name=High Priority Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "High Priority Template" has workflowable_type "Folder"
    And there is a workflow template "name=Low Priority Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Low Priority Template" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "High Priority Template" type "Folder" with conditions "[]" auto_launch false priority 0
    And there is an auto-assignment rule for template "Low Priority Template" type "Folder" with conditions "[]" auto_launch false priority 10
    When a new folder "name=Priority Test Folder" is created for the entity
    Then the folder "Priority Test Folder" should have workflow template "High Priority Template"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── On update ─────────────────────────────────────────────────────────────────

  Scenario Outline: Rule fires on update when object changes to match the condition
    Given there is a workflow template "name=Update Triggered Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Update Triggered Template" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Update Triggered Template" type "Folder" with conditions '[{"attribute":"name","operator":"eq","value":"Renamed Folder"}]' auto_launch false priority 0
    And a new folder "name=Draft Folder" is created for the entity
    And the folder "Draft Folder" should not have a workflow template
    When I update the folder "Draft Folder" attribute "name" to "Renamed Folder"
    Then the folder "Renamed Folder" should have workflow template "Update Triggered Template"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Idempotency ───────────────────────────────────────────────────────────────

  Scenario Outline: Rule does not fire again on a second update once template is already assigned
    Given there is a workflow template "name=Idempotent Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Idempotent Template" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Idempotent Template" type "Folder" with conditions "[]" auto_launch false priority 0
    And a new folder "name=Stable Folder" is created for the entity
    And the folder "Stable Folder" should have workflow template "Idempotent Template"
    When I update the folder "Stable Folder" attribute "name" to "Stable Folder Updated"
    Then the folder "Stable Folder Updated" should have exactly 1 workflow assignment

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Rule does not fire when object already has a manually assigned template
    Given there is a workflow template "name=Manual Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Manual Template" has workflowable_type "Folder"
    And there is a workflow template "name=Auto Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Auto Template" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Auto Template" type "Folder" with conditions "[]" auto_launch false priority 0
    And a new folder "name=Pre-assigned Folder" is created for the entity
    And I manually assign template "Manual Template" to folder "Pre-assigned Folder"
    When I update the folder "Pre-assigned Folder" attribute "name" to "Pre-assigned Folder v2"
    Then the folder "Pre-assigned Folder v2" should have workflow template "Manual Template"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Disabled templates ────────────────────────────────────────────────────────
  # A disabled template is never handed to a new record, and its rules go dormant rather than
  # blocking: the walk skips them and carries on down the chain, so a retired template cannot deny
  # a record the workflow a live rule would have given it. The rules themselves are never deleted —
  # they resume exactly as they were when the template is enabled again.

  Scenario Outline: A rule whose template is disabled assigns nothing
    Given there is a workflow template "name=Disabled Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Disabled Template" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Disabled Template" type "Folder" with conditions "[]" auto_launch true priority 0
    And the workflow template "Disabled Template" is disabled
    When a new folder "name=Unassigned Folder" is created for the entity
    Then the folder "Unassigned Folder" should not have a workflow template
    And the folder "Unassigned Folder" should not have an active workflow instance

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # E2 — the rule that matched points at a retired template, so the walk goes on to the catch-all.
  # A folder the retired rule singled out is treated like any other folder.
  Scenario Outline: A disabled template's narrow rule falls through to the live catch-all
    Given there is a workflow template "name=Disabled Specific" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Disabled Specific" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Disabled Specific" type "Folder" with conditions '[{"attribute":"name","operator":"eq","value":"Target Folder"}]' auto_launch false priority 10
    And there is a workflow template "name=Catch All Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Catch All Template" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Catch All Template" type "Folder" with conditions "[]" auto_launch false priority 100
    And the workflow template "Disabled Specific" is disabled
    When a new folder "name=Target Folder" is created for the entity
    Then the folder "Target Folder" should have workflow template "Catch All Template"
    When a new folder "name=Other Folder" is created for the entity
    Then the folder "Other Folder" should have workflow template "Catch All Template"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # H1 — the case that sent records away empty-handed: a retired catch-all ahead of a live one at the
  # same priority. The live rule is reached, and its auto_launch starts the workflow.
  Scenario Outline: A disabled template's catch-all is skipped and the next catch-all applies
    Given there is a workflow template "name=Retired Catch All" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Retired Catch All" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Retired Catch All" type "Folder" with conditions "[]" auto_launch true priority 0
    And there is a workflow template "name=Live Catch All" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Live Catch All" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Live Catch All" type "Folder" with conditions "[]" auto_launch true priority 0
    And the workflow template "Retired Catch All" is disabled
    When a new folder "name=Skipped Rule Folder" is created for the entity
    Then the folder "Skipped Rule Folder" should have workflow template "Live Catch All"
    And the folder "Skipped Rule Folder" should have an active workflow instance

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # H2 — disabling is reversible configuration: the rule was never edited or deleted, so enabling the
  # template puts it back at the front of the chain.
  Scenario Outline: Enabling a template again restores its rule's precedence
    Given there is a workflow template "name=Retired Catch All" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Retired Catch All" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Retired Catch All" type "Folder" with conditions "[]" auto_launch false priority 0
    And there is a workflow template "name=Live Catch All" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Live Catch All" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Live Catch All" type "Folder" with conditions "[]" auto_launch false priority 0
    And the workflow template "Retired Catch All" is disabled
    And a new folder "name=While Disabled Folder" is created for the entity
    And the folder "While Disabled Folder" should have workflow template "Live Catch All"
    When the workflow template "Retired Catch All" is enabled
    And a new folder "name=After Enabling Folder" is created for the entity
    Then the folder "After Enabling Folder" should have workflow template "Retired Catch All"
    And the template "Retired Catch All" should still have 1 auto-assignment rule

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # E3 — the rule that actually wins decides whether a workflow starts, not the retired one it
  # stepped past: the skipped rule had auto_launch true, the winner has it false.
  Scenario Outline: The successor rule's own auto_launch governs
    Given there is a workflow template "name=Retired Launcher" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Retired Launcher" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Retired Launcher" type "Folder" with conditions "[]" auto_launch true priority 0
    And there is a workflow template "name=Quiet Successor" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Quiet Successor" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Quiet Successor" type "Folder" with conditions "[]" auto_launch false priority 10
    And the workflow template "Retired Launcher" is disabled
    When a new folder "name=No Launch Folder" is created for the entity
    Then the folder "No Launch Folder" should have workflow template "Quiet Successor"
    And the folder "No Launch Folder" should not have an active workflow instance

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # E4 — two live rules at the same priority: order(:priority, :id) makes the earlier-created rule
  # win every time, rather than leaving it to whatever the database happens to return.
  Scenario Outline: Equal priorities resolve by creation order, repeatably
    Given there is a workflow template "name=First Created" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "First Created" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "First Created" type "Folder" with conditions "[]" auto_launch false priority 0
    And there is a workflow template "name=Second Created" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Second Created" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Second Created" type "Folder" with conditions "[]" auto_launch false priority 0
    When a new folder "name=Tie Folder One" is created for the entity
    And a new folder "name=Tie Folder Two" is created for the entity
    And a new folder "name=Tie Folder Three" is created for the entity
    Then the folder "Tie Folder One" should have workflow template "First Created"
    And the folder "Tie Folder Two" should have workflow template "First Created"
    And the folder "Tie Folder Three" should have workflow template "First Created"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # E5 — a record created while nothing could be assigned is not stranded: the after_update hook
  # re-walks the chain on its next save. Nothing is back-filled until then.
  Scenario Outline: A record created while every template was disabled picks one up on its next save
    Given there is a workflow template "name=Later Enabled" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Later Enabled" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Later Enabled" type "Folder" with conditions "[]" auto_launch false priority 0
    And the workflow template "Later Enabled" is disabled
    And a new folder "name=Stranded Folder" is created for the entity
    And the folder "Stranded Folder" should not have a workflow template
    When the workflow template "Later Enabled" is enabled
    And I update the folder "Stranded Folder" attribute "name" to "Rescued Folder"
    Then the folder "Rescued Folder" should have workflow template "Later Enabled"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # X1 — a rule whose template row has gone (deleted straight in the database) must not take the
  # record down with it: it is skipped like any dormant rule and the walk continues.
  Scenario Outline: A rule pointing at a missing template is skipped without raising
    Given there is a workflow template "name=Vanished Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Vanished Template" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Vanished Template" type "Folder" with conditions "[]" auto_launch false priority 0
    And there is a workflow template "name=Surviving Catch All" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Surviving Catch All" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Surviving Catch All" type "Folder" with conditions "[]" auto_launch false priority 10
    And the auto-assignment rule for template "Vanished Template" points at a missing template
    When a new folder "name=Orphan Rule Folder" is created for the entity
    Then the folder "Orphan Rule Folder" should have workflow template "Surviving Catch All"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # X2 — the successor can itself fail to be assigned (here its template was retyped behind the
  # rule's back). Auto-assignment is best-effort: it logs and gives up, and the record still saves.
  Scenario Outline: A successor that cannot be assigned fails quietly and the record still saves
    Given there is a workflow template "name=Retired Blocker" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Retired Blocker" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Retired Blocker" type "Folder" with conditions "[]" auto_launch false priority 0
    And there is a workflow template "name=Mistyped Successor" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Mistyped Successor" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Mistyped Successor" type "Folder" with conditions "[]" auto_launch false priority 10
    And the workflow template "Retired Blocker" is disabled
    And the workflow template "Mistyped Successor" has workflowable_type "CapitalCall"
    When a new folder "name=Failed Assignment Folder" is created for the entity
    Then the folder "Failed Assignment Folder" should not have a workflow template
    And the folder "Failed Assignment Folder" should not have an active workflow instance

    Examples:
      | user | entity              |
      |      | entity_type=Company |

    Examples:
      | user | entity              |
      |      | entity_type=Company |
