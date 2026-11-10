@maker_checker
Feature: Request approval and the switch-off notice (OWASP review 2026-11 M13 — F6)
  With the setting on, someone who can't approve a call or distribution themselves clicks Request approval: every
  checker (an approver with fund access who didn't prepare it) gets an email and a bell alert, at most once an hour.
  Switching the setting off tells every other company admin and approver of the firm.
  Worked examples H18–H20, E32–E39, E56, H25, E54–E55:
  openspec/changes/archive/2026-11-10-capital-call-distribution-maker-checker/business-rules.md#6-request-approval--phase-3
  openspec/changes/archive/2026-11-10-capital-call-distribution-maker-checker/business-rules.md#8-switch-off-notice--phase-3

  # H18 — Happy path: Meera requests approval of Q4 → Ravi and Priya get the email and the bell; the popup said so
  Scenario: H18 The preparer requests approval
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" and "Priya" can approve "Q4 2026 Drawdown"
    When "Meera" opens the call "Q4 2026 Drawdown"
    Then the Request approval popup says:
      | Immediate Actions                                    |
      | Ravi Iyer and Priya Nair are emailed                  |
      | You can't approve it yourself                         |
      | You prepared it (prepared by Meera Shah)              |
      | Nothing else changes                                  |
      | The call stays unapproved and no investor is emailed. |
    When "Meera" requests approval of the call "Q4 2026 Drawdown"
    Then "Meera" sees the flash "Approval requested from Ravi Iyer and Priya Nair."
    And only "Ravi, Priya" receive the maker-checker email "Q4 2026 Drawdown (Nilgiri Growth Fund I) needs your approval"
    And "Ravi" has the bell alert "Q4 2026 Drawdown (Nilgiri Growth Fund I) needs your approval"
    And "Priya" has the bell alert "Q4 2026 Drawdown (Nilgiri Growth Fund I) needs your approval"

  # H19 — Happy path: Ravi follows the email's link → the call page, with Approve enabled for him
  Scenario: H19 The checker follows the link and can approve
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" and "Priya" can approve "Q4 2026 Drawdown"
    And "Meera" requests approval of the call "Q4 2026 Drawdown"
    When "Ravi" follows the link in the maker-checker email
    Then "Ravi" sees "Q4 2026 Drawdown" on the page
    And the page shows an enabled Approve

  # H20 — Happy path: Meera requests approval of a distribution → "Tea Estates Exit (Nilgiri Growth Fund I) needs your approval"
  Scenario: H20 Request approval of a distribution
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the distribution "Tea Estates Exit"
    And "Ravi" and "Priya" can approve "Tea Estates Exit"
    When "Meera" requests approval of the distribution "Tea Estates Exit"
    Then "Meera" sees the flash "Approval requested from Ravi Iyer and Priya Nair."
    And only "Ravi, Priya" receive the maker-checker email "Tea Estates Exit (Nilgiri Growth Fund I) needs your approval"

  # E32 — Edge case: only checkers are told — not the preparers (Meera, Anil), Tara (no fund access), Deepa (inactive),
  # Vikram (no Approver role), Arun (LP) or Kiran (another firm)
  Scenario: E32 Who is told
    Given the firm "Nilgiri Capital" has maker-checker on
    And the whole Nilgiri cast exists
    And "Meera" created the call "Q4 2026 Drawdown"
    And "Anil" changes the "₹1.2 Cr" remittance of "Q4 2026 Drawdown" to "₹1.25 Cr"
    When "Meera" requests approval of the call "Q4 2026 Drawdown"
    Then only "Ravi, Priya" receive the maker-checker email "Q4 2026 Drawdown (Nilgiri Growth Fund I) needs your approval"
    And "Tara" has no maker-checker bell alert
    And "Deepa" has no maker-checker bell alert
    And "Anil" has no maker-checker bell alert

  # E33 — Edge case: Anil (no Approver role) prepared it and asks → Ravi, Meera and Priya are told
  Scenario: E33 A preparer without the Approver role requests approval
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Anil" created the call "Anil Drawdown"
    And "Ravi", "Meera" and "Priya" can approve "Anil Drawdown"
    When "Anil" opens the call "Anil Drawdown"
    Then the page shows no Approve
    And the page shows Request approval
    When "Anil" requests approval of the call "Anil Drawdown"
    Then only "Ravi, Meera, Priya" receive the maker-checker email "Anil Drawdown (Nilgiri Growth Fund I) needs your approval"

  # E34 — Edge case: Ravi and Priya lost the Approver role → nothing is sent; the message says how to fix it
  Scenario: E34 No one else can approve
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" and "Priya" lose the Approver role
    When "Meera" opens the call "Q4 2026 Drawdown"
    Then the Request approval popup says:
      | No one else can approve this call yet |
      | Nothing will be sent.                 |
    When "Meera" requests approval of the call "Q4 2026 Drawdown"
    Then "Meera" sees the flash "No one else can approve this call. Ask a company admin to give the Approver role to a colleague with access to this fund, or turn off maker–checker in Settings."
    And no maker-checker email is sent

  # E35 — Edge case: Meera asked at 10:42 and asks again at 11:05 → refused with both times
  Scenario: E35 Asked again within the hour
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" and "Priya" can approve "Q4 2026 Drawdown"
    And the time is "2026-11-18 10:42"
    And "Meera" requests approval of the call "Q4 2026 Drawdown"
    And the time is "2026-11-18 11:05"
    When "Meera" requests approval of the call "Q4 2026 Drawdown"
    Then "Meera" sees the flash "Approvers were already asked at 10:42. You can ask again after 11:42."
    And only "Ravi, Priya" receive the maker-checker email "Q4 2026 Drawdown (Nilgiri Growth Fund I) needs your approval"

  # E36 — Edge case: Meera asked at 10:42 and asks again at 11:43 → sent again
  Scenario: E36 Asked again after the hour
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" and "Priya" can approve "Q4 2026 Drawdown"
    And the time is "2026-11-18 10:42"
    And "Meera" requests approval of the call "Q4 2026 Drawdown"
    And the time is "2026-11-18 11:43"
    When "Meera" requests approval of the call "Q4 2026 Drawdown"
    Then "Meera" sees the flash "Approval requested from Ravi Iyer and Priya Nair."
    And "Ravi" receives 2 maker-checker emails

  # E37 — Edge case: Solo Ventures (off) → no Request approval item; a direct POST is refused
  Scenario: E37 No Request approval when the setting is off
    Given "Sam" created the call "Solo Q4 Drawdown"
    When "Sam" opens the call "Solo Q4 Drawdown"
    Then the page shows no Request approval
    When "Sam" requests approval of the call "Solo Q4 Drawdown"
    Then "Sam" is refused with Access Denied

  # E38 — Edge case: Q4 already approved by Ravi → no Request approval item for Meera; a direct POST is refused
  Scenario: E38 No Request approval once approved
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" approved the call "Q4 2026 Drawdown"
    When "Meera" opens the call "Q4 2026 Drawdown"
    Then the page shows no Request approval
    When "Meera" requests approval of the call "Q4 2026 Drawdown"
    Then "Meera" is refused with Access Denied

  # E39 — Edge case: the email names the call, fund, ₹5,00,00,000, the due date "Dec 15, 2026", the preparers and a link
  Scenario: E39 The approval request email says what is waiting and why
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" and "Priya" can approve "Q4 2026 Drawdown"
    When "Meera" requests approval of the call "Q4 2026 Drawdown"
    Then the maker-checker email to "Ravi" says "Call: Q4 2026 Drawdown"
    And the maker-checker email to "Ravi" says "Fund: Nilgiri Growth Fund I"
    And the maker-checker email to "Ravi" says "5,00,00,000"
    And the maker-checker email to "Ravi" says "Due date: Dec 15, 2026"
    And the maker-checker email to "Ravi" says "Prepared by: Meera Shah"
    And the maker-checker email to "Ravi" says "Why you got this: Meera Shah asked for this call to be approved."
    And the maker-checker email to "Ravi" says "Open call"

  # E56 — Edge case: Ravi (a checker) is not offered Request approval — he can approve; a direct POST is refused
  Scenario: E56 A checker is not offered Request approval
    Given the firm "Nilgiri Capital" has maker-checker on
    And "Meera" created the call "Q4 2026 Drawdown"
    When "Ravi" opens the call "Q4 2026 Drawdown"
    Then the page shows no Request approval
    When "Ravi" requests approval of the call "Q4 2026 Drawdown"
    Then "Ravi" is refused with Access Denied

  # H25 — Happy path: Ravi switches it off on Nov 19, 2026 → Meera, Priya and Tara are told; not Ravi, Deepa (inactive) or Arun
  Scenario: H25 Switching maker-checker off is announced
    Given the firm "Nilgiri Capital" has maker-checker on
    And the whole Nilgiri cast exists
    And the time is "2026-11-19 14:02"
    When "Ravi" switches maker-checker off on the entity form
    Then maker-checker is off for "Nilgiri Capital"
    And only "Meera, Priya, Tara" receive the maker-checker email "Maker–checker for calls and distributions was turned off"
    And "Meera" has the bell alert "Maker–checker for calls and distributions was turned off by Ravi Iyer on Nov 19, 2026."
    And the maker-checker email to "Meera" says "If you did not, a company admin can switch it back on"
    And "Ravi" has no maker-checker bell alert
    And "Deepa" has no maker-checker bell alert

  # E54 — Edge case: Ravi switches it on → nothing is sent
  Scenario: E54 Switching on sends nothing
    Given the firm "Nilgiri Capital" has maker-checker off
    And the whole Nilgiri cast exists
    When "Ravi" switches maker-checker on on the entity form
    Then maker-checker is on for "Nilgiri Capital"
    And no maker-checker email is sent

  # E55 — Edge case: Ravi saves the entity form with the setting unchanged → nothing is sent
  Scenario: E55 Saving unchanged sends nothing
    Given the firm "Nilgiri Capital" has maker-checker on
    And the whole Nilgiri cast exists
    When "Ravi" saves the entity form with only a new name
    Then no maker-checker email is sent
