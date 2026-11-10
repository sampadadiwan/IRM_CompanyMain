@maker_checker
Feature: Approving a capital call with maker–checker (OWASP review 2026-11 M13 — F3)
  With the firm's setting on, whoever prepared a call cannot approve it: the page shows Approve greyed out with the
  reason and offers Request approval instead. An approver who did not prepare it approves exactly as today. With the
  setting off nothing changes, except that a self-approval is labelled "also prepared it".
  Worked examples H12–H15, E15–E27:
  openspec/changes/archive/2026-11-10-capital-call-distribution-maker-checker/business-rules.md#3-approving-a-capital-call--phase-2

  # H12 — Happy path: Ravi (not a preparer) approves Meera's call → approved by Ravi
  Scenario: H12 A checker approves the call
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the call "Q4 2026 Drawdown"
    When "Ravi" opens the call "Q4 2026 Drawdown"
    Then the page shows an enabled Approve
    And the page shows no Request approval
    When "Ravi" approves the call "Q4 2026 Drawdown"
    Then "Ravi" sees the flash "Capital call was successfully approved."
    And the call "Q4 2026 Drawdown" is approved by "Ravi"

  # H13 — Happy path: Meera opens Actions on her own call → Approve greyed out with the reason; Request approval shown
  Scenario: H13 The preparer sees why Approve is greyed out
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the call "Q4 2026 Drawdown"
    When "Meera" opens the call "Q4 2026 Drawdown"
    Then the page shows Approve disabled with the reason "You prepared this call, so another approver must approve it (maker–checker is on)."
    And the page shows Request approval

  # H14 — Happy path: Solo Ventures (off) — Sam creates and approves his call → labelled "also prepared it"
  Scenario: H14 Setting off keeps self-approval, labelled
    Given "Sam" created the call "Solo Q4 Drawdown"
    When "Sam" approves the call "Solo Q4 Drawdown"
    Then the call "Solo Q4 Drawdown" is approved by "Sam"
    When "Sam" opens the call "Solo Q4 Drawdown"
    Then the Approved row shows "Yes · by Sam Mehta (also prepared it)"
    And the page shows no Request approval

  # H15 — Happy path: Meera created Q4, Anil edited a remittance → "Prepared by: Meera Shah, Anil Rao" with its ⓘ
  Scenario: H15 The page lists the preparers
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the call "Q4 2026 Drawdown"
    And "Anil" changes the "₹1.2 Cr" remittance of "Q4 2026 Drawdown" to "₹1.25 Cr"
    When "Ravi" opens the call "Q4 2026 Drawdown"
    Then the Prepared by row shows "Meera Shah, Anil Rao"
    And the Prepared by tooltip says "People who created, imported or changed this call's figures"
    And the Prepared by tooltip says "none of them can approve this call"

  # E15 — Edge case: Ravi (company admin + approver) changed a remittance → Approve greyed out for Ravi; Priya approves
  Scenario: E15 An admin-approver who edited figures cannot approve
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" changes the "₹1.2 Cr" remittance of "Q4 2026 Drawdown" to "₹1.25 Cr"
    When "Ravi" opens the call "Q4 2026 Drawdown"
    Then the page shows Approve disabled with the reason "You prepared this call"
    When "Priya" approves the call "Q4 2026 Drawdown"
    Then the call "Q4 2026 Drawdown" is approved by "Priya"

  # E16 — Edge case: a call created by Anil only (no Approver role) → Meera approves it
  Scenario: E16 An approver who is not a preparer approves
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Anil" created the call "Anil Drawdown"
    When "Meera" approves the call "Anil Drawdown"
    Then the call "Anil Drawdown" is approved by "Meera"

  # E17 — Edge case: Priya imported "Q1 2027 Drawdown" → greyed out for Priya; Ravi approves
  Scenario: E17 The importer cannot approve the imported call
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Priya" imported the call "Q1 2027 Drawdown"
    When "Priya" opens the call "Q1 2027 Drawdown"
    Then the page shows Approve disabled with the reason "You prepared this call"
    When "Ravi" approves the call "Q1 2027 Drawdown"
    Then the call "Q1 2027 Drawdown" is approved by "Ravi"

  # E18 — Edge case: Q4 self-approved by Meera while off; Ravi switches on → stays approved; Unapprove offered to both
  Scenario: E18 Approvals given before switching on stay valid
    Given the firm "Nilgiri Capital" has maker-checker off
    And "Meera" created the call "Q4 2026 Drawdown"
    And "Meera" approved the call "Q4 2026 Drawdown"
    When "Ravi" switches maker-checker on on the entity form
    Then the call "Q4 2026 Drawdown" is approved by "Meera"
    When "Meera" opens the call "Q4 2026 Drawdown"
    Then the page shows Unapprove
    When "Ravi" opens the call "Q4 2026 Drawdown"
    Then the page shows Unapprove

  # E19 — Edge case: on; Q4 approved by Ravi; Meera (a preparer) unapproves → unapproved, as today
  Scenario: E19 A preparer may still unapprove
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" approved the call "Q4 2026 Drawdown"
    When "Meera" unapproves the call "Q4 2026 Drawdown"
    Then "Meera" sees the flash "Capital call was reverted to unapproved."
    And the call "Q4 2026 Drawdown" is not approved

  # E20 — Edge case: on → off; Meera approves her own call → approved, labelled "also prepared it"
  Scenario: E20 Switched off again, self-approval works and is labelled
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the call "Q4 2026 Drawdown"
    And the firm "Nilgiri Capital" has maker-checker off
    When "Meera" approves the call "Q4 2026 Drawdown"
    Then the call "Q4 2026 Drawdown" is approved by "Meera"
    When "Meera" opens the call "Q4 2026 Drawdown"
    Then the Approved row shows "Yes · by Meera Shah (also prepared it)"

  # E21 — Edge case: Tara (Approver, no fund access) opens Q4 → Access Denied, unchanged
  Scenario: E21 An approver without fund access is refused as today
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the call "Q4 2026 Drawdown"
    When "Tara" opens the call "Q4 2026 Drawdown"
    Then "Tara" is refused with Access Denied

  # E22 — Edge case: a blocker validation rule fires (unapproved generated notice) → Ravi is blocked with the rule's message
  Scenario: E22 A validation rule blocker still stops the checker
    Given the firm "Nilgiri Capital" has maker-checker on
    And the default validation rules are seeded
    And "Meera" created the call "Q4 2026 Drawdown"
    And the call "Q4 2026 Drawdown" has an unapproved generated notice
    When "Ravi" approves the call "Q4 2026 Drawdown"
    Then "Ravi" sees the flash "generated call notice(s) pending approval"
    And the call "Q4 2026 Drawdown" is not approved

  # E23 — Edge case: unapproved generated notices (no rules) → "Call not approved: There are unapproved documents…"
  Scenario: E23 Unapproved notices still stop the checker
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the call "Q4 2026 Drawdown"
    And the call "Q4 2026 Drawdown" has an unapproved generated notice
    When "Ravi" approves the call "Q4 2026 Drawdown"
    Then "Ravi" sees the flash "Call not approved: There are unapproved documents for the remittances of this call. Please approve them first."
    And the call "Q4 2026 Drawdown" is not approved

  # E24 — Edge case: journey panel at Approve call, setting on → says a second approver is needed
  Scenario: E24 The journey says a second approver is needed
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the call "Q4 2026 Drawdown"
    When the Approve call journey check runs for "Q4 2026 Drawdown"
    Then the journey check says "The call is not approved yet — it needs an approver who did not prepare it"

  # E25 — Edge case: journey panel at Approve call, setting off → today's message
  Scenario: E25 The journey message is unchanged when off
    Given "Sam" created the call "Solo Q4 Drawdown"
    When the Approve call journey check runs for "Solo Q4 Drawdown"
    Then the journey check says "The call is not approved yet"

  # E26 — Edge case: Meera's legacy call (creator only in the audit trail), setting on → greyed out for Meera
  Scenario: E26 The legacy creator cannot approve
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the call "Q3 2026 Drawdown" before maker-checker existed
    When "Meera" opens the call "Q3 2026 Drawdown"
    Then the page shows Approve disabled with the reason "You prepared this call"
    When "Meera" approves the call "Q3 2026 Drawdown"
    Then "Meera" is refused with Access Denied

  # E27 — Edge case: an open-ended fund's dealing date settles → the settlement call is created approved, unchanged
  Scenario: E27 Open-ended settlements are created approved as today
    Given the firm "Nilgiri Capital" has maker-checker on
    And the fund of "Nilgiri Capital" settles a dealing date
    When "Ravi" creates the subscription settlement
    Then the settlement is approved with no preparer recorded
