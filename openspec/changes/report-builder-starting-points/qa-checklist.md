# Report Builder starting points — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md) · [Business rules](business-rules.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row; put defect links in Notes. Row IDs match [business-rules.md](business-rules.md) (H/E/X) and the proposal's journey (J).

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
| Environment | Staging |
| Accounts | **Meera** (Acme-like company with Funds and Deals, can create reports) · **Omar** (another company) · a user of a company **without** the Funds feature |
| Data | Two funds in different currencies (e.g. INR and USD); investors with commitments, calls, remittances, distributions; at least one portfolio holding and one KPI report if available |
| Existing report | A builder report "LPs" with a few columns, a formula, a sort and a weekly schedule |

---

## Happy Path

| ☐ | ID | Check | Steps | Expected | Pass/Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | H1 | One New report | Open Reports | One **New report** menu: From a template, Guided setup; no "New Custom Report" / "Builder Report" | | |
| ☐ | H2 | Template page | New report › From a template | 10 cards under Investors, Capital calls, Distributions, Fund overview, Portfolio, Compliance | | |
| ☐ | H3 | A card | Read LP Capital Account Summary | Question, "Starts from Investors", Needs a fund, "Includes: 3 formulas · sorted by Unpaid" | | |
| ☐ | H4 | Create with a fund | Use this › pick the INR fund › Create | Builder opens "LP Capital Account Summary — <fund>", message "Created from…", preview filled, badge All good; check Unpaid = Called − Collected for one LP | | |
| ☐ | H5 | No fund needed | Fund Scorecard › Use this | No Fund field; Create makes one row per fund | | |
| ☐ | H6 | Fund optional | Unverified KYC › All funds › Create | No fund filter; only unverified KYCs | | |
| ☐ | H7 | Pivot | Capital Call Collection Tracker › fund › Create | One column per remittance status | | |
| ☐ | H8 | Own name | Type "Q3 LP accounts", Create | Exactly that name | | |
| ☐ | H9 | Duplicate | "LPs" card ⋮ › Duplicate | "Copy of LPs" opens in the builder; columns, labels, totals, order, filters, formulas, sort match | | |
| ☐ | H10 | Original unchanged | Change the copy's fund filter | "LPs" unchanged | | |
| ☐ | H11 | One name | Card menu, guided setup, builder | "Guided setup", "Duplicate"; no "Guided Wizard", "Advanced builder", "Custom report" | | |
| ☐ | H12 | All templates work | Create each of the 10 templates on real data (dev copy) | Each opens with a preview and no error | | |

## Edge Cases

| ☐ | ID | Check | Steps | Expected | Pass/Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | E1 | Fund required | LP Capital Account › Create with no fund | "Choose a fund — this template adds up amounts"; no All funds choice; nothing created | | |
| ☐ | E2 | No Funds feature | Template page as the no-Funds user | Only KPI Matrix (if Deals is on) | | |
| ☐ | E3 | Mixed currencies | Unverified KYC › All funds, where an unverified KYC has commitments in both funds | Report check warns about INR and USD | | |
| ☐ | E4 | Name taken | Duplicate "LPs" twice | Second copy "Copy of LPs (2)" | | |
| ☐ | E5 | Not copied | Duplicate the scheduled "LPs" right after removing a column | Copy has no schedule and no Undo; "LPs" keeps both | | |
| ☐ | E6 | Blank name | Clear the name, pick a fund, Create | Template name — fund | | |
| ☐ | E7 | No Templates button | Open any report in the builder | No Templates button; report unchanged | | |
| ☐ | E8 | Own funds only | Open the Fund list | Only this company's funds | | |
| ☐ | E9 | Fund rows | Fund Scorecard with funds in two currencies | Report check note "The totals row adds funds in INR and USD", no warning | | |

## Error Cases

| ☐ | ID | Check | Steps | Expected | Pass/Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | X1 | Template check | (Engineering) CI run | Template check passes | | |
| ☐ | X2 | Other company's fund | (Engineering) post another company's fund id | Access denied; nothing created | | |
| ☐ | X3 | Unknown template | Open a template address with a wrong name | "That template isn't available" | | |
| ☐ | X4 | Duplicate across companies | As Omar, open the Duplicate address of "LPs" | Refused; nothing created | | |
| ☐ | X5 | Broken template | (Engineering only) | "That template can't be used right now"; nothing created | | |

## UI Journeys

| ☐ | ID | Journey | Expected | Pass/Fail | Notes |
|---|---|---|---|---|---|
| ☐ | J-A | Proposal Part A (A1–A7) | As described, including the A4–A5 refusal | | |
| ☐ | J-B | Proposal Part B (B1–B4) | Copy for another fund in under a minute | | |
| ☐ | J-C | Proposal Part C | Guided setup opens step 1 | | |

## Role Sweep

| ☐ | ID | Role | Expected | Pass/Fail | Notes |
|---|---|---|---|---|---|
| ☐ | R1 | User who can create reports | New report menu, templates, Duplicate | | |
| ☐ | R2 | User of another company | Can't see or duplicate Acme's reports | | |

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass/Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Mobile width | Template cards stack; popup usable | | |
| ☐ | C2 | Keyboard | Use this, popup fields and Create reachable by Tab; Escape closes the popup | | |
| ☐ | C3 | No emails | Creating or duplicating sends nothing | | |
| ☐ | C4 | User guide | Creating a report, templates, Duplicate and FAQs match the screens | | |

## Sign-off

| Role | Name | Date | Result |
|---|---|---|---|
| QA | | | |
| Product | | | |
