@bank_detail_change
Feature: Bank and verification fields only the right people can set (OWASP review 2026-11 M14 — §2)
  Bank Verified and Verified sent with a KYC save are accepted only from a KYC approver of the KYC's firm; anyone
  else's value is ignored without failing the save, and the Bank Verified box is shown only to those who may tick
  it. The bank and PAN check results (status and response) are written only by the checks themselves — never
  accepted from a user, an investor, a magic link or the API.
  Worked examples H4, E11–E13, X2–X4:
  openspec/changes/bank-detail-change-controls/business-rules.md#2-protected-fields--phase-1

  # H4 — Happy path: no awaiting change, Bank Verified off; Ravi ticks Bank Verified and saves → ✓
  Scenario: H4 An approver ticks Bank Verified
    Given the KYC "Anil Kumar" is unverified
    And the KYC "Anil Kumar" starts with Bank Verified off
    When "Ravi" opens the edit page of the KYC "Anil Kumar"
    Then the edit page has a Bank Verified box saying "Tick only after checking proof of the current account"
    When "Ravi" saves the KYC "Anil Kumar" with:
      | Bank Verified | 1 |
    Then the KYC "Anil Kumar" has Bank Verified on

  # E11 — Edge case: Priya (Update, not Approve) sees no box; her crafted bank_verified=1 is dropped, the rest saves
  Scenario: E11 An update-only employee's tick is ignored
    Given the KYC "Anil Kumar" is unverified
    And the KYC "Anil Kumar" starts with Bank Verified off
    When "Priya" opens the edit page of the KYC "Anil Kumar"
    Then the edit page has no Bank Verified box
    When "Priya" saves the KYC "Anil Kumar" with:
      | Bank Verified | 1                     |
      | address       | 22 Lavelle Road, Bengaluru |
    Then the KYC "Anil Kumar" has "address" "22 Lavelle Road, Bengaluru"
    And the KYC "Anil Kumar" has Bank Verified off

  # E12 — Edge case: Priya PATCHes verified: true through the API → 200; still unverified
  Scenario: E12 An update-only employee cannot verify through the API
    Given the KYC "Anil Kumar" is unverified
    When "Priya" sends the KYC "Anil Kumar" over the API with:
      | verified | true |
    Then the KYC API answers 200
    And the KYC "Anil Kumar" is not verified

  # E13 — Edge case: Bank Verified ✓; Ravi changes only the address → ✓ stays
  Scenario: E13 An approver's plain re-save keeps the tick
    Given the KYC "Anil Kumar" is unverified
    When "Ravi" saves the KYC "Anil Kumar" with:
      | address       | 22 Lavelle Road, Bengaluru |
      | Bank Verified | 1                          |
    Then the KYC "Anil Kumar" has Bank Verified on

  # X2 — Error case: Anil's magic link; the form posts bank_verification_status=Verified and a fake response → unchanged
  Scenario: X2 An investor forges the bank check result through the magic link
    Given the KYC "Anil Kumar" was sent to the investor
    And the bank check of "Anil Kumar" last said "Name does not match"
    When the investor "anil.kumar@example.in" submits the KYC "Anil Kumar" through the emailed link with:
      | bank verification status   | Verified                    |
      | bank verification response | {"verified": true, "x": 1} |
      | branch                     | Koramangala                 |
    Then the KYC "Anil Kumar" has "branch" "Koramangala"
    And the KYC "Anil Kumar" keeps its bank check status "Name does not match"
    And the KYC "Anil Kumar" has no bank check response mentioning "verified"

  # X3 — Error case: Anil signed in with a bearer token PATCHes bank_verification_response → 200; unchanged
  Scenario: X3 An investor forges the bank check result through the API
    Given the KYC "Anil Kumar" was sent to the investor
    And the bank check of "Anil Kumar" last said "Name does not match"
    When "anil.kumar@example.in" sends the KYC "Anil Kumar" over the API with:
      | bank verification response | {"verified": true} |
      | bank verification status   | Verified           |
    Then the KYC API answers 200
    And the KYC "Anil Kumar" keeps its bank check status "Name does not match"
    And the KYC "Anil Kumar" has no bank check response mentioning "verified"

  # X4 — Error case: Meera PATCHes pan_verification_status=Verified → unchanged
  Scenario: X4 An employee sends the PAN check result
    Given the KYC "Anil Kumar" is unverified
    When "Meera" sends the KYC "Anil Kumar" over the API with:
      | PAN verification status | Verified |
    Then the KYC API answers 200
    And the KYC "Anil Kumar" has PAN verification status ""
