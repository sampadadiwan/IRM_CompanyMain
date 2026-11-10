@maker_checker
Feature: Maker–checker firm setting (OWASP review 2026-11 M13 — F1)
  A company admin can require a second person to approve capital calls and distributions. The switch is off for
  every firm, existing and new, so nothing changes until a firm turns it on; only the firm's company admins can
  change it, and every change is in the entity's audit trail.
  Worked examples H1, E1–E3, X1–X2:
  openspec/changes/archive/2026-11-10-capital-call-distribution-maker-checker/business-rules.md#1-firm-setting--phase-1

  # H1 — Happy path: Ravi (company admin) ticks the switch and saves; the audit trail names him, false → true
  Scenario: H1 A company admin switches maker-checker on
    Given the firm "Nilgiri Capital" has maker-checker off
    When "Ravi" switches maker-checker on on the entity form
    Then "Ravi" sees the flash "Entity was successfully updated."
    And maker-checker is on for "Nilgiri Capital"
    And the entity audit of "Nilgiri Capital" shows "Ravi" switched maker-checker from false to true

  # H1 / U.1 — the Approvals block explains itself: what the switch does, who counts as a preparer, what switching off does
  Scenario: H1 The entity form explains the switch
    Given the firm "Nilgiri Capital" has maker-checker off
    When "Ravi" opens the entity form
    Then the entity form has the maker-checker switch with its explanation

  # E1 — Edge case: a firm that existed before release keeps today's behaviour — Sam approves his own call
  Scenario: E1 An existing firm is off and self-approval works as before
    Given "Sam" created the call "Solo Q4 Drawdown"
    Then maker-checker is off for "Solo Ventures"
    When "Sam" approves the call "Solo Q4 Drawdown"
    Then the call "Solo Q4 Drawdown" is approved by "Sam"

  # E2 — Edge case: a firm created after release starts off too (the user's decision on open question 1)
  Scenario: E2 A new firm starts with maker-checker off
    When CapHive support creates the firm "Ganga Fund Advisors"
    Then maker-checker is off for "Ganga Fund Advisors"

  # E3 — Edge case: saving the entity form without touching the switch leaves it on and records no setting change
  Scenario: E3 Saving the form without touching the switch keeps it
    Given the firm "Nilgiri Capital" has maker-checker on
    When "Ravi" saves the entity form with only a new name
    Then maker-checker is on for "Nilgiri Capital"
    And the entity audit of "Nilgiri Capital" has no maker-checker change

  # X1 — Error case: Meera (not a company admin) sends the entity form directly with the switch off → refused
  Scenario: X1 A non-admin cannot change the setting
    Given the firm "Nilgiri Capital" has maker-checker on
    When "Meera" saves the entity form of "Nilgiri Capital" with maker-checker off
    Then "Meera" is refused with Access Denied
    And maker-checker is on for "Nilgiri Capital"

  # X2 — Error case: Kiran, company admin of another firm, sends Nilgiri's entity form → refused
  Scenario: X2 Another firm's admin cannot change the setting
    Given the firm "Nilgiri Capital" has maker-checker on
    When "Kiran" saves the entity form of "Nilgiri Capital" with maker-checker off
    Then "Kiran" is refused with Access Denied
    And maker-checker is on for "Nilgiri Capital"
