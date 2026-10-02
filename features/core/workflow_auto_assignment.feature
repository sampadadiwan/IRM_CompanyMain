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
  # A disabled template is never handed to a new record. The check runs after the rule has been
  # matched, deliberately: the rule that matched is the rule that applies, so its template being
  # disabled means "no template", not "whatever the next rule says".

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

  Scenario Outline: A disabled template's rule does not fall through to the next rule
    Given there is a workflow template "name=Disabled Specific" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Disabled Specific" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Disabled Specific" type "Folder" with conditions '[{"attribute":"name","operator":"eq","value":"Target Folder"}]' auto_launch false priority 10
    And there is a workflow template "name=Catch All Template" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the workflow template "Catch All Template" has workflowable_type "Folder"
    And there is an auto-assignment rule for template "Catch All Template" type "Folder" with conditions "[]" auto_launch false priority 100
    And the workflow template "Disabled Specific" is disabled
    When a new folder "name=Target Folder" is created for the entity
    Then the folder "Target Folder" should not have a workflow template
    When a new folder "name=Other Folder" is created for the entity
    Then the folder "Other Folder" should have workflow template "Catch All Template"

    Examples:
      | user | entity              |
      |      | entity_type=Company |
