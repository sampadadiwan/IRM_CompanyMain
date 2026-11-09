@bank_detail_change
Feature: The maker of a bank change cannot verify it by any route (OWASP review 2026-11 M14 — §5 refusals)
  A direct request, an API call or a crafted Bank Verified tick from the person who made an awaiting bank change is
  refused or ignored, with the reason; people who may not verify at all are refused as before; another firm sees
  nothing; and a double-clicked popup verifies once.
  Worked examples X7–X12:
  openspec/changes/bank-detail-change-controls/business-rules.md#5-second-person--phase-3

  Background:
    Given the KYC "Anil Kumar" is unverified
    And "Meera" saves the KYC "Anil Kumar" with:
      | account | 50100273107310 |

  # X7 — Error case: Meera PUTs /investor_kycs/:id/toggle_verified → refused with the reason; still unverified
  Scenario: X7 The maker's direct Verify request is refused
    When "Meera" verifies the KYC "Anil Kumar" from its page
    Then "Meera" is told "You changed this KYC's bank details, so another KYC approver must verify it."
    And the KYC "Anil Kumar" is not verified
    When "Meera" sends a JSON Verify request for the KYC "Anil Kumar"
    Then the KYC API answers 403
    And the KYC API error says "You changed this KYC's bank details, so another KYC approver must verify it."

  # X8 — Error case: Meera PATCHes verified: true → ignored; still unverified
  Scenario: X8 The maker's API verify is ignored
    When "Meera" sends the KYC "Anil Kumar" over the API with:
      | verified | true |
    Then the KYC API answers 200
    And the KYC "Anil Kumar" is not verified
    And the latest bank change of the KYC "Anil Kumar" is:
      | status | awaiting |

  # X9 — Error case: Meera PATCHes bank_verified: 1 → ignored; still off
  Scenario: X9 The maker's crafted Bank Verified tick is ignored
    When "Meera" saves the KYC "Anil Kumar" with:
      | Bank Verified | 1 |
    Then the KYC "Anil Kumar" has Bank Verified off

  # X10 — Error case: Priya (no Approve) PUTs toggle_verified → refused (not authorized), as today
  Scenario: X10 A non-approver's Verify is refused as before
    When "Priya" verifies the KYC "Anil Kumar" from its page
    Then "Priya" is told "Access Denied"
    And the KYC "Anil Kumar" is not verified

  # X11 — Error case: Omar (Northwind) opens Horizon's KYC page and PUTs toggle_verified → both refused; nothing shown
  Scenario: X11 Another firm sees and verifies nothing
    When "Omar" opens the KYC "Anil Kumar"
    Then the KYC page does not say "Bank details changed"
    And the KYC page does not say "50100273107310"
    When "Omar" verifies the KYC "Anil Kumar" from its page
    Then "Omar" is told "Access Denied"
    And the KYC "Anil Kumar" is not verified

  # X12 — Error case: Ravi submits the popup twice → verified once; one confirmation; no new record
  Scenario: X12 A double-clicked popup verifies once
    When "Ravi" confirms the Verify popup of the KYC "Anil Kumar"
    And "Ravi" submits the Verify popup of the KYC "Anil Kumar" again
    Then "Ravi" is told "Investor kyc was successfully verified."
    And the KYC "Anil Kumar" is verified
    And the KYC "Anil Kumar" has 1 bank changes, the first "confirmed"
