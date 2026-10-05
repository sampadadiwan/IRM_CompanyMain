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
    When an undoing action by a colleague clears flag "flag_1" on the investor_kyc "Asha" with note "Documents withdrawn"
    Then the user should receive a sign-off reset email mentioning "Documents withdrawn"

  # ── Review needed / journey complete emails, Send email / Send WhatsApp switches ──
  # Every workflow message goes through WorkflowNotifier: logged as a notification, gated by the
  # template's Send email / Send WhatsApp switches, WhatsApp only ever to employees.

  # The person whose own click moved the journey on is already on the page, so the next step's
  # review / sign-off email skips them (WorkflowEvaluator#notify passes the actor through)
  Scenario: The owner is emailed as soon as an acknowledge step needs review, unless they moved it there
    Given there is a journey template "KYC Journey" with steps:
      | name          | kind        | check       | owner | actors |
      | Documents     | system      | test.flag_1 |       |        |
      | Review        | acknowledge | test.always | admin |        |
      | Second review | acknowledge | test.always | admin |        |
      | CFO sign-off  | human       |             |       | admin  |
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the journey for investor_kyc "Asha" is evaluated
    And the investor_kyc "Asha" has flag "flag_1" set
    When the journey for investor_kyc "Asha" is evaluated again
    Then the journey current step should be "Review"
    And the user should receive a workflow email starting "Needs your review: Review"
    And the user should have a workflow notification for "review_needed"
    When I mark step "Review" reviewed on the investor_kyc "Asha"
    Then the journey current step should be "Second review"
    And no workflow email starting "Needs your review: Second review" should have been sent
    When I mark step "Second review" reviewed on the investor_kyc "Asha"
    Then the journey current step should be "CFO sign-off"
    And no workflow email starting "Action Required" should have been sent

  Scenario: A review step set not to notify on activation sends no review email
    Given there is a journey template "KYC Journey" with steps:
      | name      | kind        | check       | owner | notify |
      | Documents | system      | test.flag_1 |       |        |
      | Review    | acknowledge | test.always | admin | false  |
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the journey for investor_kyc "Asha" is evaluated
    And the investor_kyc "Asha" has flag "flag_1" set
    When the journey for investor_kyc "Asha" is evaluated again
    Then the journey current step should be "Review"
    And no workflow email starting "Needs your review" should have been sent

  Scenario: A journey that lands on a review step at launch emails nobody
    Given there is a journey template "KYC Journey" with steps:
      | name      | kind        | check       | owner |
      | Documents | system      | test.flag_1 |       |
      | Review    | acknowledge | test.always | admin |
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the investor_kyc "Asha" has flag "flag_1" set
    When the journey for investor_kyc "Asha" is evaluated again
    Then the journey current step should be "Review"
    And no workflow email starting "Needs your review" should have been sent

  Scenario: The owner of the last step is told when the journey completes
    Given there is a journey template "KYC Journey" with steps:
      | name      | kind   | check       | owner |
      | Documents | system | test.flag_1 | admin |
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the journey for investor_kyc "Asha" is evaluated
    And the investor_kyc "Asha" has flag "flag_1" set
    When the journey for investor_kyc "Asha" is evaluated again
    Then the journey should be complete
    And the user should receive a workflow email starting "Complete: KYC Journey"
    And the user should have a workflow notification for "journey_complete"

  Scenario: A journey already finished when it is launched sends no completion email
    Given there is a journey template "KYC Journey" with steps:
      | name      | kind   | check       | owner |
      | Documents | system | test.flag_1 | admin |
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the investor_kyc "Asha" has flag "flag_1" set
    When the journey for investor_kyc "Asha" is evaluated again
    Then the journey should be complete
    And no workflow email starting "Complete:" should have been sent

  Scenario: With Send email off, an approver reached by the tick is not emailed
    Given there is a journey template "KYC Journey" with steps:
      | name         | kind   | check       | actors |
      | Documents    | system | test.flag_1 |        |
      | CFO sign-off | human  |             | admin  |
    And the workflow template "KYC Journey" has "Send email" turned off
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the journey for investor_kyc "Asha" is evaluated
    And the investor_kyc "Asha" has flag "flag_1" set
    When the 15-minute tick runs
    Then the journey current step should be "CFO sign-off"
    And no step-activation email should have been sent
    But the user should have a workflow notification for "step_activation"

  Scenario: With Send email off, a stalled step's owner is not emailed
    Given there is a journey template "KYC Journey" with steps:
      | name      | kind   | check       | owner | reminder_days |
      | Documents | system | test.flag_1 | admin | 2             |
    And the workflow template "KYC Journey" has "Send email" turned off
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the journey for investor_kyc "Asha" is evaluated
    When 3 days pass
    And the daily reminder job runs
    Then no owner reminder should have been sent

  # The WhatsApp send is hard-off in test (a real WATI call), so these run the employee WhatsApp
  # delivery directly with the sender captured — they prove who would be messaged, not WATI itself
  Scenario: With Send WhatsApp on, the owner also gets the review on WhatsApp
    Given there is a journey template "KYC Journey" with steps:
      | name      | kind        | check       | owner |
      | Documents | system      | test.flag_1 |       |
      | Review    | acknowledge | test.always | admin |
    And the workflow template "KYC Journey" has "Send WhatsApp" turned on
    And WhatsApp is enabled for the entity and the user
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the journey for investor_kyc "Asha" is evaluated
    And the investor_kyc "Asha" has flag "flag_1" set
    And the journey for investor_kyc "Asha" is evaluated again
    When the employee WhatsApp delivery runs for the user's "review_needed" workflow notification
    Then a WhatsApp starting "Needs your review: Review" should have been sent to the user

  Scenario: With Send WhatsApp off, nobody gets a WhatsApp
    Given there is a journey template "KYC Journey" with steps:
      | name      | kind        | check       | owner |
      | Documents | system      | test.flag_1 |       |
      | Review    | acknowledge | test.always | admin |
    And WhatsApp is enabled for the entity and the user
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the journey for investor_kyc "Asha" is evaluated
    And the investor_kyc "Asha" has flag "flag_1" set
    And the journey for investor_kyc "Asha" is evaluated again
    When the employee WhatsApp delivery runs for the user's "review_needed" workflow notification
    Then no WhatsApp should have been sent

  Scenario: A workflow message to someone outside the organisation never goes on WhatsApp
    Given there is a journey template "KYC Journey" with steps:
      | name      | kind        | check       | owner |
      | Review    | acknowledge | test.always | admin |
    And the workflow template "KYC Journey" has "Send WhatsApp" turned on
    And WhatsApp is enabled for the entity and the user
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And a WhatsApp-enabled user of another organisation is sent the "review_needed" workflow message for investor_kyc "Asha"
    When the employee WhatsApp delivery runs for that user's "review_needed" workflow notification
    Then no WhatsApp should have been sent
