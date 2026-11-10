@bank_detail_change
Feature: A bank detail change clears Bank Verified in the same save (OWASP review 2026-11 M14 — §1)
  A change of a KYC's account number or IFSC switches Bank Verified off and clears the stored bank check in that
  same save, on every way a KYC is saved (form, JSON API, import, Compare CKYC/KRA, Document Checks, AI extraction),
  whatever value of Bank Verified was sent. A change on a verified KYC also unverifies it. Bank name, branch, account
  type and full name do not count; neither does the same value re-typed.
  Worked examples H1–H3, E1–E10, X1:
  openspec/changes/archive/2026-11-10-bank-detail-change-controls/business-rules.md#1-clear-on-change--phase-1

  # H1 — Happy path: Meera changes Anil's account (checks off) → Bank Verified off straight after the save
  Scenario: H1 Account change clears Bank Verified
    Given the KYC "Anil Kumar" is unverified
    When "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    Then the KYC "Anil Kumar" has Bank Verified off
    And the KYC "Anil Kumar" has no bank check result
    And the KYC "Anil Kumar" has "account" "50100273107310"

  # H2 — Happy path: Meera changes the IFSC only → Bank Verified off
  Scenario: H2 IFSC change clears Bank Verified
    Given the KYC "Anil Kumar" is unverified
    When "Meera" saves the KYC "Anil Kumar" with:
      | IFSC | ICIC0004567 |
    Then the KYC "Anil Kumar" has Bank Verified off

  # H3 — Happy path: Kestrel (checks on) — off right after Dev's save; ✓ again after the (stubbed) check runs
  Scenario: H3 Checks on: cleared, then re-checked by the bank check
    Given the KYC "A Kumar" is unverified
    And the bank check returns "A KUMAR" with a provider match
    And the bank check is held until it is run
    When "Dev" saves the KYC "A Kumar" with:
      | account | 60200099990000 |
    Then the KYC "A Kumar" has Bank Verified off
    When the held bank check runs
    Then the KYC "A Kumar" has Bank Verified on

  # E1 — Edge case: Ravi changes the account and leaves the ticked Bank Verified box ticked → off
  Scenario: E1 The form still sends the old tick
    Given the KYC "Anil Kumar" is unverified
    When "Ravi" saves the KYC "Anil Kumar" with:
      | account       | 50100273107310 |
      | Bank Verified | 1              |
    Then the KYC "Anil Kumar" has Bank Verified off

  # E2 — Edge case: branch "MG Road" → "Indiranagar" and account type → Current only → Bank Verified unchanged
  Scenario: E2 Branch and account type only
    Given the KYC "Anil Kumar" is unverified
    When "Meera" saves the KYC "Anil Kumar" with:
      | branch       | Indiranagar     |
      | account type | Current Account |
    Then the KYC "Anil Kumar" has Bank Verified on
    And the KYC "Anil Kumar" has "branch" "Indiranagar"

  # E3 — Edge case: the same IFSC re-typed "hdfc0001234 " → Bank Verified unchanged
  Scenario: E3 The same IFSC re-typed
    Given the KYC "Anil Kumar" is unverified
    And the bank check of "Anil Kumar" last said "Verified by an approver"
    When "Meera" saves the KYC "Anil Kumar" with:
      | IFSC | hdfc0001234  |
    Then the KYC "Anil Kumar" has Bank Verified on
    And the KYC "Anil Kumar" keeps its bank check status "Verified by an approver"

  # E4 — Edge case: full name only, checks off → Bank Verified unchanged
  Scenario: E4 Full name only
    Given the KYC "Anil Kumar" is unverified
    When "Meera" saves the KYC "Anil Kumar" with:
      | full name | Anil K Kumar |
    Then the KYC "Anil Kumar" has Bank Verified on

  # E5 — Edge case: Document Checks read 50100273107310 from the cheque; Meera clicks "Use document value" → off
  Scenario: E5 Document Checks fill-in
    Given the KYC "Anil Kumar" is unverified
    When "Meera" uses the document value "50100273107310" for "account" on the KYC "Anil Kumar"
    Then the KYC "Anil Kumar" has "account" "50100273107310"
    And the KYC "Anil Kumar" has Bank Verified off

  # E6 — Edge case: the AI extractor ("always overwrite", a bank rule) writes 50100273107310 → off
  Scenario: E6 AI extraction overwrites the account
    Given the KYC "Anil Kumar" is unverified
    When the AI extraction writes "50100273107310" to "account" on the KYC "Anil Kumar" as "Meera"
    Then the KYC "Anil Kumar" has "account" "50100273107310"
    And the KYC "Anil Kumar" has Bank Verified off

  # E7 — Edge case: Ravi's API token, PATCH /investor_kycs/:id.json with a new account → 200; off
  Scenario: E7 JSON API update
    Given the KYC "Anil Kumar" is unverified
    When "Ravi" sends the KYC "Anil Kumar" over the API with:
      | account | 50100273107310 |
    Then the KYC API answers 200
    And the KYC "Anil Kumar" has Bank Verified off

  # E8 — Edge case: Meera imports an Update Only row with the new account, Verified blank → "Success"; off
  Scenario: E8 Import Update Only with Verified blank
    Given the KYC "Anil Kumar" is unverified
    When "Meera" imports an Update Only row for the KYC "Anil Kumar" with:
      | Bank Account Number | 50100273107310 |
    Then the import row says "Success"
    And the KYC "Anil Kumar" has "account" "50100273107310"
    And the KYC "Anil Kumar" has Bank Verified off

  # E9 — Edge case: Anil's KYC is verified; Meera saves the Compare CKYC/KRA form with a new account → unverified, off
  Scenario: E9 Compare CKYC/KRA save on a verified KYC
    Given the KYC "Anil Kumar" is already verified
    When "Meera" saves the Compare CKYC/KRA form of the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    Then the KYC "Anil Kumar" has "account" "50100273107310"
    And the KYC "Anil Kumar" is not verified
    And the KYC "Anil Kumar" has Bank Verified off

  # E10 — Edge case: verified KYC with a journey; Meera imports IFSC ICIC0004567, Verified blank → unverified,
  # journey back at Verify KYC with the note "Bank details changed"
  Scenario: E10 Import changes the IFSC of a verified KYC with a journey
    Given the investor KYC journey of the KYC "Anil Kumar" has reached Verify KYC
    And "Ravi" verifies the KYC "Anil Kumar" from its page
    When "Meera" imports an Update Only row for the KYC "Anil Kumar" with:
      | Ifsc Code | ICIC0004567 |
    Then the import row says "Success"
    And the KYC "Anil Kumar" is not verified
    And the KYC "Anil Kumar" has Bank Verified off
    And the KYC's journey should have moved back to "Verify KYC" with "Bank details changed"

  # X1 — Error case: a new account with a 21-character IFSC → "Ifsc code is too long"; nothing changed
  Scenario: X1 A save that fails validation changes nothing
    Given the KYC "Anil Kumar" is unverified
    When "Meera" saves the KYC "Anil Kumar" with validation and:
      | account | 50100273107310        |
      | IFSC    | ICIC00045670000000000 |
    Then the save is refused with the form error "Ifsc code is too long"
    And the KYC "Anil Kumar" has Bank Verified on
    And the KYC "Anil Kumar" has "account" "50100012344821"
