# Spec Delta

## MODIFIED Requirements

### Requirement: Management fee accrued up to every NAV date
The management fee SHALL be accrued up to every NAV date, independent of the dealing schedule and of when the fee is paid. When a NAV is drafted for a class whose management fee % is above zero and which has units outstanding at the NAV date, and that class's latest management-fee accrual is dated before the NAV date (or there is none), the draft SHALL show:

> Management fee accrued only to <last accrual date> — run the fee formula to <NAV date>, then recalculate

or, with no accrual at all:

> No management fee accrued yet — run the fee formula to <NAV date>, then recalculate

The system SHALL refuse to approve such a draft, with the same message, whether approval is requested from the NAV page or directly. An uploaded NAV, a class whose management fee % is zero, and a NAV with no units outstanding SHALL be exempt: no message and no refusal.

Payment of the fee SHALL be recorded separately as a fund ledger entry under the name configured in the open-ended settings (default "Management Fee Paid"). It reduces Management fee payable in the first NAV dated on or after the payment.

#### Scenario: Accrual missing for the NAV period
- **WHEN** class A charges 1.5 %, its latest management-fee accrual is dated 31 Oct 2026 and a NAV is drafted for 30 Nov 2026
- **THEN** the draft shows "Management fee accrued only to 31 Oct 2026 — run the fee formula to 30 Nov 2026, then recalculate"

#### Scenario: Approval refused until the fee is accrued
- **WHEN** an approver approves that 30 Nov 2026 draft
- **THEN** approval is refused with the same message and the NAV stays a draft

#### Scenario: Approval allowed once the fee is accrued
- **WHEN** the fee formula is run to 30 Nov 2026 and the draft is recalculated
- **THEN** the message is gone and the approver can approve

#### Scenario: Class without a management fee
- **WHEN** class B charges 0 % management fee and a NAV is drafted
- **THEN** no accrual message is shown for class B and its approval is not refused for the fee

#### Scenario: Uploaded NAV is exempt
- **WHEN** an uploaded NAV for class A (1.5 %) has no management-fee accrual
- **THEN** no accrual message is shown and it can be approved

#### Scenario: NAV with no units outstanding is exempt
- **WHEN** class A's first NAV has no units outstanding and no accrual
- **THEN** no accrual message is shown and it can be approved

#### Scenario: Quarterly NAV accrues for the whole quarter
- **WHEN** the fund strikes NAVs quarterly and the fee formula runs for 1 Oct–31 Dec 2026 with class A at 1.5 % and an approved NAV of ₹102,20,00,000
- **THEN** the accrual is ₹102,20,00,000 × 1.5 % × 92 ÷ 365 = ₹38,64,000

#### Scenario: Payment on its own schedule
- **WHEN** nothing is payable at 30 Sep 2026; fees of ₹12,51,805 (Oct, on ₹98.26 Cr), ₹12,60,000 (Nov, on ₹102.20 Cr) and ₹12,93,082 (Dec, on ₹101.50 Cr) are accrued; and a "Management Fee Paid" entry of ₹38,04,887 is recorded on 5 Jan 2027
- **THEN** Management fee payable is ₹12,51,805 in the 31 Oct NAV, ₹25,11,805 in the 30 Nov NAV and ₹38,04,887 in the 31 Dec NAV, and the 31 Jan 2027 NAV shows only January's accrual of ₹13,12,192

## ADDED Requirements

### Requirement: Late management-fee entries
A management-fee accrual is **late** when it is dated on or before a class's previous approved computed NAV and no NAV has yet counted it or recorded a decision on it. The system SHALL NOT refuse to record a late entry. Periods covered by an uploaded NAV SHALL never produce late entries: accruals dated on or before a class's latest approved uploaded NAV are never late.

When a class's NAV is drafted from the ledger and late accruals exist, the draft SHALL list, for that class: the late amount, the approved NAV period(s) it falls in, the amount as a percentage of this draft's NAV, the number of distinct investors of that class whose redemptions were dealt after the earliest of those periods and on or before this draft's date, and, for each of those approved NAVs, whether it can still be reopened (no dealing date priced at it).

