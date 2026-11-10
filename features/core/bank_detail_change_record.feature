@bank_detail_change
Feature: Every bank change is recorded and shown on the KYC page (OWASP review 2026-11 M14 — §3)
  A save that changes a KYC's account number or IFSC from a non-blank value is a bank change. It is recorded with
  who made it (a firm user, an investor or System), how (screen, API, import, Document Checks, AI extraction),
  the last 4 digits of the old and new accounts and both IFSCs, and its state: awaiting a second person, confirmed
  or replaced. Fund users see the latest one as a note in Contact & Banking; investors never see it. Full account
  numbers are never stored in the record.
  Worked examples H5, H6, E14–E23, X5:
  openspec/changes/bank-detail-change-controls/business-rules.md#3-change-record-and-kyc-page--phase-2

  # H5 — Happy path: Meera changes account + IFSC → record (Meera, fund, screen, 4821 → 7310, both IFSCs, awaiting)
  # and the amber note in Contact & Banking
  Scenario: H5 A fund user's change is recorded and noted on the KYC page
    Given the KYC "Anil Kumar" is unverified
    When "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
      | IFSC    | ICIC0004567    |
    Then the latest bank change of the KYC "Anil Kumar" is:
      | status  | awaiting                  |
      | maker   | Meera Shah                |
      | side    | fund                      |
      | source  | screen                    |
      | account | 4821 → 7310               |
      | IFSC    | HDFC0001234 → ICIC0004567 |
    When "Ravi" opens the KYC "Anil Kumar"
    Then the bank change note says "Bank details changed on 09/11/2026 by Meera Shah — account ending 4821 → 7310"
    And the bank change note says "Waiting for a second approver to verify."
    And the bank change note says "Investor contacts emailed: anil.kumar@example.in"
    And the bank change note explains "Payouts should wait until a KYC approver other than Meera Shah verifies this KYC"

  # H6 — Happy path: Anil (magic link) changes his account and submits → record by Anil Kumar (investor), awaiting
  Scenario: H6 An investor's own change is recorded
    Given the KYC "Anil Kumar" was sent to the investor
    When the investor "anil.kumar@example.in" submits the KYC "Anil Kumar" through the emailed link with:
      | account | 50100273107310 |
    Then the latest bank change of the KYC "Anil Kumar" is:
      | status | awaiting    |
      | maker  | Anil Kumar  |
      | side   | investor    |
      | source | screen      |

  # E14 — Edge case: Chetan's bank details were blank; his contact fills account and IFSC → no record, no note
  Scenario: E14 A first fill is not a change
    Given the KYC "Chetan Rao" was sent to the investor
    When the investor "chetan.rao@example.in" submits the KYC "Chetan Rao" through the emailed link with:
      | account | 30200011112222 |
      | IFSC    | KKBK0000123    |
    Then the KYC "Chetan Rao" has "account" "30200011112222"
    And the KYC "Chetan Rao" has no bank change
    When "Ravi" opens the KYC "Chetan Rao"
    Then the KYC page has no bank change note

  # E15 — Edge case: after H5, Meera changes the account again to …9902 → the first is replaced, 7310 → 9902 awaits
  Scenario: E15 A second change before verify replaces the first
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    When "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273109902 |
    Then the KYC "Anil Kumar" has 2 bank changes, the first "replaced"
    And the latest bank change of the KYC "Anil Kumar" is:
      | status  | awaiting    |
      | account | 7310 → 9902 |
    When "Ravi" opens the KYC "Anil Kumar"
    Then the bank change note says "account ending 7310 → 9902"

  # E16 — Edge case: Meera blanks the account number → "ending 4821 → none"
  Scenario: E16 The account cleared
    Given the KYC "Anil Kumar" is unverified
    When "Meera" saves the KYC "Anil Kumar" with:
      | account | (blank) |
    Then the latest bank change of the KYC "Anil Kumar" is:
      | account | 4821 → none |
    When "Ravi" opens the KYC "Anil Kumar"
    Then the bank change note says "account ending 4821 → none"

  # E17 — Edge case: Meera imports an Update Only row with a new account → source import, maker Meera
  Scenario: E17 An import is recorded as made by the importer
    Given the KYC "Anil Kumar" is unverified
    When "Meera" imports an Update Only row for the KYC "Anil Kumar" with:
      | Bank Account Number | 50100273107310 |
    Then the latest bank change of the KYC "Anil Kumar" is:
      | status | awaiting   |
      | maker  | Meera Shah |
      | source | import     |

  # E18 — Edge case: the AI extraction job with no acting user writes a new account → maker "System"
  Scenario: E18 A job with nobody behind it is recorded as System
    Given the KYC "Anil Kumar" is unverified
    When the AI extraction writes "50100273107310" to "account" on the KYC "Anil Kumar" with nobody behind it
    Then the latest bank change of the KYC "Anil Kumar" is:
      | status | awaiting      |
      | maker  | System        |
      | side   | system        |
      | source | ai_extraction |

  # E19 — Edge case: after H5, Anil opens his KYC signed in → no change note; details as today
  Scenario: E19 The investor does not see the note
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    When "anil.kumar@example.in" opens the KYC "Anil Kumar"
    Then the KYC page says "50100273107310"
    And the KYC page has no bank change note

  # E20 — Edge case: after H5 (checks off) Ravi sees the badge "Not verified — bank details changed" with its reason
  Scenario: E20 The Bank Verified badge says why
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    When "Ravi" opens the KYC "Anil Kumar"
    Then the Bank Verified badge says "Not verified — bank details changed"
    And the Bank Verified badge explains "Bank verification is off for this firm"

  # E21 — Edge case: after H5 Ravi opens KYC Actions › Audit Trail → the old account and the old Bank Verified listed
  Scenario: E21 The audit trail keeps the old values
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    Then the audit trail of the KYC "Anil Kumar" shows "bank_account_number" changed from "50100012344821"
    And the audit trail of the KYC "Anil Kumar" shows "bank_verified" changed from "true"

  # E22 — Edge case: Bina was verified before release, no records → no note; Verified and Bank Verified as before
  Scenario: E22 KYCs verified before release are untouched
    Given the KYC "Bina Shah" is already verified
    When "Ravi" opens the KYC "Bina Shah"
    Then the KYC page has no bank change note
    And the KYC "Bina Shah" is verified
    And the KYC "Bina Shah" has Bank Verified on
    And no bank change email was sent

  # E23 — Edge case: after H5 the stored record holds only "4821" / "7310", never a full account number
  Scenario: E23 No full account number is stored in the record
    Given the KYC "Anil Kumar" is unverified
    When "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    Then no bank change record of the KYC "Anil Kumar" holds "50100012344821" or "50100273107310"

  # X5 — Error case: a new account with a 21-character IFSC → form error; no record; no email
  Scenario: X5 A failed save leaves no record and sends nothing
    Given the KYC "Anil Kumar" is unverified
    When "Meera" saves the KYC "Anil Kumar" with validation and:
      | account | 50100273107310        |
      | IFSC    | ICIC00045670000000000 |
    Then the save is refused with the form error "Ifsc code is too long"
    And the KYC "Anil Kumar" has no bank change
    And no bank change email was sent
