@maker_checker
Feature: Who is a preparer (OWASP review 2026-11 M13 — F2)
  Anyone who created, imported or changed the figures of a capital call or distribution — on the record itself or on
  its remittances, payments or fee lines — is recorded as a preparer, once per person. Names, notes, custom fields,
  notification switches, payments received and verification don't count. The person behind a change is the real
  human: CapHive support when acting as a user. A record's creator from the audit trail always counts.
  Worked examples H2–H11, E4–E14:
  openspec/changes/capital-call-distribution-maker-checker/business-rules.md#2-who-is-a-preparer--phase-1

  Background:
    Given the firm "Nilgiri Capital" has maker-checker on

  # H2 — Happy path: Meera creates Q4 2026 Drawdown on the form → she is its preparer
  Scenario: H2 The creator on the form is a preparer
    When "Meera" creates the call "Q4 2026 Drawdown" on the form
    Then the preparers of the call "Q4 2026 Drawdown" are "Meera Shah"
    And "Meera" is recorded as "created" on the call "Q4 2026 Drawdown"

  # H3 — Happy path: Meera creates the call through the JSON API with a bearer token → she is its preparer
  Scenario: H3 The creator through the API is a preparer
    When "Meera" creates the call "Q4 2026 Drawdown" through the API
    Then the preparers of the call "Q4 2026 Drawdown" are "Meera Shah"

  # H4 — Happy path: Anil changes the percentage called 10% → 12% → Meera and Anil
  Scenario: H4 The editor of the call's figures is a preparer
    Given "Meera" created the call "Q4 2026 Drawdown"
    When "Anil" changes the percentage of "Q4 2026 Drawdown" to 12%
    Then the preparers of the call "Q4 2026 Drawdown" are "Meera Shah, Anil Rao"
    And "Anil" is recorded as "edited" on the call "Q4 2026 Drawdown"

  # H5 — Happy path: Anil changes one remittance ₹1.2 Cr → ₹1.25 Cr → Meera and Anil
  Scenario: H5 The editor of a remittance amount is a preparer
    Given "Meera" created the call "Q4 2026 Drawdown"
    When "Anil" changes the "₹1.2 Cr" remittance of "Q4 2026 Drawdown" to "₹1.25 Cr"
    Then the preparers of the call "Q4 2026 Drawdown" are "Meera Shah, Anil Rao"

  # H6 — Happy path: Anil changes a distribution payment's income ₹0.72 Cr → ₹0.75 Cr → Meera and Anil
  Scenario: H6 The editor of a distribution payment is a preparer
    Given "Meera" created the distribution "Tea Estates Exit"
    When "Anil" changes the income of the "₹0.72 Cr" payment of "Tea Estates Exit" to "₹0.75 Cr"
    Then the preparers of the distribution "Tea Estates Exit" are "Meera Shah, Anil Rao"

  # H7 — Happy path: Anil imports a sheet with "Q1 2027 Drawdown" → the importer is its preparer
  Scenario: H7 The importer of a call is a preparer
    Given "Anil" imported the call "Q1 2027 Drawdown"
    Then the preparers of the call "Q1 2027 Drawdown" are "Anil Rao"
    And "Anil" is recorded as "imported" on the call "Q1 2027 Drawdown"

  # H8 — Happy path: Meera's upload-basis call; Anil imports 3 remittance rows → Meera and Anil
  Scenario: H8 The importer of remittances is a preparer
    Given "Meera" created the upload-basis call "Sep 2026 Top-up"
    And "Anil" imported 3 remittances into "Sep 2026 Top-up"
    Then the preparers of the call "Sep 2026 Top-up" are "Meera Shah, Anil Rao"
    And "Anil" is recorded as "imported" on the call "Sep 2026 Top-up"

  # H9 — Happy path: Anil clicks Recompute Fees and the fees change (₹1,00,000 → ₹1,20,000 a folio) → Anil is a preparer
  Scenario: H9 Recompute Fees that changes the fees makes a preparer
    Given "Meera" created the call "Q4 2026 Drawdown"
    And the call "Q4 2026 Drawdown" charges a management fee from account entries
    And the management fee account entries of "Q4 2026 Drawdown" grow to ₹1,20,000 per folio
    When "Anil" clicks Recompute Fees on "Q4 2026 Drawdown"
    Then "Anil" is a preparer of the call "Q4 2026 Drawdown"

  # H10 — Happy path: Anil changes the call fee line's end date → Anil is a preparer
  Scenario: H10 The editor of a fee line is a preparer
    Given "Meera" created the call "Q4 2026 Drawdown"
    And the call "Q4 2026 Drawdown" charges a management fee from account entries
    When "Anil" changes the end date of the fee line of "Q4 2026 Drawdown"
    Then "Anil" is a preparer of the call "Q4 2026 Drawdown"

  # H11 — Happy path: Meera creates Tea Estates Exit on the form → she is its preparer
  Scenario: H11 The creator of a distribution is a preparer
    When "Meera" creates the distribution "Tea Estates Exit" on the form
    Then the preparers of the distribution "Tea Estates Exit" are "Meera Shah"

  # E4 — Edge case: Ravi edits the call's name and notes → not figures, Ravi is not a preparer
  Scenario: E4 Editing the name and notes does not make a preparer
    Given "Meera" created the call "Q4 2026 Drawdown"
    When "Ravi" edits the name and notes of "Q4 2026 Drawdown"
    Then "Ravi" is not a preparer of the call "Q4 2026 Drawdown"

  # E5 — Edge case: Ravi changes a custom field and the Send Call Notice switch → not figures
  Scenario: E5 Custom fields and notification switches do not make a preparer
    Given "Meera" created the call "Q4 2026 Drawdown"
    When "Ravi" changes the custom fields and the Send Call Notice switch of "Q4 2026 Drawdown"
    Then "Ravi" is not a preparer of the call "Q4 2026 Drawdown"

  # E6 — Edge case: Ravi records a ₹1.8 Cr payment received → money in, not figures
  Scenario: E6 Recording a payment does not make a preparer
    Given "Meera" created the call "Q4 2026 Drawdown"
    When "Ravi" records a payment of "₹1.8 Cr" on the "₹1.8 Cr" remittance of "Q4 2026 Drawdown"
    Then "Ravi" is not a preparer of the call "Q4 2026 Drawdown"

  # E7 — Edge case: Ravi verifies a remittance → not figures
  Scenario: E7 Verifying a remittance does not make a preparer
    Given "Meera" created the call "Q4 2026 Drawdown"
    When "Ravi" verifies the "₹1.8 Cr" remittance of "Q4 2026 Drawdown"
    Then "Ravi" is not a preparer of the call "Q4 2026 Drawdown"

  # E8 — Edge case: creating the call generates 3 remittances under Meera → exactly one preparer row
  Scenario: E8 Generating many remittances records the person once
    Given "Meera" created the call "Q4 2026 Drawdown"
    Then the call "Q4 2026 Drawdown" has 1 preparer row
    And the preparers of the call "Q4 2026 Drawdown" are "Meera Shah"

  # E9 — Edge case: Anil edits two remittances in two requests → still one row for Anil
  Scenario: E9 The same person twice is one row
    Given "Meera" created the call "Q4 2026 Drawdown"
    When "Anil" changes the "₹1.2 Cr" remittance of "Q4 2026 Drawdown" to "₹1.25 Cr"
    And "Anil" changes the "₹1.8 Cr" remittance of "Q4 2026 Drawdown" to "₹1.85 Cr"
    Then the call "Q4 2026 Drawdown" has 2 preparer rows
    And the preparers of the call "Q4 2026 Drawdown" are "Meera Shah, Anil Rao"

  # E10 — Edge case: a job with no acting user changes a remittance amount → no row is added
  Scenario: E10 No acting person records nobody
    Given "Meera" created the call "Q4 2026 Drawdown"
    When a job with no acting user changes the "₹1.2 Cr" remittance of "Q4 2026 Drawdown" to "₹1.3 Cr"
    Then the call "Q4 2026 Drawdown" has 1 preparer row
    And the preparers of the call "Q4 2026 Drawdown" are "Meera Shah"

  # E11 — Edge case: Sunil (CapHive support), acting as Meera, creates a call → Sunil, the real person, is the preparer
  Scenario: E11 Support acting as a user is recorded as themselves
    Given CapHive support "Sunil" supports "Nilgiri Capital"
    When CapHive support "Sunil" acting as "Meera" creates the call "Support Drawdown"
    Then the preparers of the call "Support Drawdown" are "Sunil Menon"
    And "Meera" is not a preparer of the call "Support Drawdown"

  # E12 — Edge case: a call created before release by Meera, with no log row → Meera from the audit trail
  Scenario: E12 A legacy call counts its creator from the audit trail
    Given "Meera" created the call "Q3 2026 Drawdown" before maker-checker existed
    Then the call "Q3 2026 Drawdown" has 0 preparer rows
    And the preparers of the call "Q3 2026 Drawdown" are "Meera Shah"

  # E13 — Edge case: the legacy call, then Anil changes a remittance → Meera (audit) and Anil (log)
  Scenario: E13 A legacy call edited after release keeps its creator
    Given "Meera" created the call "Q3 2026 Drawdown" before maker-checker existed
    When "Anil" changes the "₹1.2 Cr" remittance of "Q3 2026 Drawdown" to "₹1.25 Cr"
    Then the preparers of the call "Q3 2026 Drawdown" are "Meera Shah, Anil Rao"

  # E14 — Edge case: Anil saves a remittance form without changing the amount → not a preparer
  Scenario: E14 Saving without a real change does not make a preparer
    Given "Meera" created the call "Q4 2026 Drawdown"
    When "Anil" saves the "₹1.2 Cr" remittance of "Q4 2026 Drawdown" without changes
    Then "Anil" is not a preparer of the call "Q4 2026 Drawdown"