The approver SHALL choose, per class, one of:
- **Include** — the late amount is added to this draft's management fee payable; or
- **Exclude** — the late amount is not taken through any NAV; a reason of 1–255 characters is required.

Neither choice SHALL be pre-selected and there SHALL be no fund-level default. The system SHALL refuse to approve a draft while any late amount on it has no choice. A choice MAY be changed while the NAV is a draft. The choice, the amount, the user, the time and the reason SHALL be recorded in the NAV's audit trail and shown on the NAV page and on the Fees tab row of that NAV. An amount that was included or excluded SHALL never be listed on a later draft; only accruals added after it SHALL be.

A management-fee **payment** dated on or before the previous approved computed NAV and not yet counted SHALL always be included in this draft's payable, split between classes as other payments are, and listed as "always included" without a choice.

#### Scenario: Late fee listed on the next draft
- **WHEN** class A's 30 Sep 2026 NAV (₹19,34,20,000, approved) was drafted with no accrual, ₹2,38,500 of management fee dated 30 Sep 2026 is booked on 11 Oct 2026, and the 31 Oct 2026 NAV of ₹19,40,00,000 is drafted
- **THEN** the draft lists a late amount of ₹2,38,500 for the 30 Sep 2026 period at 0.12 % of NAV and does not add it to the payable

#### Scenario: Approval refused while a late amount is undecided
- **WHEN** the approver approves that 31 Oct 2026 draft without choosing
- **THEN** approval is refused with "Decide the late management fee for class A first" and the NAV stays a draft

#### Scenario: Include a late fee
- **WHEN** the approver chooses Include for the ₹2,38,500 and October's accruals are ₹2,46,000
- **THEN** the 31 Oct 2026 management fee payable is ₹4,84,500 and the audit trail records the inclusion with the approver's name

#### Scenario: Exclude a late fee
- **WHEN** the approver chooses Exclude with reason "Waived for Q3 by side letter"
- **THEN** the payable stays ₹2,46,000, the reason is recorded, and the ₹2,38,500 is not listed on the 30 Nov 2026 draft

#### Scenario: Exclude needs a reason
- **WHEN** the approver chooses Exclude with a blank reason
- **THEN** the choice is refused with "Give a reason for excluding the late fee"

#### Scenario: More late entries after a decision
- **WHEN** after Include was chosen for ₹2,38,500, another ₹10,000 dated 30 Sep 2026 is booked and the 31 Oct 2026 draft is recalculated
- **THEN** the draft lists a late amount of ₹10,000 needing a choice, and the earlier ₹2,38,500 stays included

#### Scenario: Investors who redeemed since
- **WHEN** two class A investors had redemptions dealt on 1 Oct 2026, and a class I investor too, and class A's 31 Oct 2026 draft lists a late amount for the 30 Sep 2026 period
- **THEN** the draft says 2 investors redeemed since that period — another class never bears class A's fee

#### Scenario: Late payment always included
- **WHEN** a "Management Fee Paid" entry of ₹1,00,000 dated 25 Sep 2026 is booked after the 30 Sep 2026 NAV was approved
- **THEN** the 31 Oct 2026 draft reduces its payable by ₹1,00,000 and lists it as always included, with no choice

#### Scenario: Uploaded NAV period is never late
- **WHEN** class A's 30 Sep 2026 NAV was uploaded and an accrual dated 30 Sep 2026 is booked afterwards
- **THEN** the 31 Oct 2026 draft lists no late amount for class A

#### Scenario: Reopen route shown when possible
- **WHEN** the late amount falls in the 31 Aug 2026 period and no dealing date was priced at the 31 Aug 2026 NAV
- **THEN** the draft and the Fees tab row for 31 Aug 2026 say that NAV can be reopened and recalculated to put the fee in its own period
