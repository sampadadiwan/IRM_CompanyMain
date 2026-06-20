Feature: Workflow Auto-Reminders and Audit Trail Export
  The system sends daily reminder emails to pending actors after the configured
  reminder_interval_days. Step-level overrides take precedence over the template
  default. Steps with reminder_interval_days = nil are skipped. Admins can also
  trigger reminders manually. The full audit trail is exportable as CSV.

  # ── Auto-reminder job ────────────────────────────────────────────────────────

  Scenario Outline: Auto-reminder job sends emails to pending actors after interval
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is an actor user "reminder_actor@example.com" in the entity
    And there is a workflow template "name=Review;reminder_interval_days=3" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=actor_user"
    And the entity has a folder "name=Pending Docs"
    And the folder "Pending Docs" has workflow template "Review"
    And the folder "Pending Docs" has an active workflow instance for "Review"
    And the instance has been idle for 4 days
    When the auto-reminder job runs
    Then a reminder email should be enqueued for "reminder_actor@example.com"
    And a reminder state change should be logged for the instance

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Auto-reminder job does not send email before interval elapses
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is an actor user "early_actor@example.com" in the entity
    And there is a workflow template "name=Review;reminder_interval_days=7" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=actor_user"
    And the entity has a folder "name=Fresh Docs"
    And the folder "Fresh Docs" has workflow template "Review"
    And the folder "Fresh Docs" has an active workflow instance for "Review"
    And the instance has been idle for 2 days
    When the auto-reminder job runs
    Then no reminder email should be enqueued for "early_actor@example.com"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Step with nil reminder_interval_days is skipped by auto-reminder job
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is an actor user "no_remind@example.com" in the entity
    And there is a workflow template "name=Silent;reminder_interval_days=3" with 1 step "name=No Remind Step;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=actor_user;reminder_interval_days=nil"
    And the entity has a folder "name=Silent Docs"
    And the folder "Silent Docs" has workflow template "Silent"
    And the folder "Silent Docs" has an active workflow instance for "Silent"
    And the instance has been idle for 10 days
    When the auto-reminder job runs
    Then no reminder email should be enqueued for "no_remind@example.com"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Step-level reminder_interval_days overrides the template default
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is an actor user "step_override@example.com" in the entity
    And there is a workflow template "name=Override;reminder_interval_days=7" with 1 step "name=Fast Step;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=actor_user;reminder_interval_days=2"
    And the entity has a folder "name=Override Docs"
    And the folder "Override Docs" has workflow template "Override"
    And the folder "Override Docs" has an active workflow instance for "Override"
    And the instance has been idle for 3 days
    When the auto-reminder job runs
    Then a reminder email should be enqueued for "step_override@example.com"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: Auto-reminder skips actors who have already responded
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is an actor user "responded@example.com" in the entity
    And there is a workflow template "name=Review;reminder_interval_days=1" with 1 step "name=Step 1;states=Approved,Rejected;quorum_rule=all;on_reject_rule=stop;actors=actor_user"
    And the entity has a folder "name=Done Docs"
    And the folder "Done Docs" has workflow template "Review"
    And the folder "Done Docs" has an active workflow instance for "Review"
    And the actor "responded@example.com" has already responded "Approved" to the current step
    And the instance has been idle for 5 days
    When the auto-reminder job runs
    Then no reminder email should be enqueued for "responded@example.com"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Manual reminder ───────────────────────────────────────────────────────────

  Scenario Outline: Admin manually triggers a reminder and it is logged
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is an actor user "manual_actor@example.com" in the entity
    And there is a workflow template "name=LP Review" with 1 step "name=Initial Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=actor_user"
    And the entity has a folder "name=Manual Docs"
    And the folder "Manual Docs" has workflow template "LP Review"
    And the folder "Manual Docs" has an active workflow instance for "LP Review"
    When I send a manual reminder for the active instance
    Then a reminder email should be enqueued for "manual_actor@example.com"
    And a reminder state change should be logged for the instance

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Audit trail CSV export ────────────────────────────────────────────────────

  Scenario Outline: Exporting the audit trail produces a CSV with all state changes
    Given Im logged in as a user "<user>" for an entity "<entity>"
    And the user has role "company_admin"
    And there is an actor user "audit_actor@example.com" in the entity
    And there is a workflow template "name=LP Review" with 1 step "name=Initial Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=actor_user"
    And the entity has a folder "name=Audit Docs"
    And the folder "Audit Docs" has workflow template "LP Review"
    And the folder "Audit Docs" has an active workflow instance for "LP Review"
    And the actor "audit_actor@example.com" has already responded "Approved" to the current step
    When I export the audit trail for the active instance
    Then the CSV should include a row with to_state "Approved"
    And the CSV should have the correct headers

    Examples:
      | user | entity              |
      |      | entity_type=Company |
