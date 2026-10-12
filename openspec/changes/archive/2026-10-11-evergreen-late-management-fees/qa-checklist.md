# Late management fees on evergreen NAVs — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail. Row IDs match the design's
> worked examples (H/E/X) and journeys (J).

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey step · **R** = Role sweep · **C** = Cross-cutting check

---

## Contents

- [Test Setup](#test-setup)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [UI Journeys](#ui-journeys)
- [Role Sweep](#role-sweep)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

---

## Test Setup

| Item | Detail |
|---|---|
| Environment | Staging, evergreen funds switched on for the entity |
| Accounts | Ravi — fund user with update rights, no approver role · Asha — approver role + update rights · an investor user · a user in a second entity |
| Second entity | Any entity with its own evergreen fund |
| Seed data | Evergreen fund "Alpha Long-Short Fund" (INR), class A at 1.5% (Unit Settings), class B at 0%; folios A Ltd F-012 (60,000 units) and B LLP F-031 (40,000 units); "Management Fee on NAV" formula added (NAV › Fees › Add formula) |
| Background work | Fee accruals: Fund › Allocations › New run with the fee formula for the period. Late entries: run an allocation for a period whose NAV is already approved |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H105 | A late fee is listed on the next draft | 30/09 class A NAV approved with no fee | 1. Run the fee allocation for 01/09–30/09. 2. Draft the 31/10 NAV. 3. Open class A's draft | "Late fees" panel: ₹ amount for the 30/09 period, its % of NAV; payable line unchanged | | |
| ☐ | H106 | Include | H105 | 1. Decide. 2. Choose Include. 3. Save | "Late fee included"; payable rises by the late amount and shows "incl. ₹… late"; audit trail names Asha | | |
| ☐ | H107 | Exclude | H105 (fresh) | 1. Decide. 2. Exclude, reason "Waived for Q3 by side letter". 3. Save. 4. Approve; draft 30/11 | Payable unchanged; reason shown; the 30/11 draft has no Late fees panel | | |
| ☐ | H108 | Approve after accruing | 30/11 draft, fee accrued only to 31/10 | 1. Run allocation 01/11–30/11. 2. Recalculate. 3. Approve | Approved | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E329 | Recording a late entry is never refused | 30/09 approved | Run an allocation for September | Run completes; entries saved | | |
| ☐ | E330 | Uploaded period never late | 30/09 NAV uploaded | Book a fee dated 30/09; draft 31/10 | No Late fees panel | | |
| ☐ | E331 | Late before an upload | 31/08 computed, 30/09 uploaded | Book a fee dated 31/08; draft 31/10 | No panel | | |
| ☐ | E332 | Own-window entry | 30/09 approved | Book a fee dated 15/10; draft 31/10 | Counted in the payable; no panel | | |
| ☐ | E333 | Only class A late | Classes A (1.5%) and B (1.0%) | Late fee for A only; draft 31/10 | Panel for A only; B approves without a decision | | |
| ☐ | E334 | More late after a decision | H106 done | Book ₹10,000 more dated 30/09; Recalculate | Panel asks about ₹10,000 only; the earlier amount stays included | | |
| ☐ | E335 | Change decision | H106 done | Change decision → Exclude with a reason | Payable back to without the late fee | | |
| ☐ | E336 | Late payment | 30/09 approved | Book "Management Fee Paid" ₹1,00,000 dated 25/09; draft 31/10 | Payable −₹1,00,000; listed "always included", no choice | | |
| ☐ | E337 | Late payment split | Classes A and B both owe | Same as E336 | Split between classes in proportion to what each owed | | |
| ☐ | E338 | Investors redeemed since | 2 investors redeemed on 01/10 | Open the 31/10 draft | "2 investors redeemed since 30/09/2026" | | |
| ☐ | E339 | Reopen route | Late fee in 31/08 period, no dealing at 31/08 | Open the draft and the Fees tab | Says the 31/08 NAV can be reopened | | |
| ☐ | E340 | Locked period | Late fee in 30/09 period, dealing 01/10 priced | Open the draft | "30/09 NAV priced 01/10/2026 — it can't be reopened" | | |
| ☐ | E341 | Late entry reversed after deciding | H106 done | Reverse the late entries; Recalculate | Decision removed with an audit note; nothing to decide | | |
| ☐ | E342 | 0% class exempt | Class B 0% | Draft and approve with no accrual | Approved | | |
| ☐ | E343 | Uploaded NAV exempt | Upload a 30/11 NAV for class A | Approve | Approved | | |
| ☐ | E344 | No units exempt | A class's first NAV, no units | Approve | Approved | | |
| ☐ | E345 | Accrual on the NAV date | Accrual dated 30/11 | Approve the 30/11 draft | Approved; no message | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X204 | Exclude needs a reason | H105 | Exclude with blank reason; Save | "Give a reason for excluding the late fee"; nothing saved | | |
| ☐ | X205 | Non-approver can't decide | H105, logged in as Ravi | Look for Decide | No Decide button; a direct request is refused | | |
| ☐ | X206 | Decide on an approved NAV | 31/10 approved | (Developer) send the decide request | "This NAV is already approved" | | |
| ☐ | X207 | Approve with an undecided late fee | H105 | Approve | Button disabled with "Decide the late management fee for class A first"; NAV stays draft | | |
| ☐ | X208 | Approve with fee not accrued | 30/11 accrued to 31/10 | Approve | Disabled with "Management fee accrued only to 31 Oct 2026 — run the fee formula to 30 Nov 2026, then recalculate" | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | NAV › class A 31/10 draft | Open | Late fees panel above the actions; Approve disabled with the reason | | |
| ☐ | J1.2 | Same | Read the panel | Amount, period, % of NAV, investors redeemed, reopen status; the payable each choice would give | | |
| ☐ | J1.3 | Same › Decide | Open the modal | Two options, neither selected; reason field required for Exclude | | |
| ☐ | J1.4 | Same | Save Include | Page reloads; payable updated; panel shows the decision with Change decision; Approve enabled | | |
| ☐ | J1.5 | Same | Approve | Approved; panel read-only "Late fees decided" | | |
| ☐ | J1.6 | NAV › Fees | Find the 31/10 row | "+ ₹… late (Sep), included by Asha <date>" | | |
| ☐ | J1.7 | NAV › Fees | Find the 30/09 row | "Late fee booked" with the reopen route or "decided on a later NAV" | | |

---

## Role Sweep

| ID | Screen / action | Approver (Asha) | Fund user (Ravi) | Investor | Other-entity user |
|---|---|---|---|---|---|
| R1 | See the Late fees panel on a draft | | | | |
| R2 | Decide (Include / Exclude) | | | | |
| R3 | Approve a draft with a decided late fee | | | | |
| R4 | See the decision on the Fees tab | | | | |

Expected: R1 ✓ ✓ ✗ ✗ · R2 ✓ ✗ ✗ ✗ · R3 ✓ ✗ ✗ ✗ · R4 ✓ ✓ ✗ ✗.

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Approver alert | "NAV awaiting approval" for the 31/10 draft mentions a late management fee decision; once per NAV date | | |
| ☐ | C2 | Dates on changed screens | Locale format (e.g. `30/09/2026` for en) | | |
| ☐ | C3 | Narrow width | Panel and modal usable without horizontal scroll | | |
| ☐ | C4 | Tenant isolation | Other-entity user can't open the NAV or send the decide request | | |
| ☐ | C5 | Regression | NAV page (override, recalculate, reopen), Fees tab, approval of uploaded NAVs unchanged | | |
| ☐ | C6 | Empty state | A draft with nothing late shows no panel | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
