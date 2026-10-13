Feature: Evaluated workflow steps (journeys)
  A workflow with system or acknowledge steps is worked out from data: the evaluator walks the
  steps, stops at the first one not done, moves back when data stops satisfying a step, and resets
  later sign-offs only when a user's undoing action caused it.
  These scenarios use test checks (test.flag_1 …) that read the record's json_fields, so they need
  no capital call. Worked examples H4, H8, E9, E10c, E11, E26, X3, X6 in
  openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user has role "company_admin"
    And the entity has an investor_kyc "name=Asha"

  # H4 — Acknowledge a step
  @rack_test
  Scenario: Mark reviewed passes an acknowledge step and the journey moves on
    Given there is a journey template "KYC Journey" with steps:
      | name        | kind        | check       |
      | Documents   | system      | test.flag_1 |
      | Review      | acknowledge | test.always |
      | Final check | system      | test.flag_2 |
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the investor_kyc "Asha" has flag "flag_1" set
    When the journey for investor_kyc "Asha" is evaluated
    Then the journey should show:
      | step        | status  |
      | Documents   | passed  |
      | Review      | current |
      | Final check | not_yet |
    When I mark step "Review" reviewed on the investor_kyc "Asha"
    Then the journey should show:
      | step        | status  |
      | Review      | passed  |
      | Final check | current |
    And the history should show "passed" for step "Review"

  # H8 — Human step after system steps
  @rack_test
  Scenario: Approving a human step moves past system steps that already pass
    Given there is a journey template "KYC Journey" with steps:
      | name        | kind   | check       | actors |
      | Documents   | system | test.flag_1 |        |
      | CFO sign-off| human  |             | admin  |
      | Final check | system | test.flag_2 |        |
      | Archive     | system | test.flag_3 |        |
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the investor_kyc "Asha" has flags "flag_1,flag_2" set
    And the journey for investor_kyc "Asha" is evaluated
    When the actor submits "Approved" on the current step of the investor_kyc "Asha"
    Then the journey current step should be "Archive"
    And the journey should show:
      | step         | status  |
      | CFO sign-off | passed  |
      | Final check  | passed  |
      | Archive      | current |

  # E9 — keep_on_regress
  Scenario Outline: An undo resets later sign-offs unless the step keeps them
    Given there is a journey template "KYC Journey" with steps:
      | name         | kind   | check       | actors | keep_on_regress |
      | Documents    | system | test.flag_1 |        |                 |
      | CFO sign-off | human  |             | admin  | <keep>          |
      | Final check  | system | test.flag_2 |        |                 |
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the investor_kyc "Asha" has flag "flag_1" set
    And the journey for investor_kyc "Asha" is evaluated
    And the actor submits "Approved" on the current step of the investor_kyc "Asha"
    When an undoing action clears flag "flag_1" on the investor_kyc "Asha" with note "Documents withdrawn"
    Then the journey current step should be "Documents"
    And the CFO vote on step "CFO sign-off" should be <vote>
    And the history should show "regressed" for step "Documents" with note "Documents withdrawn"

    Examples:
      | keep | vote     |
      |      | archived |
      | true | kept     |

  # E10c — a passive evaluation during a long undo does not use up the reset
  @rack_test
  Scenario: The undo's own evaluation still resets sign-offs a page view saw first
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
    When a long undoing action clears flag "flag_1" on the investor_kyc "Asha" and the journey is viewed before it finishes
    Then the CFO vote on step "CFO sign-off" should be archived

  # E11 — Passive move back does not clear sign-offs
  @rack_test
  Scenario: A move back found by a page view is recorded but resets nothing
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
    When the investor_kyc "Asha" has flag "flag_1" cleared
    And the journey for investor_kyc "Asha" is evaluated
    Then the journey current step should be "Documents"
    And the history should show "regressed" for step "Documents"
    And the CFO vote on step "CFO sign-off" should be kept

  # E26 — Rejecting a journey step means "vote again"
  @rack_test
  Scenario: A rejected journey step stays current with the note and the journey stays active
    Given there is a journey template "KYC Journey" with steps:
      | name         | kind   | check       | actors |
      | Documents    | system | test.flag_1 |        |
      | CFO sign-off | human  |             | admin  |
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the investor_kyc "Asha" has flag "flag_1" set
    And the journey for investor_kyc "Asha" is evaluated
    When the actor rejects the current step of the investor_kyc "Asha" with note "Fee looks wrong"
    Then the journey current step should be "CFO sign-off"
    And the journey message for "CFO sign-off" should include "Fee looks wrong"
    And the journey instance should be active
    When the actor submits "Approved" on the current step of the investor_kyc "Asha"
    Then the journey should be complete

  # X3 — A user without update rights cannot confirm
  @rack_test
  Scenario: Mark reviewed is refused for a user without update rights on the record
    Given there is a journey template "KYC Journey" with steps:
      | name   | kind        | check |
      | Review | acknowledge | test.always |
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the journey for investor_kyc "Asha" is evaluated
    When a view-only employee "vik@example.com" posts Mark reviewed for step "Review" on the investor_kyc "Asha"
    Then the journey current step should be "Review"
    And no confirmation should be recorded for step "Review"

  # X6 — A check that raises
  @rack_test
  Scenario: A failing check shows an error on its step and stops the walk there
    Given there is a journey template "KYC Journey" with steps:
      | name      | kind   | check        |
      | Documents | system | test.flag_1  |
      | Broken    | system | test.raises  |
      | Later     | system | test.flag_2  |
    And the investor_kyc "Asha" has workflow template "KYC Journey"
    And I launch the workflow for investor_kyc "Asha"
    And the investor_kyc "Asha" has flags "flag_1,flag_2" set
    When the journey for investor_kyc "Asha" is evaluated
    Then the journey should show:
      | step      | status  |
      | Documents | passed  |
      | Broken    | error   |
      | Later     | not_yet |
    And the journey message for "Broken" should include "Could not check this step"
