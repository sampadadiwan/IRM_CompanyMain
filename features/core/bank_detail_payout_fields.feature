@bank_detail_change
Feature: Payout custom fields (SWIFT / IBAN) follow the bank change rules (OWASP review 2026-11 M14 — §8)
  A firm marks text custom fields on its KYC forms as payout fields: a bank code (shown in full, like the IFSC — SWIFT,
  routing number) or an account identifier (last 4 only, like the account number — IBAN). A change to a marked field
  follows every bank change rule: Bank Verified clears, a verified KYC is unverified, the change is recorded and
  emailed, a second person verifies, imports warn, payouts flag it. Unmarked fields are ignored. Marking changes no
  KYC. Only CapHive support unmarks. A support rake task proposes marks for existing fields.
  Horizon's Individual KYC form has SWIFT Code, IBAN, Intermediary Bank Name (text) and Foreign account? (check box);
  its Non-Individual form has SWIFT Code. Farah Ali (Individual) holds SWIFT EBILAEADXXX and IBAN ending 3456.
  Worked examples H18–H21, E63–E80:
  openspec/changes/bank-detail-change-controls/business-rules.md#8-payout-custom-fields-swift--iban--phase-6

  Background:
    Given Horizon Capital's KYC forms have the SWIFT and IBAN custom fields

  # H18 — Happy path: Ravi opens Farah's custom fields side panel, sets SWIFT Code → Bank code and IBAN → Account
  # identifier, Save → saved; both rows show the payout icon; Form Types › Edit shows the same; Farah unchanged; no email
  Scenario: H18 A company admin marks SWIFT and IBAN in the side panel
    Given the KYC "Farah Ali" is already verified
    When "Ravi" opens the custom fields side panel of the KYC "Farah Ali"
    Then the side panel row "SWIFT Code" offers the payout field choice "Payout field: a change needs a second approver"
    And the side panel row "Foreign account?" offers no payout field choice
    When "Ravi" saves the custom fields side panel of the KYC "Farah Ali" with:
      | SWIFT Code | Bank code          |
      | IBAN       | Account identifier |
    Then the side panel says "Individual kyc fields saved"
    And "SWIFT Code" on the Individual KYC form is a payout field of kind "code"
    And "IBAN" on the Individual KYC form is a payout field of kind "account"
    When "Ravi" opens the custom fields side panel of the KYC "Farah Ali"
    Then the side panel row "SWIFT Code" shows the payout icon
    When "Ravi" opens Form Types › Edit of the Individual KYC form
    Then the field "SWIFT Code" has the payout field choice "Bank code (shown in full)" selected
    And the KYC "Farah Ali" is verified
    And no bank change email was sent

  # H19 — Happy path: SWIFT marked; Farah unverified; Meera changes SWIFT EBILAEADXXX → NBADAEAAXXX → off; recorded; note
  Scenario: H19 A SWIFT change is a bank change
    Given "SWIFT Code" is marked as a bank code on the Individual KYC form
    And the KYC "Farah Ali" is unverified
    When "Meera" saves the KYC "Farah Ali" with:
      | SWIFT Code | NBADAEAAXXX |
    Then the KYC "Farah Ali" has Bank Verified off
    And the latest bank change of the KYC "Farah Ali" is:
      | status        | awaiting                               |
      | maker         | Meera Shah                             |
      | source        | screen                                 |
      | custom fields | SWIFT Code EBILAEADXXX → NBADAEAAXXX   |
    When "Ravi" opens the KYC "Farah Ali"
    Then the bank change note says "Bank details changed on 09/11/2026 by Meera Shah — SWIFT Code EBILAEADXXX → NBADAEAAXXX. Waiting for a second approver to verify."

  # H20 — Happy path: IBAN marked; Meera changes IBAN → farah.ali@example.ae gets "IBAN ending 3456 → ending 8901"
  # (no full IBAN); Ravi gets the approver email; Meera nothing
  Scenario: H20 The emails name the field, the IBAN masked
    Given "IBAN" is marked as an account identifier on the Individual KYC form
    And the KYC "Farah Ali" is unverified
    When "Meera" saves the KYC "Farah Ali" with:
      | IBAN | AE460260001015333438901 |
    Then "farah.ali@example.ae" receives 1 email "Your bank details with Horizon Capital were changed"
    And that email says "IBAN ending 3456 → ending 8901"
    And that email does not say "AE460260001015333438901"
    And that email does not say "AE070331234567890123456"
    And "Ravi" receives 1 email "Bank details changed for Farah Ali — a second approver must verify"
    And that email says "IBAN ending 3456 → ending 8901"
    And "Meera" receives no bank change email

  # H21 — Happy path: after H19 Meera's Verify is greyed; Ravi's popup card names the SWIFT; verified; confirmed
  Scenario: H21 A second approver confirms a SWIFT change
    Given "SWIFT Code" is marked as a bank code on the Individual KYC form
    And the KYC "Farah Ali" is unverified
    And "Meera" saves the KYC "Farah Ali" with:
      | SWIFT Code | NBADAEAAXXX |
    When "Meera" opens the KYC "Farah Ali"
    Then the page shows Verify greyed out saying "You changed this KYC's bank details. Another KYC approver must verify it."
    Given the next day comes
    When "Ravi" opens the KYC "Farah Ali"
    Then the Verify popup shows the card "New payout account confirmed" saying "SWIFT Code NBADAEAAXXX"
    When "Ravi" confirms the Verify popup of the KYC "Farah Ali"
    Then the KYC "Farah Ali" is verified
    And the bank change note says "Confirmed by Ravi Iyer on 10/11/2026"

  # E63 — Edge case: SWIFT marked; Farah verified; Meera imports Update Only SWIFT NBADAEAAXXX, Verified Yes → warning;
  # unverified; source import; emails
  Scenario: E63 An import changes the SWIFT of a verified KYC
    Given "SWIFT Code" is marked as a bank code on the Individual KYC form
    And the KYC "Farah Ali" is already verified
    When "Meera" imports an Update Only row for the KYC "Farah Ali" with:
      | SWIFT Code | NBADAEAAXXX |
      | Verified   | Yes         |
    Then the import row says "Success with warnings" with "Bank details changed — the KYC was left unverified for another approver to verify"
    And the KYC "Farah Ali" is not verified
    And the latest bank change of the KYC "Farah Ali" is:
      | status | awaiting |
      | source | import   |
    And "farah.ali@example.ae" receives 1 email "Your bank details with Horizon Capital were changed"

  # E64 — Edge case: SWIFT and IBAN marked; Meera changes the unmarked Intermediary Bank Name → nothing new
  Scenario: E64 An unmarked custom field is ignored
    Given "SWIFT Code" is marked as a bank code on the Individual KYC form
    And "IBAN" is marked as an account identifier on the Individual KYC form
    And the KYC "Farah Ali" is unverified
    When "Meera" saves the KYC "Farah Ali" with:
      | Intermediary Bank Name | Citibank New York |
    Then the KYC "Farah Ali" has Bank Verified on
    And the KYC "Farah Ali" has no bank change
    And no bank change email was sent
    And the audit trail of the KYC "Farah Ali" records "Citibank New York" in "json_fields"

  # E65 — Edge case: SWIFT unmarked; Farah verified with Bank Verified ✓; Ravi marks SWIFT → Farah unchanged; nothing sent
  Scenario: E65 Marking does not unverify anyone
    Given the KYC "Farah Ali" is already verified
    When "Ravi" saves the custom fields side panel of the KYC "Farah Ali" with:
      | SWIFT Code | Bank code |
    Then the KYC "Farah Ali" is verified
    And the KYC "Farah Ali" has Bank Verified on
    And the KYC "Farah Ali" has no bank change
    And no bank change email was sent

  # E66 — Edge case: SWIFT unmarked; Meera changed Farah's SWIFT on 08/11/2026; Ravi marks SWIFT on 09/11 → no note, no
  # record for the earlier edit; the audit trail shows it
  Scenario: E66 A change made before marking is not recorded later
    Given the KYC "Farah Ali" is unverified
    And on 08/11/2026 "Meera" saved the KYC "Farah Ali" with SWIFT Code "NBADAEAAXXX"
    When "Ravi" saves the custom fields side panel of the KYC "Farah Ali" with:
      | SWIFT Code | Bank code |
    And "Ravi" opens the KYC "Farah Ali"
    Then the KYC page has no bank change note
    And the KYC "Farah Ali" has no bank change
    And the audit trail of the KYC "Farah Ali" records "NBADAEAAXXX" in "json_fields"

  # E67 — Edge case: SWIFT marked on the Individual form only; Meera changes Gulf Ventures LLC's (Non-Individual) SWIFT
  Scenario: E67 A mark applies to its own form only
    Given "SWIFT Code" is marked as a bank code on the Individual KYC form
    And the KYC "Gulf Ventures LLC" is unverified
    When "Meera" saves the KYC "Gulf Ventures LLC" with:
      | SWIFT Code | ADCBAEAAXXX |
    Then the KYC "Gulf Ventures LLC" has no bank change
    And no bank change email was sent

  # E68 — Edge case: IBAN marked; Farah's IBAN blank, Bank Verified ✓; Farah fills it through her link → no record, no
  # email (a first fill); Bank Verified off
  Scenario: E68 The first fill of a marked field
    Given "IBAN" is marked as an account identifier on the Individual KYC form
    And the KYC "Farah Ali" was sent to the investor
    And the KYC "Farah Ali" has a blank "IBAN"
    When the investor "farah.ali@example.ae" submits the KYC "Farah Ali" through the emailed link with:
      | IBAN | AE460260001015333438901 |
    Then the KYC "Farah Ali" has Bank Verified off
    And the KYC "Farah Ali" has no bank change
    And no bank change email was sent

  # E69 — Edge case: IBAN marked; Meera blanks it → "IBAN ending 3456 → none"; both emails
  Scenario: E69 A marked value cleared
    Given "IBAN" is marked as an account identifier on the Individual KYC form
    And the KYC "Farah Ali" is unverified
    When "Meera" saves the KYC "Farah Ali" with:
      | IBAN | (blank) |
    Then the latest bank change of the KYC "Farah Ali" is:
      | custom fields | IBAN ending 3456 → none |
    And "farah.ali@example.ae" receives 1 email "Your bank details with Horizon Capital were changed"
    And "Ravi" receives 1 email "Bank details changed for Farah Ali — a second approver must verify"

  # E70 — Edge case: SWIFT marked; Meera saves "ebilaead xxx" (the same SWIFT re-typed) → no record; ✓ unchanged
  Scenario: E70 The same SWIFT re-typed
    Given "SWIFT Code" is marked as a bank code on the Individual KYC form
    And the KYC "Farah Ali" is unverified
    When "Meera" saves the KYC "Farah Ali" with:
      | SWIFT Code | ebilaead xxx |
    Then the KYC "Farah Ali" has no bank change
    And the KYC "Farah Ali" has Bank Verified on

  # E71 — Edge case: SWIFT marked; Meera changes the account to …7788 and the SWIFT in one save → one record listing
  # both; one investor email, one approver email
  Scenario: E71 Account and SWIFT in one save make one change
    Given "SWIFT Code" is marked as a bank code on the Individual KYC form
    And the KYC "Farah Ali" is unverified
    When "Meera" saves the KYC "Farah Ali" with:
      | account    | 50100099007788 |
      | SWIFT Code | NBADAEAAXXX    |
    Then the KYC "Farah Ali" has 1 bank changes, the first "awaiting"
    And the latest bank change of the KYC "Farah Ali" is:
      | account       | 1122 → 7788                          |
      | custom fields | SWIFT Code EBILAEADXXX → NBADAEAAXXX |
    And "farah.ali@example.ae" receives 1 email "Your bank details with Horizon Capital were changed"
    And that email says "SWIFT Code EBILAEADXXX → NBADAEAAXXX"
    And "Ravi" receives 1 email "Bank details changed for Farah Ali — a second approver must verify"

  # E72 — Edge case: SWIFT marked; the AI extractor ("always overwrite") writes NBADAEAAXXX → source ai_extraction; off
  Scenario: E72 AI extraction writes a marked field
    Given "SWIFT Code" is marked as a bank code on the Individual KYC form
    And the KYC "Farah Ali" is unverified
    When the AI extraction writes "NBADAEAAXXX" to "SWIFT Code" on the KYC "Farah Ali" as "Meera"
    Then the KYC "Farah Ali" has Bank Verified off
    And the latest bank change of the KYC "Farah Ali" is:
      | source        | ai_extraction                        |
      | custom fields | SWIFT Code EBILAEADXXX → NBADAEAAXXX |

  # E73 — Edge case: IBAN marked; Document Checks read the IBAN from a bank letter; Meera uses the document value →
  # source document_checks; off
  Scenario: E73 Document Checks write a marked field
    Given "IBAN" is marked as an account identifier on the Individual KYC form
    And the KYC "Farah Ali" is unverified
    When "Meera" uses the document value "AE460260001015333438901" for "IBAN" on the KYC "Farah Ali"
    Then the KYC "Farah Ali" has Bank Verified off
    And the latest bank change of the KYC "Farah Ali" is:
      | source        | document_checks         |
      | custom fields | IBAN ending 3456 → ending 8901 |

  # E74 — Edge case: Kestrel (checks on); "A Kumar" unverified, Bank Verified ✓; Dev changes only the SWIFT → off; no
  # bank check runs; Asha ticks Bank Verified after proof; Dev cannot
  Scenario: E74 With checks on, a SWIFT-only change runs no bank check
    Given Kestrel Capital's Individual KYC form has "SWIFT Code" marked as a bank code
    And the KYC "A Kumar" is unverified
    And the KYC "A Kumar" holds the SWIFT Code "SBININBBXXX"
    And the bank check must not be called
    When "Dev" saves the KYC "A Kumar" with:
      | SWIFT Code | HDFCINBBXXX |
    Then the KYC "A Kumar" has Bank Verified off
    When "Dev" opens the edit page of the KYC "A Kumar"
    Then the edit page has no Bank Verified box
    When "Asha" saves the KYC "A Kumar" with:
      | Bank Verified | 1 |
    Then the KYC "A Kumar" has Bank Verified on

  # E75 — Edge case: Solo Advisors; Kiran changes Leela's SWIFT after UnVerify, clicks Verify → only-approver card;
  # confirm → verified, recorded "only approver"; Leela's contact emailed
  Scenario: E75 The only approver and a SWIFT change
    Given Solo Advisors' Individual KYC form has "SWIFT Code" marked as a bank code
    And the KYC "Leela Menon" holds the SWIFT Code "UTIBINBBXXX"
    And the KYC "Leela Menon" is unverified
    And "Kiran" saves the KYC "Leela Menon" with:
      | SWIFT Code | ICICINBBXXX |
    When "Kiran" opens the KYC "Leela Menon"
    Then the Verify popup shows the card "You are the only KYC approver" saying "You are the only KYC approver at Solo Advisors"
    When "Kiran" confirms the Verify popup of the KYC "Leela Menon"
    Then the KYC "Leela Menon" is verified
    And the latest bank change of the KYC "Leela Menon" is:
      | only approver | yes |
    And "leela.menon@example.in" receives 1 email "Your bank details with Solo Advisors were changed"

  # E76 — Edge case: after H19, Q3 2026 Distribution pays Farah, not emailed → panel warns; download column has the date
  Scenario: E76 The payout flags see a SWIFT change
    Given Horizon Capital's "Q3 2026 Distribution" of "Horizon Fund I" pays "Farah Ali" and "Bina Shah"
    And "SWIFT Code" is marked as a bank code on the Individual KYC form
    And the KYC "Farah Ali" is unverified
    And "Meera" saves the KYC "Farah Ali" with:
      | SWIFT Code | NBADAEAAXXX |
    When "Ravi" opens the distribution page of "Q3 2026 Distribution"
    Then the journey panel warns "1 KYC has bank details changed and not yet confirmed by a second approver"
    When "Meera" downloads the payments of "Q3 2026 Distribution"
    Then the payments download shows "2026-11-09" for "Farah Ali" and nothing for "Bina Shah"

  # E77 — Edge case: after H18 Sam (support) sets IBAN → No → unmarked; a later IBAN change makes no record
  Scenario: E77 CapHive support unmarks
    Given "IBAN" is marked as an account identifier on the Individual KYC form
    When CapHive support "Sam" saves the custom fields side panel of the KYC "Farah Ali" as "Ravi" with:
      | IBAN | No |
    Then "IBAN" on the Individual KYC form is not a payout field
    Given the KYC "Farah Ali" is unverified
    When "Meera" saves the KYC "Farah Ali" with:
      | IBAN | AE460260001015333438901 |
    Then the KYC "Farah Ali" has no bank change

  # E78 — Edge case: support runs the proposal dry run for Horizon → SWIFT Code → bank code, IBAN → account identifier
  # with filled-value counts; the check box not listed; nothing saved
  Scenario: E78 The rollout proposal dry run marks nothing
    When CapHive support runs the payout field proposal for "Horizon Capital"
    Then the proposal lists "SWIFT Code" on the "IndividualKyc" form as "code" with 1 filled value
    And the proposal lists "IBAN" on the "IndividualKyc" form as "account" with 1 filled value
    And the proposal lists "SWIFT Code" on the "NonIndividualKyc" form as "code" with 1 filled value
    And the proposal does not list "Foreign account?"
    And the proposal does not list "Intermediary Bank Name"
    And the proposal says "Dry run: nothing was saved"
    And "SWIFT Code" on the Individual KYC form is not a payout field

  # E79 — Edge case: after the admin agreed, the same command with EXECUTE=1 → listed fields marked; no KYC changed; no email
  Scenario: E79 The rollout proposal with EXECUTE=1 marks the fields
    Given the KYC "Farah Ali" is already verified
    When CapHive support runs the payout field proposal for "Horizon Capital" with EXECUTE=1
    Then "SWIFT Code" on the Individual KYC form is a payout field of kind "code"
    And "IBAN" on the Individual KYC form is a payout field of kind "account"
    And "SWIFT Code" on the Non-Individual KYC form is a payout field of kind "code"
    And the KYC "Farah Ali" is verified
    And the KYC "Farah Ali" has no bank change
    And no bank change email was sent

  # E80 — Edge case: after H18 Ravi sets SWIFT Code's max length to 11 in Form Types › Edit → still marked; then Meera's
  # SWIFT change is recorded
  Scenario: E80 Editing a marked field's rules keeps the mark
    Given "SWIFT Code" is marked as a bank code on the Individual KYC form
    When "Ravi" sets the max length of "SWIFT Code" to 11 in Form Types › Edit of the Individual KYC form
    Then "SWIFT Code" on the Individual KYC form is a payout field of kind "code"
    And "SWIFT Code" on the Individual KYC form has the max length 11
    Given the KYC "Farah Ali" is unverified
    When "Meera" saves the KYC "Farah Ali" with:
      | SWIFT Code | NBADAEAAXXX |
    Then the latest bank change of the KYC "Farah Ali" is:
      | custom fields | SWIFT Code EBILAEADXXX → NBADAEAAXXX |
