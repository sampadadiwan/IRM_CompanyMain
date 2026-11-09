@bank_detail_change
Feature: Payouts flag bank changes still waiting for a second approver (OWASP review 2026-11 M14 — §7)
  Wherever a distribution is paid, a KYC whose bank details changed and wait for a second person is flagged — never
  blocked: the distribution journey panel warns until investors are emailed, the readiness check's bank step fails
  with what to do, and the payments download has a last column "Unconfirmed Bank Change". A KYC with a journey
  warns on its own panel too. Existing columns, warnings and panels are unchanged.
  Horizon Fund I's Q3 2026 Distribution pays Anil Kumar and Bina Shah.
  Worked examples H15–H17, E57–E62, X15:
  openspec/changes/bank-detail-change-controls/business-rules.md#7-payout-flags-and-journey-warnings--phase-5

  Background:
    Given Horizon Capital's "Q3 2026 Distribution" of "Horizon Fund I" pays "Anil Kumar" and "Bina Shah"

  # H15 — Happy path: Meera's change on Anil awaits; the distribution has a journey, not emailed → the panel warns
  Scenario: H15 The distribution panel warns
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    When "Ravi" opens the distribution page of "Q3 2026 Distribution"
    Then the journey panel warns "1 KYC has bank details changed and not yet confirmed by a second approver"

  # H16 — Happy path: the readiness check (bank step) on the distribution → fails with what to do
  Scenario: H16 The readiness check flags it
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    When "Meera" runs the distribution readiness check on "Q3 2026 Distribution" with only the bank details check on
    Then the readiness step "verify_bank_details" is "failed" with "1 investor(s) have bank details changed and not yet confirmed. Ask a second approver to verify the KYC before releasing payment."

  # H17 — Happy path: Meera downloads the payments → last column "Unconfirmed Bank Change": Anil 09/11/2026, Bina blank
  Scenario: H17 The payments download has the column
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    When "Meera" downloads the payments of "Q3 2026 Distribution"
    Then the payments download's last column is "Unconfirmed Bank Change"
    And the payments download shows "2026-11-09" for "Anil Kumar" and nothing for "Bina Shah"

  # E57 — Edge case: H15–H17, then Ravi verifies (H9) → no warning; readiness KYC + bank steps pass; column blank
  Scenario: E57 The flags clear once a second approver verifies
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    When "Ravi" confirms the Verify popup of the KYC "Anil Kumar"
    And "Ravi" opens the distribution page of "Q3 2026 Distribution"
    Then the journey panel has no warning "bank details changed"
    When "Meera" runs the distribution readiness check on "Q3 2026 Distribution" with the KYC and bank details checks on
    Then the readiness step "verify_investor_kyc" is "success"
    And the readiness step "verify_bank_details" is "success"
    When "Meera" downloads the payments of "Q3 2026 Distribution"
    Then the payments download shows nothing for "Anil Kumar" and nothing for "Bina Shah"

  # E58 — Edge case: the distribution's investors were already emailed → no panel warnings; readiness still flags
  Scenario: E58 The panel stops warning once investors are emailed; the readiness check does not
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    And the investors of "Q3 2026 Distribution" have been emailed
    When "Ravi" opens the distribution page of "Q3 2026 Distribution"
    Then the journey panel has no warning "bank details changed"
    When "Meera" runs the distribution readiness check on "Q3 2026 Distribution" with only the bank details check on
    Then the readiness step "verify_bank_details" is "failed" with "1 investor(s) have bank details changed"

  # E59 — Edge case: + one commitment with Skip Doc Gen → both warnings shown
  Scenario: E59 Existing warnings are still shown
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    And Bina Shah's commitment to "Horizon Fund I" is set to Skip Doc Gen
    When "Ravi" opens the distribution page of "Q3 2026 Distribution"
    Then the journey panel warns "1 commitment has Skip Doc Gen set and will not be emailed"
    And the journey panel warns "1 KYC has bank details changed and not yet confirmed by a second approver"

  # E60 — Edge case: any distribution's download → every existing column in its existing position; the new one last
  Scenario: E60 The download keeps its columns in order
    When "Meera" downloads the payments of "Q3 2026 Distribution"
    Then the payments download's columns are the existing ones in order, then "Unconfirmed Bank Change"

  # E61 — Edge case: Anil's KYC has a journey and Meera's change awaits → Ravi's KYC panel warns with maker and date
  Scenario: E61 The KYC journey panel warns
    Given the investor KYC journey of the KYC "Anil Kumar" has reached Verify KYC
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    When "Ravi" opens the KYC "Anil Kumar"
    Then the journey panel warns "Bank details changed on 09/11/2026 by Meera Shah — a different approver must verify"

  # E62 — Edge case: no awaiting change → the distribution panel has no bank change warning (the existing journey
  # scenarios are re-run unchanged in the phase gate)
  Scenario: E62 Other distribution panels are unchanged
    When "Ravi" opens the distribution page of "Q3 2026 Distribution"
    Then the journey panel is shown
    And the journey panel has no warning "bank details changed"

  # X15 — Error case: the agent's bank check is off → the KYC step fails "KYC not verified" for Anil and the run
  # stops there, so the bank step never runs (see design "Changed during the build" C5)
  Scenario: X15 The readiness bank check switched off
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |
    When "Meera" runs the distribution readiness check on "Q3 2026 Distribution" with only the KYC check on
    Then the readiness step "verify_investor_kyc" is "failed" listing "Anil Kumar" as "KYC not verified"
    And the readiness step "verify_bank_details" is not run
