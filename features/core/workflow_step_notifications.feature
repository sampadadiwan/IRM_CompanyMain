Feature: Workflow Step Notifications
  Each workflow step defaults to emailing its assigned actors when the step becomes the
  active step (on launch, or once an earlier step passes). A step can opt out via
  notify_on_activation, so bulk operations — e.g. an auto-assignment rule firing on a
  large investor_kyc import — don't slam actors with one email per launched instance.
  The suppression is per-step (other steps in the same template still notify normally)
  and applies wherever notify_step_actors fires (launch and reset).

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"

  # ── Silent step suppresses the activation email ───────────────────────────────

  Scenario Outline: A silent step does not email actors when it becomes the active step
    Given there is a workflow template "name=Silent Launch" with 1 step "name=Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And step 1 of the workflow template is set to not notify actors
    And the entity has a folder "name=Silent Folder"
    And the folder "Silent Folder" has workflow template "Silent Launch"
    When I launch the workflow for folder "Silent Folder"
    Then no step-activation email should have been sent

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Default behaviour is unchanged ────────────────────────────────────────────

  @rack_test
  Scenario Outline: A normal step still emails actors when it becomes the active step
    Given there is a workflow template "name=Normal Launch" with 1 step "name=Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the entity has a folder "name=Normal Folder"
    And the folder "Normal Folder" has workflow template "Normal Launch"
    When I launch the workflow for folder "Normal Folder"
    Then a step-activation email should have been sent

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Suppression is per-step, not template-wide ────────────────────────────────

  Scenario Outline: A silent step does not stop other steps in the same template from notifying
    Given there is a workflow template "name=Mixed Steps" with 2 steps:
      | name      | states            | quorum_rule | on_reject_rule | actors |
      | Step One  | Approved,Rejected | any_one     | stop           | admin  |
      | Step Two  | Approved,Rejected | any_one     | stop           | admin  |
    And step 2 of the workflow template is set to not notify actors
    And the entity has a folder "name=Mixed Folder"
    And the folder "Mixed Folder" has workflow template "Mixed Steps"
    When I launch the workflow for folder "Mixed Folder"
    Then a step-activation email should have been sent

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  # ── Suppression also applies on reset (same notify_step_actors code path) ────

  Scenario Outline: A silent step does not re-notify actors on reset
    Given there is a workflow template "name=Silent Reset" with 2 steps:
      | name      | states            | quorum_rule | on_reject_rule | actors |
      | Step One  | Approved,Rejected | any_one     | stop           | admin  |
      | Step Two  | Approved,Rejected | any_one     | stop           | admin  |
    And step 1 of the workflow template is set to not notify actors
    And the entity has a folder "name=Silent Reset Folder"
    And the folder "Silent Reset Folder" has workflow template "Silent Reset"
    And the folder "Silent Reset Folder" has an active workflow instance for "Silent Reset" at step 2
    When I reset the active workflow for folder "Silent Reset Folder"
    Then no step-activation email should have been sent

    Examples:
      | user | entity              |
      |      | entity_type=Company |
