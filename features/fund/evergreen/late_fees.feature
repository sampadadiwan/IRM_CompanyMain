Feature: Evergreen late management fees — approval needs the fee accrued; late fees are decided, never lost
  Worked examples H105–H108, E329–E345, X204–X208 —
  openspec/changes/archive/2026-10-11-evergreen-late-management-fees/design.md#worked-examples
  Business rules R9.2, R9.10–R9.18 — docs/modules/funds/evergreen_business_rules.md

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 60000 | 2025-09-01 |
      | B LLP    | F-031 | A     | 40000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"

  # ---- Phase 1: approval refuses a NAV without its fee (R9.2) ----

  # H108 — Happy path: the 30 Nov draft accrued only to 31 Oct is refused; once the fee is accrued to 30 Nov and the draft recalculated, it approves.
  Scenario: A NAV approves once its fee is accrued to the NAV date
    Given class "A" charges a management fee of "1.5"
    And folio "F-012" accrued a management fee of "12,51,805" on "2026-10-31"
    When I draft the NAV for "2026-11-30"
    Then approving the class "A" NAV for "2026-11-30" is refused with "Management fee accrued only to 31 October 2026 — run the fee formula to 30 November 2026, then recalculate"
    Given folio "F-012" accrued a management fee of "12,60,000" on "2026-11-30"
    When I draft the NAV for "2026-11-30"
    Then approving the class "A" NAV for "2026-11-30" succeeds

  # X208 — Error case: with no fee accrued at all, the NAV page disables Approve with the reason, and a direct approval is refused with it too.
  Scenario: Approve is disabled while no fee is accrued
    Given the user has role "approver"
    And class "A" charges a management fee of "1.5"
    When I draft the NAV for "2026-11-30"
    And I open the class "A" NAV for "2026-11-30"
    Then I should see "No management fee accrued yet — run the fee formula to 30 November 2026, then recalculate"
    And the Approve button should be disabled
    And approving the class "A" NAV for "2026-11-30" is refused with "No management fee accrued yet — run the fee formula to 30 November 2026, then recalculate"

  # E342 — Edge case: a class charging 0 % has no fee to accrue, so its draft approves without one.
  Scenario: A class without a management fee approves without an accrual
    Given class "A" charges a management fee of "0"
    When I draft the NAV for "2026-11-30"
    Then approving the class "A" NAV for "2026-11-30" succeeds

  # E343 — Edge case: an uploaded draft is the administrator's figure with the fee in it — it approves with no accrual.
  @rack_test
  Scenario: An uploaded NAV approves without an accrual
    Given class "A" charges a management fee of "1.5"
    And an uploaded draft NAV for class "A" on "2026-11-30" with NAV per unit "10,220" and units "100000"
    Then approving the class "A" NAV for "2026-11-30" succeeds

  # E344 — Edge case: a NAV with no units outstanding (a class's first NAV) has nothing to charge a fee on — it approves with no accrual.
  @rack_test
  Scenario: A NAV with no units outstanding approves without an accrual
    Given class "A" charges a management fee of "1.5"
    And a computed draft NAV for class "A" on "2025-08-29" with no units outstanding
    Then approving the class "A" NAV for "2025-08-29" succeeds

  # E345 — Edge case: an accrual dated on the NAV date itself is up to date — it approves.
  Scenario: An accrual dated on the NAV date is enough
    Given class "A" charges a management fee of "1.5"
    And folio "F-012" accrued a management fee of "12,60,000" on "2026-11-30"
    When I draft the NAV for "2026-11-30"
    Then approving the class "A" NAV for "2026-11-30" succeeds

  # ---- Phase 2: what each NAV accounted for, and finding late amounts (R9.10, R9.11, R9.17, R9.18) ----

  # H105 — Happy path: 30 Sep was approved with no fee; ₹2,38,500 dated 30 Sep is booked afterwards. The 31 Oct draft takes October's ₹2,46,000 into its payable and holds the ₹2,38,500 as late, undecided — not added.
  @rack_test
  Scenario: A fee booked after its NAV was approved is found as late
    Given class "A" charges a management fee of "1.5"
    And the class "A" NAV for "2026-09-30" was drafted and approved before a fee was required
    And folio "F-012" accrued a management fee of "2,38,500" on "2026-09-30"
    And folio "F-012" accrued a management fee of "2,46,000" on "2026-10-31"
    When the NAVs for "2026-10-31" are drafted
    Then the class "A" draft for "2026-10-31" should have a late fee of "2,38,500" waiting for a decision
    And the class "A" NAV for "2026-10-31" should be:
      | mgmt_fee_payable_cents   | 2,46,000 |
      | mgmt_fee_accounted_cents | 2,46,000 |
    When I open the class "A" NAV for "2026-10-31"
    Then I should see "₹2,38,500.00 of management fee is dated in the period of the 30/09/2026 NAV"
    And I should see "Decide before approving"

  # E329 — Edge case: an allocation run books September's fee after the 30 Sep NAV was approved — the run is not refused, and its ₹12,60,000 shows as late on the 31 Oct draft.
  @rack_test
  Scenario: Recording a fee into an approved period is never refused
    Given class "A" charges a management fee of "1.5"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,220" and units "100000"
    And the class "A" NAV for "2026-09-30" was drafted and approved before a fee was required
    And the management fee formula is added
    And the Allocation Run "start_date=2026-09-01;end_date=2026-09-30" is created for the "Alpha Long-Short Fund"
    Then the management fee entries for "2026-09-30" should total "12,60,000"
    When the NAVs for "2026-10-31" are drafted
    Then the class "A" draft for "2026-10-31" should have a late fee of "12,60,000" waiting for a decision

  # E330 — Edge case: the 30 Sep NAV was uploaded — the administrator's figure includes the fee — so an accrual dated 30 Sep booked afterwards is never late.
  @rack_test
  Scenario: A period covered by an uploaded NAV is never late
    Given class "A" charges a management fee of "1.5"
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,220" and units "100000"
    And folio "F-012" accrued a management fee of "2,38,500" on "2026-09-30"
    And folio "F-012" accrued a management fee of "2,46,000" on "2026-10-31"
    When the NAVs for "2026-10-31" are drafted
    Then the class "A" draft for "2026-10-31" should have no late fee

  # E331 — Edge case: 31 Aug was drafted (no fee), 30 Sep uploaded; an accrual dated 31 Aug booked later falls before the upload, so it is never late.
  @rack_test
  Scenario: An entry dated before the latest uploaded NAV is never late
    Given class "A" charges a management fee of "1.5"
    And the class "A" NAV for "2026-08-31" was drafted and approved before a fee was required
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,220" and units "100000"
    And folio "F-012" accrued a management fee of "2,30,000" on "2026-08-31"
    And folio "F-012" accrued a management fee of "2,46,000" on "2026-10-31"
    When the NAVs for "2026-10-31" are drafted
    Then the class "A" draft for "2026-10-31" should have no late fee

  # E332 — Edge case: an accrual dated 15 Oct is in the 31 Oct draft's own period — counted in its payable, not late.
  @rack_test
  Scenario: An entry in the draft's own period is not late
    Given class "A" charges a management fee of "1.5"
    And the class "A" NAV for "2026-09-30" was drafted and approved before a fee was required
    And folio "F-012" accrued a management fee of "1,20,000" on "2026-10-15"
    And folio "F-012" accrued a management fee of "1,26,000" on "2026-10-31"
    When the NAVs for "2026-10-31" are drafted
    Then the class "A" draft for "2026-10-31" should have no late fee
    And the class "A" NAV for "2026-10-31" should be:
      | mgmt_fee_payable_cents | 2,46,000 |

  # E336 — Edge case: a ₹1,00,000 "Management Fee Paid" entry dated 25 Sep is booked after 30 Sep was approved. It is always included: the 31 Oct payable is ₹2,46,000 − ₹1,00,000 = ₹1,46,000, with no choice.
  @rack_test
  Scenario: A late fee payment is always included
    Given class "A" charges a management fee of "1.5"
    And the class "A" NAV for "2026-09-30" was drafted and approved before a fee was required
    And the fund ledger has "Management Fee Paid" of "1,00,000" on "2026-09-25"
    And folio "F-012" accrued a management fee of "2,46,000" on "2026-10-31"
    When the NAVs for "2026-10-31" are drafted
    Then the class "A" draft for "2026-10-31" should have no late fee
    And the "2026-10-31" drafts should include a late fee payment of "1,00,000"
    And the class "A" NAV for "2026-10-31" should be:
      | mgmt_fee_payable_cents        | 1,46,000 |
      | mgmt_fee_paid_accounted_cents | 1,00,000 |

  # ---- Phase 3: deciding, the panel and the second refusal (R9.12–R9.16) ----

  # H106 — Happy path: on the 31 Oct draft the approver includes the ₹2,38,500 — the payable becomes ₹2,46,000 + ₹2,38,500 = ₹4,84,500 and the audit trail names who included it.
  @rack_test
  Scenario: Include a late fee
    Given the user has role "approver"
    And class "A" has a late fee of "2,38,500" dated "2026-09-30" on its "2026-10-31" draft, with "2,46,000" accrued for October
    When I open the class "A" NAV for "2026-10-31"
    And I decide to "include" the late fee
    Then I should see "Late fee included"
    And I should see "The management fee payable includes ₹2,38,500.00 of late fee."
    And the class "A" NAV for "2026-10-31" should be:
      | mgmt_fee_payable_cents   | 4,84,500 |
      | mgmt_fee_accounted_cents | 4,84,500 |
    And the NAV audit trail for class "A" on "2026-10-31" should note "included by"
    And approving the class "A" NAV for "2026-10-31" succeeds

  # H107 — Happy path: the approver excludes it ("Waived for Q3 by side letter") — the payable stays ₹2,46,000, and once 31 Oct is approved the 30 Nov draft has nothing late.
  @rack_test
  Scenario: Exclude a late fee
    Given class "A" has a late fee of "2,38,500" dated "2026-09-30" on its "2026-10-31" draft, with "2,46,000" accrued for October
    When the approver decides to "exclude" the late fee on the class "A" NAV for "2026-10-31" with reason "Waived for Q3 by side letter"
    Then the class "A" NAV for "2026-10-31" should be:
      | mgmt_fee_payable_cents | 2,46,000 |
    And approving the class "A" NAV for "2026-10-31" succeeds
    Given folio "F-012" accrued a management fee of "2,50,000" on "2026-11-30"
    When the NAVs for "2026-11-30" are drafted
    Then the class "A" draft for "2026-11-30" should have no late fee

  # X204 — Error case: Exclude with a blank reason is refused with "Give a reason for excluding the late fee"; nothing is saved.
  @rack_test
  Scenario: Excluding needs a reason
    Given the user has role "approver"
    And class "A" has a late fee of "2,38,500" dated "2026-09-30" on its "2026-10-31" draft, with "2,46,000" accrued for October
    When I open the class "A" NAV for "2026-10-31"
    And I decide to "exclude" the late fee
    Then I should see "Give a reason for excluding the late fee"
    And the class "A" draft for "2026-10-31" should have a late fee of "2,38,500" waiting for a decision

  # X207 — Error case: approving with the late fee undecided is refused with "Decide the late management fee for class A first".
  @rack_test
  Scenario: Approval waits for the late fee decision
    Given class "A" has a late fee of "2,38,500" dated "2026-09-30" on its "2026-10-31" draft, with "2,46,000" accrued for October
    Then approving the class "A" NAV for "2026-10-31" is refused with "Decide the late management fee for class A first"

  # X205 — Error case: a fund user without the approver role sees no Decide button, and a decision from them is refused.
  @rack_test
  Scenario: Only an approver decides a late fee
    Given class "A" has a late fee of "2,38,500" dated "2026-09-30" on its "2026-10-31" draft, with "2,46,000" accrued for October
    When I open the class "A" NAV for "2026-10-31"
    Then I should see "An approver decides this late fee."
    And I should not see "Save decision"
    And deciding to "include" the late fee on the class "A" NAV for "2026-10-31" as myself is refused with "Only an approver can decide a late fee"

  # X206 — Error case: a decision on an approved NAV is refused with "This NAV is already approved".
  @rack_test
  Scenario: No late fee decision on an approved NAV
    Given class "A" has a late fee of "2,38,500" dated "2026-09-30" on its "2026-10-31" draft, with "2,46,000" accrued for October
    And the approver decides to "include" the late fee on the class "A" NAV for "2026-10-31"
    And approving the class "A" NAV for "2026-10-31" succeeds
    Then deciding to "exclude" the late fee on the class "A" NAV for "2026-10-31" as the approver is refused with "This NAV is already approved"

  # E334 — Edge case: after ₹2,38,500 was included, another ₹10,000 dated 30 Sep is booked; on recalculation only the ₹10,000 needs a decision and the ₹2,38,500 stays included.
  @rack_test
  Scenario: More late fees after a decision need only their own decision
    Given class "A" has a late fee of "2,38,500" dated "2026-09-30" on its "2026-10-31" draft, with "2,46,000" accrued for October
    And the approver decides to "include" the late fee on the class "A" NAV for "2026-10-31"
    And folio "F-012" accrued a management fee of "10,000" on "2026-09-30"
    When the NAVs for "2026-10-31" are drafted
    Then the class "A" draft for "2026-10-31" should have a late fee of "10,000" waiting for a decision
    And the class "A" NAV for "2026-10-31" should be:
      | mgmt_fee_payable_cents | 4,84,500 |

  # E335 — Edge case: Change decision clears the inclusion; excluding instead puts the payable back to ₹2,46,000.
  @rack_test
  Scenario: Change a late fee decision on a draft
    Given class "A" has a late fee of "2,38,500" dated "2026-09-30" on its "2026-10-31" draft, with "2,46,000" accrued for October
    And the approver decides to "include" the late fee on the class "A" NAV for "2026-10-31"
    When the approver decides to "clear" the late fee on the class "A" NAV for "2026-10-31"
    And the approver decides to "exclude" the late fee on the class "A" NAV for "2026-10-31" with reason "Charged to the manager directly"
    Then the class "A" NAV for "2026-10-31" should be:
      | mgmt_fee_payable_cents | 2,46,000 |
    And the class "A" draft for "2026-10-31" should have no late fee waiting for a decision

  # E341 — Edge case: the ₹2,38,500 is reversed after it was included; on recalculation the decision is dropped with an audit note and nothing is late.
  @rack_test
  Scenario: A decided late fee that is reversed drops its decision
    Given class "A" has a late fee of "2,38,500" dated "2026-09-30" on its "2026-10-31" draft, with "2,46,000" accrued for October
    And the approver decides to "include" the late fee on the class "A" NAV for "2026-10-31"
    And folio "F-012" accrued a management fee of "-2,38,500" on "2026-09-30"
    When the NAVs for "2026-10-31" are drafted
    Then the class "A" draft for "2026-10-31" should have no late fee
    And the class "A" NAV for "2026-10-31" should be:
      | mgmt_fee_payable_cents | 2,46,000 |
    And the NAV audit trail for class "A" on "2026-10-31" should note "Late fee decision removed"

  # E338 — Edge case: A Ltd and B LLP (class A) redeemed on 1 Oct; the 31 Oct panel says 2 investors redeemed since 30/09/2026.
  @rack_test
  Scenario: The panel counts the class's investors who redeemed since
    Given class "A" has a late fee of "2,38,500" dated "2026-09-30" on its "2026-10-31" draft, with "2,46,000" accrued for October
    And folios "F-012,F-031" redeemed on dealing date "2026-10-01"
    When I open the class "A" NAV for "2026-10-31"
    Then I should see "2 investors redeemed since 30/09/2026"

  # E339 — Edge case: no dealing date was priced at the 30 Sep NAV, so the panel and the Fees tab offer reopening it instead.
  @rack_test
  Scenario: A late fee's NAV that can still be reopened
    Given class "A" has a late fee of "2,38,500" dated "2026-09-30" on its "2026-10-31" draft, with "2,46,000" accrued for October
    When I open the class "A" NAV for "2026-10-31"
    Then I should see "The 30/09/2026 NAV can be reopened"
    When I open the fees tab
    Then the fees row for class "A" on "2026-09-30" should show "Late fee booked"
    And the fees row for class "A" on "2026-09-30" should show "Reopen this NAV to put it in its own month"

  # E340 — Edge case: the 30 Sep NAV priced the 1 Oct dealing date, so it can't be reopened — the panel says so.
  @rack_test
  Scenario: A late fee's NAV that priced a dealing date
    Given class "A" has a late fee of "2,38,500" dated "2026-09-30" on its "2026-10-31" draft, with "2,46,000" accrued for October
    And the class "A" NAV for "2026-09-30" priced a dealing date on "2026-10-01"
    When I open the class "A" NAV for "2026-10-31"
    Then I should see "it can't be reopened"
