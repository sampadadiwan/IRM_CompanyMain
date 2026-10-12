# Share Classes: Fair Split and Class-Only Expenses — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail. Row IDs match the design's
> worked examples, so a failure maps straight to its automated test.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey
step · **R** = Role sweep · **C** = Cross-cutting check

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
| Environment | Staging |
| Accounts | Meera (fund user with update rights); Raj (approver); an investor in Class B |
| Second entity | Another company with its own evergreen fund, for isolation checks |
| Seed data | Alpha Evergreen with Classes A and B, each 50,000 units, approved 30 Sep NAV of ₹50 Cr each; ledger "Cash In Hand" ₹100 Cr on 30 Sep. Each row gives its own changes. |
| Ledger entries | Add through Fund › Ledger (or the accounting upload) with the names and amounts each row gives |
| Background work | None |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Split with nothing owed | A 60,000 units at ₹10,000; B 20,000 at ₹20,000; pool ₹110 Cr | 1. NAV › New NAV 31 Oct | A ₹66 Cr and B ₹44 Cr before class lines | | |
| ☐ | H2 | An unpaid fee doesn't drift | A owes ₹1 Cr at 30 Sep (NAV ₹49 Cr); B ₹50 Cr; pool still ₹100 Cr; nothing changes | 1. New NAV 31 Oct | A ₹49 Cr; B ₹50 Cr | | |
| ☐ | H3 | Fee paid from cash | H2; record "Management Fee Paid" ₹1 Cr on 5 Nov and reduce cash by ₹1 Cr | 1. New NAV 30 Nov | A ₹49 Cr with management fee payable ₹0; B ₹50 Cr | | |
| ☐ | H4 | Class expense charged | Class B entries named; "Class B Servicing Fee" ₹40,00,000 on 20 Oct | 1. New NAV 31 Oct 2. Open Class B | "Class expenses payable" −₹40,00,000 with source "Class B Servicing Fee"; B NAV ₹40 lakh lower; A unchanged | | |
| ☐ | H5 | Class expense paid | H4; record "Class B Servicing Fee Paid" ₹40,00,000 on 10 Nov and reduce cash by the same | 1. New NAV 30 Nov | B payable ₹0; B NAV same as 31 Oct; A unchanged | | |
| ☐ | H6 | Name class entries | — | 1. Evergreen settings › Classes › Class B › Customise this class 2. Enter both names 3. Save | Saved; the Review step lists both names | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | One class | One-class fund | 1. New NAV | 100%; same as before the release | | |
| ☐ | E2 | New class | Class C first subscription 1,000 units at initial price ₹10,000 | 1. New NAV | Class C stake ₹1 Cr | | |
| ☐ | E3 | Fully redeemed class | Class B 0 units; its fee ₹10 lakh paid since | 1. New NAV | A 100%; B shows "No units outstanding — initial price" | | |
| ☐ | E4 | Units issued since | A 50,000 → 55,000 on 1 Oct; previous gross ₹10,200 per unit | 1. New NAV | A's base ₹56.1 Cr | | |
| ☐ | E5 | Previous NAV uploaded | Both 30 Sep NAVs uploaded | 1. New NAV | Split equals the uploaded NAVs, scaled for units | | |
| ☐ | E6 | Overpaid fee | Payment ₹1.5 Cr when A owed ₹1 Cr | 1. New NAV | The ₹50 lakh excess is shared by value; no class gains | | |
| ☐ | E7 | Crystallised fee unpaid | B crystallised ₹20 lakh at 30 Sep, unpaid | 1. New NAV | No value moves to A | | |
| ☐ | E8 | Fees owed in proportion | Each class owes 1% of NAV | 1. New NAV | Same as before the release | | |
| ☐ | E9 | Approved NAVs untouched | 30 Sep approved before the release | 1. Open 30 Sep | Figures unchanged | | |
| ☐ | E10 | Three classes, rounding | A, B, C with equal stakes; pool ₹100 Cr | 1. New NAV | The three class NAVs add up to exactly ₹100 Cr | | |
| ☐ | E11 | No units anywhere | All classes 0 units | 1. New NAV | Equal split | | |
| ☐ | E12 | Overridden fee line | A's 30 Sep management fee payable overridden to ₹80 lakh | 1. New NAV | The split uses ₹80 lakh | | |
| ☐ | E13 | Payment on the previous NAV date | Payment dated 30 Sep | 1. New NAV 31 Oct | Not counted again | | |
| ☐ | E14 | Expensed and paid in one month | ₹40 lakh expensed and paid in October | 1. New NAV 31 Oct | B payable ₹0; B NAV ₹40 lakh lower | | |
| ☐ | E15 | Overpaid class expense | Paid ₹50 lakh on ₹40 lakh | 1. New NAV | B payable −₹10,00,000; A unchanged | | |
| ☐ | E16 | Class without entries | Class A has none | 1. Open A's NAV | No "Class expenses payable" row | | |
| ☐ | E17 | Dates around the NAV date | Expenses on 31 Oct and 1 Nov | 1. New NAV 31 Oct | Only 31 Oct counted | | |
| ☐ | E18 | Reversal | −₹40 lakh expense after H4 | 1. New NAV | Payable back to ₹0 | | |
| ☐ | E19 | Override | — | 1. Override B's class expenses payable to ₹35 lakh, reason "per admin" 2. Re-draft | Override kept | | |
| ☐ | E20 | Uploaded NAV | Class B NAV uploaded | 1. Open it | No class expense line | | |
| ☐ | E21 | Entries named later | Expense 20 Oct; entries named 25 Oct | 1. New NAV 31 Oct | Expense counted | | |
| ☐ | E22 | Unclaimed entry warning | "Class C Legal" in the ledger | 1. New NAV 2. Name it on a class 3. Re-draft | "Ledger entry 'Class C Legal' looks class-specific but no class uses it — name it on the class or it is ignored", then gone | | |
| ☐ | E23 | Fund-wide "Class …" name | "Class Action Settlement" | 1. New NAV | Warning shown; figures unaffected | | |
| ☐ | E24 | Expense after drafting | Add an expense after the draft | 1. Open the NAV | Flagged out of date | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Only one entry | — | 1. Enter only the class expenses entry 2. Save | "Class B needs both a class expenses entry and a class expenses paid entry, or neither" | | |
| ☐ | X2 | Name used by another class | Class A uses "Class A Servicing Fee" | 1. Enter it on B 2. Save | "Class B's expense entry 'Class A Servicing Fee' is already used by Class A — each class needs its own entries" | | |
| ☐ | X3 | Fund ledger name | — | 1. Enter "Cash In Hand" 2. Save | "Class B's expense entry 'Cash In Hand' is already one of the fund's ledger settings" | | |
| ☐ | X4 | Too long | — | 1. Enter 126 characters 2. Save | "Class expenses entry is too long (maximum is 125 characters)" | | |
| ☐ | X5 | Clearing with an amount owed | B's latest NAV payable ₹40 lakh | 1. Blank both 2. Save | "Class B still owes ₹40,00,000.00 of class expenses on its latest NAV — pay or reverse it before removing its expense entries" | | |
| ☐ | X6 | Expense makes the NAV negative | B's expense larger than its share | 1. New NAV | The existing negative-NAV message; nothing saved | | |
| ☐ | X7 | Same entry twice | — | 1. Enter "Class B Servicing Fee" in both fields 2. Save | "Class B's class expenses entry and class expenses paid entry must be different" | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Fund › NAV | Open the Class B draft | ① Header "NAV 31 Oct 2026 — Class B", Draft | | |
| ☐ | J1.2 | Class B NAV | Hover ⓘ on Class expenses payable | ③ The entry names it was built from | | |
| ☐ | J1.3 | Class B NAV | Read NAV per unit | ④ The class's own figure | | |
| ☐ | J1.4 | Class B NAV | With an unclaimed "Class C Legal" entry | ⑤ The warning; gone after naming it and re-drafting | | |

---

## Role Sweep

✓ = allowed and works · ✗ = correctly blocked · ! = wrong

| ID | Screen / action | Fund user with update rights | Approver | Investor | Other-entity user |
|---|---|---|---|---|---|
| R1 | Evergreen settings › class expense entries | ✓ | per fund rights | ✗ | ✗ |
| R2 | View a class NAV draft with the new line | ✓ | ✓ | ✗ | ✗ |
| R3 | See the approved NAV per unit | ✓ | ✓ | ✓ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | NAV drafted alert and NAV update email | Arrive as before; dates shown as `Oct 31, 2026` | | |
| ☐ | C2 | Dates on the NAV page | Follow the user's locale format | | |
| ☐ | C3 | Narrow / mobile width | The class settings fields and NAV page fit | | |
| ☐ | C4 | Tenant isolation | The other company's user can't reach these settings or NAVs, even with a direct URL | | |
| ☐ | C5 | Regression | A one-class fund and a fund that owes nothing show the same NAVs as before | | |
| ☐ | C6 | Empty states | A class with no entries shows no new line | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
