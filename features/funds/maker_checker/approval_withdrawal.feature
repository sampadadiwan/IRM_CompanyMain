@maker_checker
Feature: Figure changes after approval withdraw it (OWASP review 2026-11 M13 — F7)
  With the setting on, a person who changes the figures of an approved call or distribution — or of its
  remittances, payments or fee lines — un-approves it in the same save. The editor's flash says so, the journey
  goes back to Approve with a note, and the approvers and preparers are told. Non-figure edits, payments received,
  verification, late commitments, jobs with nobody behind them and open-ended settlements keep the approval.
  Worked examples H21–H24, E40–E53, X16:
  openspec/changes/capital-call-distribution-maker-checker/business-rules.md#7-withdrawal-on-figure-change--phase-3

  Background:
    Given the firm "Nilgiri Capital" has maker-checker on
    And the whole Nilgiri cast exists

  # H21 — Happy path: Q4 approved by Ravi; Anil changes 10% → 12% → unapproved; flash and journey note say why
  Scenario: H21 Changing the call's figures after approval withdraws it
    Given "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" approved the call "Q4 2026 Drawdown"
    When "Anil" changes the percentage of "Q4 2026 Drawdown" to 12%
    Then "Anil" sees the flash "Capital call was successfully updated. Its approval was withdrawn because the figures changed — another approver must approve it again."
    And the call "Q4 2026 Drawdown" is not approved
    And the call "Q4 2026 Drawdown" was withdrawn by "Anil" in its audit trail

  # H22 — Happy path: Anil changes a remittance ₹1.2 Cr → ₹1.25 Cr → unapproved; Ravi, Priya, Meera told; not Anil or Tara
  Scenario: H22 Changing a remittance after approval withdraws it and tells the approvers
    Given "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" approved the call "Q4 2026 Drawdown"
    When "Anil" changes the "₹1.2 Cr" remittance of "Q4 2026 Drawdown" to "₹1.25 Cr"
    Then "Anil" sees the flash "Capital remittance was successfully updated. Its approval was withdrawn because the figures changed — another approver must approve it again."
    And the call "Q4 2026 Drawdown" is not approved
    And only "Ravi, Priya, Meera" receive the maker-checker email "Approval of Q4 2026 Drawdown was withdrawn"
    And "Ravi" has the bell alert "Approval of Q4 2026 Drawdown was withdrawn: Anil Rao changed its figures after approval."
    And "Anil" has no maker-checker bell alert
    And "Tara" has no maker-checker bell alert

  # H23 — Happy path: Tea Estates approved; Anil changes a payment's income → distribution unapproved; alert sent
  Scenario: H23 Changing a payment after approval withdraws the distribution
    Given "Meera" created the distribution "Tea Estates Exit"
    And "Ravi" approved the distribution "Tea Estates Exit"
    When "Anil" changes the income of the "₹0.72 Cr" payment of "Tea Estates Exit" to "₹0.75 Cr"
    Then "Anil" sees the flash "Its approval was withdrawn because the figures changed"
    And the distribution "Tea Estates Exit" is not approved
    And "Ravi" has the bell alert "Approval of Tea Estates Exit was withdrawn: Anil Rao changed its figures after approval."

  # H24 — Happy path: after H22, Priya (not a preparer) approves again → approved by Priya
  Scenario: H24 A checker re-approves after a withdrawal
    Given "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" approved the call "Q4 2026 Drawdown"
    And "Anil" changes the "₹1.2 Cr" remittance of "Q4 2026 Drawdown" to "₹1.25 Cr"
    When "Priya" approves the call "Q4 2026 Drawdown"
    Then the call "Q4 2026 Drawdown" is approved by "Priya"

  # E40 — Edge case: Ravi edits the notes of approved Q4 → stays approved; nothing sent
  Scenario: E40 A notes edit keeps the approval
    Given "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" approved the call "Q4 2026 Drawdown"
    When "Ravi" edits the notes of "Q4 2026 Drawdown"
    Then the call "Q4 2026 Drawdown" is approved by "Ravi"
    And no maker-checker email is sent

  # E41 — Edge case: a ₹1.8 Cr payment is recorded on approved Q4 → stays approved
  Scenario: E41 Recording a payment keeps the approval
    Given "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" approved the call "Q4 2026 Drawdown"
    When "Anil" records a payment of "₹1.8 Cr" on the "₹1.8 Cr" remittance of "Q4 2026 Drawdown"
    Then the call "Q4 2026 Drawdown" is approved by "Ravi"

  # E42 — Edge case: Ravi verifies a remittance of approved Q4 → stays approved
  Scenario: E42 Verifying a remittance keeps the approval
    Given "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" approved the call "Q4 2026 Drawdown"
    When "Ravi" verifies the "₹1.8 Cr" remittance of "Q4 2026 Drawdown"
    Then the call "Q4 2026 Drawdown" is approved by "Ravi"

  # E43 — Edge case: a ₹10 Cr commitment is added after approval; its ₹1 Cr remittance is created in Q4 → stays approved
  Scenario: E43 A late commitment keeps the approval
    Given "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" approved the call "Q4 2026 Drawdown"
    When "Anil" adds a "₹10 Cr" commitment for "Kabir Ventures" to the fund of "Nilgiri Capital"
    Then the call "Q4 2026 Drawdown" has a "₹1 Cr" remittance
    And the call "Q4 2026 Drawdown" is approved by "Ravi"
    And "Anil" is not a preparer of the call "Q4 2026 Drawdown"

  # E44 — Edge case: Solo Ventures (off), approved call; Sam changes its percentage → stays approved
  Scenario: E44 Setting off keeps today's behaviour
    Given "Sam" created the call "Solo Q4 Drawdown"
    And "Sam" approved the call "Solo Q4 Drawdown"
    When "Sam" changes the percentage of "Solo Q4 Drawdown" to 12%
    Then the call "Solo Q4 Drawdown" is approved by "Sam"
    And no maker-checker email is sent

  # E45 — Edge case: a job with no acting user changes a remittance of approved Q4 → stays approved; a warning is logged
  Scenario: E45 A change with nobody behind it keeps the approval
    Given "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" approved the call "Q4 2026 Drawdown"
    When a job with no acting user changes the "₹1.2 Cr" remittance of "Q4 2026 Drawdown" to "₹1.3 Cr"
    Then the call "Q4 2026 Drawdown" is approved by "Ravi"
    And a warning about an unattributed figure change is logged for "Q4 2026 Drawdown"

  # E46 — Edge case: Anil clicks Recompute Fees on approved Q4 and the fees change → withdrawn; Anil a preparer
  Scenario: E46 Recompute Fees that changes fees withdraws the approval
    Given "Meera" created the call "Q4 2026 Drawdown"
    And the call "Q4 2026 Drawdown" charges a management fee from account entries
    And "Ravi" approved the call "Q4 2026 Drawdown"
    And the management fee account entries of "Q4 2026 Drawdown" grow to ₹1,20,000 per folio
    When "Anil" clicks Recompute Fees on "Q4 2026 Drawdown"
    Then the call "Q4 2026 Drawdown" is not approved
    And "Anil" is a preparer of the call "Q4 2026 Drawdown"

  # E47 — Edge case: Recompute Fees leaves every fee the same → stays approved
  Scenario: E47 Recompute Fees with no change keeps the approval
    Given "Meera" created the call "Q4 2026 Drawdown"
    And the call "Q4 2026 Drawdown" charges a management fee from account entries
    And "Ravi" approved the call "Q4 2026 Drawdown"
    When "Anil" clicks Recompute Fees on "Q4 2026 Drawdown"
    Then the call "Q4 2026 Drawdown" is approved by "Ravi"

  # E48 — Edge case: Anil deletes the ₹1.2 Cr remittance of approved Q4 → withdrawn
  Scenario: E48 Deleting a remittance withdraws the approval
    Given "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" approved the call "Q4 2026 Drawdown"
    When "Anil" deletes the "₹1.2 Cr" remittance of "Q4 2026 Drawdown"
    Then the call "Q4 2026 Drawdown" is not approved

  # E49 — Edge case: Ravi deletes approved Q4 → deleted; no withdrawal alert
  Scenario: E49 Deleting the call sends no withdrawal alert
    Given "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" approved the call "Q4 2026 Drawdown"
    When "Ravi" deletes the call "Q4 2026 Drawdown"
    Then "Ravi" sees the flash "Capital call was successfully destroyed."
    And no maker-checker email is sent

  # E50 — Edge case: an open-ended settlement call; a subscription payment is added, then changed → stays approved
  Scenario: E50 Open-ended settlements are exempt
    Given the fund of "Nilgiri Capital" settles a dealing date
    And "Ravi" creates the subscription settlement
    When "Anil" adds and then changes a subscription payment on the settlement
    Then the settlement is approved with no preparer recorded
    And no maker-checker email is sent

  # E51 — Edge case: Q4 approved and its notices already sent; Anil changes a remittance → withdrawn; the alert says LPs aren't told
  Scenario: E51 The alert says investors already notified are not told
    Given "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" approved the call "Q4 2026 Drawdown"
    And the notices of "Q4 2026 Drawdown" were sent
    When "Anil" changes the "₹1.2 Cr" remittance of "Q4 2026 Drawdown" to "₹1.25 Cr"
    Then the call "Q4 2026 Drawdown" is not approved
    And the maker-checker email to "Ravi" says "Investors were already sent this call's notice; they are not told about the change."

  # E52 — Edge case: Q4 not approved; Anil changes a remittance → no withdrawal alert; Anil a preparer
  Scenario: E52 An unapproved call only records the preparer
    Given "Meera" created the call "Q4 2026 Drawdown"
    When "Anil" changes the "₹1.2 Cr" remittance of "Q4 2026 Drawdown" to "₹1.25 Cr"
    Then "Anil" sees the flash "Capital remittance was successfully updated."
    And "Anil" is a preparer of the call "Q4 2026 Drawdown"
    And no maker-checker email is sent

  # E53 — Edge case: Tea Estates approved; Anil changes the distribution date → withdrawn
  Scenario: E53 Changing the distribution date withdraws the approval
    Given "Meera" created the distribution "Tea Estates Exit"
    And "Ravi" approved the distribution "Tea Estates Exit"
    When "Anil" changes the distribution date of "Tea Estates Exit"
    Then "Anil" sees the flash "Capital distribution was successfully updated. Its approval was withdrawn because the figures changed — another approver must approve it again."
    And the distribution "Tea Estates Exit" is not approved

  # X16 — Error case (C-X16): Q4 approved but failing an unrelated validation; Anil changes a remittance → his change
  # saves and the approval is still withdrawn — figures and approval never disagree, and the unrelated problem doesn't
  # block him (design "Changed during the build")
  Scenario: X16 An unrelated validation problem on the call doesn't block the withdrawal
    Given "Meera" created the call "Q4 2026 Drawdown"
    And "Ravi" approved the call "Q4 2026 Drawdown"
    And the call "Q4 2026 Drawdown" fails an unrelated validation
    When "Anil" changes the "₹1.2 Cr" remittance of "Q4 2026 Drawdown" to "₹1.25 Cr"
    Then "Anil" sees the flash "Its approval was withdrawn because the figures changed"
    And the call "Q4 2026 Drawdown" is not approved
    And the call "Q4 2026 Drawdown" has a "₹1.25 Cr" remittance
