Feature: Journey ticks and reminders
  A 15-minute tick re-evaluates every journey so progress made without anyone looking is picked
  up and approvers of a newly current human step are told promptly. The daily reminder job
  evaluates first, then reminds the owner of a stalled system/acknowledge step, timing intervals
  from when the step became current. Human-only workflows are untouched.
  Worked examples H9, H15, H16, H17, E8, E16, X4 in openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"
    And the entity has an investor_kyc "name=Asha"

  # H9 — Owner reminder
  Scenario: The owner of a stalled system step is reminded
    Given there is a journey template "KYC Journey" with steps:
      | name      | kind   | check       | owner | reminder_days |
      | Documents | system | test.flag_1 | admin | 2             |
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the journey for investor_kyc "Asha" is evaluated
    When 3 days pass
    And the daily reminder job runs
    Then the user should receive an owner reminder for "Documents"
    And the history should show "owner_reminded" for step "Documents"
    When the daily reminder job runs
    Then no owner reminder should have been sent

  # H15 — Late detection still timed from the data
  Scenario: A step completed while nobody looked is stamped with the real time
    Given there is a journey template "KYC Journey" with steps:
      | name      | kind   | check       | owner | reminder_days |
      | Documents | system | test.flag_1 |       |               |
      | Final     | system | test.flag_2 | admin | 2             |
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the journey for investor_kyc "Asha" was launched 5 days ago
    And the investor_kyc "Asha" has flag "flag_1" set 3 days ago
    When the 15-minute tick runs
    Then step "Documents" should be recorded as passed 3 days ago
    And step "Final" should be current since 3 days ago
    When the daily reminder job runs
    Then the user should receive an owner reminder for "Final"

  # H16 — The tick tells an approver without anyone viewing
  Scenario: A human step reached by the tick emails its approvers
    Given there is a journey template "KYC Journey" with steps:
      | name         | kind   | check       | actors |
      | Documents    | system | test.flag_1 |        |
      | CFO sign-off | human  |             | admin  |
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the journey for investor_kyc "Asha" is evaluated
    And the investor_kyc "Asha" has flag "flag_1" set
    When the 15-minute tick runs
    Then the journey current step should be "CFO sign-off"
    And a step-activation email should have been sent

  # H17 — The tick leaves approval workflows alone
  Scenario: The tick never touches a human-only workflow
    Given there is a workflow template "name=KYC Review" with 1 step "name=Review;states=Approved,Rejected;quorum_rule=any_one;on_reject_rule=stop;actors=admin"
    And the investor_kyc "Asha" has workflow template "KYC Review"
    And the investor_kyc "Asha" has an active workflow instance for "KYC Review"
    When the 15-minute tick runs
    Then the human-only instance for investor_kyc "Asha" should be unchanged

  # E16 — No interval, no reminder
  Scenario: A step without a reminder interval is never reminded
    Given there is a journey template "KYC Journey" with steps:
      | name      | kind   | check       | owner |
      | Documents | system | test.flag_1 | admin |
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the journey for investor_kyc "Asha" is evaluated
    When 10 days pass
    And the daily reminder job runs
    Then no owner reminder should have been sent

  # X4 — Owner unavailable
  Scenario: No reminder when the owner is no longer active
    Given there is a journey template "KYC Journey" with steps:
      | name      | kind   | check       | owner | reminder_days |
      | Documents | system | test.flag_1 | admin | 1             |
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the journey for investor_kyc "Asha" is evaluated
    And the user is deactivated
    When 3 days pass
    And the daily reminder job runs
    Then no owner reminder should have been sent

  # E8 at engine level — the reset email reaches the approver (WorkflowMailer#sign_off_reset)
  Scenario: An approver whose sign-off is reset by an undo is emailed
    Given there is a journey template "KYC Journey" with steps:
      | name         | kind   | check       | actors |
      | Documents    | system | test.flag_1 |        |
      | CFO sign-off | human  |             | admin  |
      | Final check  | system | test.flag_2 |        |
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the investor_kyc "Asha" has flag "flag_1" set
    And the journey for investor_kyc "Asha" is evaluated
    And the actor submits "Approved" on the current step of the investor_kyc "Asha"
    When an undoing action clears flag "flag_1" on the investor_kyc "Asha" with note "Documents withdrawn"
    Then the user should receive a sign-off reset email mentioning "Documents withdrawn"
