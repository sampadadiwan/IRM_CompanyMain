# Report Builder with live preview, and a reworked guided wizard — Manual QA Checklist

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
| Accounts | **Meera** (Acme Capital, can edit reports) · **Arjun** (Acme Capital, view only) |
| Second entity | **Omar** (Beta Partners) |
| Seed data | The Phase 1 Acme data (see [business-rules.md](business-rules.md#shared-setup)); report "LPs" |
| Background work | None |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Preview on open | "LPs" + Committed | Open the builder | Rows and "Total" visible without clicking Refresh | | |
| ☐ | H2 | Change updates in place | "LPs" + Committed | Committed header › Total › Count | Panel and preview show Count (Aditi 1); no page reload | | |
| ☐ | H3 | Grouped list | "LPs" | Columns tab | "About the investor", "From capital commitments"; groups Amounts / Dates / Yes/No / Names & text; no "…_id"/"…_cents" | | |
| ☐ | H4 | Add several | "LPs" | Tick Committed, Called, Commitment date › Add selected (3) | All three appear at once; green "3 columns added" | | |
| ☐ | H5 | Rename from header | "LPs" + Committed | Header menu › Rename › "Total committed" | Header reads "Total committed" | | |
| ☐ | H6 | Move right | "LPs" | Stakeholder › Move right | Category, Stakeholder | | |
| ☐ | H7 | Date filter | Commitment report with Folio, Commitment date | Filters › Commitment date › is on or after › pick 01/02/2026 | Saved by itself; F-2, F-3, F-4 | | |
| ☐ | H8 | Pick-list and fund picker | "LPs" | Filters › add Category row; add Fund row on capital commitments | Category: LP, Co-Investor; Fund: Global Fund, Growth Fund II | | |
| ☐ | H9 | Insert into formula | "LPs" + Called | Formulas › Add Formula › click Called | `[capital_commitments.call_amount]` inserted | | |
| ☐ | H10 | Formula samples | "LPs" + Called + Committed | Type `ROUND(Called / Committed * 100, 2)` via buttons | Samples: Aditi 40.00, Kiran 40.00, Zeta 40.00, Nova blank | | |
| ☐ | H11 | Undo a column | "LPs" + Committed | Remove Committed › Undo | Committed back in place, Sum | | |
| ☐ | H12 | Undo related data | "LPs" + 3 commitment columns | Remove capital commitments › Proceed › Undo | Related data, its filter and 3 columns back | | |
| ☐ | H13 | Popup lists columns | "LPs" + Committed, Called | Related data › Remove on capital commitments | Immediate Actions popup names Committed and Called | | |
| ☐ | H14 | Health all good | "LPs" + Committed | Look at the Health button | "All good" | | |
| ☐ | H15 | Mixed currencies | Investor report, commitments without fund filter, Committed | Health | "Committed adds amounts in INR and USD — pick a fund or split by fund" | | |
| ☐ | H16 | Pivot preview | Investor report + commitments | Pivot: Unit Type × Committed (before Apply) | "This will create 2 columns: A, B" | | |
| ☐ | H17 | Labels and help | "LPs" | Hover icon buttons; look at the header | Every icon button has a tooltip; Guide link and ⌘K button present | | |
| ☐ | H18 | Wizard cards | — | Reports › New Custom Report | Cards with icon and example for each table | | |
| ☐ | H19 | No name yet | — | Click Investors | Step "What to show" opens; report "Untitled Report" | | |
| ☐ | H20 | Own and related | H19 | Tick Stakeholder, Committed, Called › Add selected | Commitments added; both amounts show Sum | | |
| ☐ | H21 | Change total inline | H20 | Called › Count | Saved; sample shows counts | | |
| ☐ | H22 | Sample beside the step | H20 | Go to step 3 | 5-row sample with totals on the right | | |
| ☐ | H23 | Fund on related data | H20 | Pick Growth Fund II | "Only commitments in Growth Fund II" | | |
| ☐ | H24 | Sentence filters | H20 | Add Category is LP | "Only include investors where Category is LP" | | |
| ☐ | H25 | Suggestions | H20 + Collected | Step 4 | Called %, Unpaid, Uncalled suggested | | |
| ☐ | H26 | Add suggestion | H25 | Add Called % | Shows Added; Called % in the sample | | |
| ☐ | H27 | Summary and name | H23 | Step 5 | Cards; name "Investors — Committed, Called — Growth Fund II" | | |
| ☐ | H28 | Card opens step | H27 | Click Only include | Step 3 | | |
| ☐ | H29 | Save and open | H27 | Save and open | Report page, named | | |
| ☐ | H30 | Fine-tune | H27 | Fine-tune in builder | Builder | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Nothing ticked | "LPs" | Columns tab | Add selected disabled | | |
| ☐ | E2 | Already added / refused | Developer-assisted request | Add Category, Committed, `no_such` | Committed added; red message names `no_such` | | |
| ☐ | E3 | Same label | Aggregate Portfolio Investment report | Columns tab | Two "Net bought amount" rows with field hints | | |
| ☐ | E4 | Blank rename | H5 | Rename to blank | "Committed" again | | |
| ☐ | E5 | No total one-per-row | Commitment report + fund name | Fund name header menu | No Total entry | | |
| ☐ | E6 | Ends | "LPs" | First header menu; last header menu | Move left / Move right disabled | | |
| ☐ | E7 | Large table field | Investor report + remittances | Filters › remittances Status | Text box | | |
| ☐ | E8 | Many values | 31 investors with different cities | Filters › City | Text box | | |
| ☐ | E9 | Missing value | Builder | Category › is › (no value) | "needs a value"; nothing saved | | |
| ☐ | E10 | Unreadable date | Builder | Type 31/31/2026 | "Enter a date like 19/08/2026" | | |
| ☐ | E11 | Invalid formula | Formulas | Type `Called /` | Error shown; Add Formula disabled | | |
| ☐ | E12 | Undo too late | Developer-assisted (wait 11 min) | Undo | "Too late to undo — removals can be undone for 10 minutes" | | |
| ☐ | E13 | Undo after change | Removed Committed | Change sort › Undo | "Too late to undo — the report has changed since" | | |
| ☐ | E14 | Blank column warning | Developer-prepared broken relation | Health | "…will be blank…" | | |
| ☐ | E15 | Broken formula ref | Formula uses Collected; remove Collected | Health | Names the formula and Collected | | |
| ☐ | E16 | Filter matches nothing | Category is Partner | Health | "No rows match Category is Partner" | | |
| ☐ | E17 | Large pivot | 21 unit types | Pivot on Unit Type | Warning with the column count | | |
| ☐ | E18 | Large export / default totals | Developer-assisted threshold | Health | Info items for export size and default total | | |
| ☐ | E19 | Preview error | Developer-prepared failing report | Open builder | Error inside the preview; tabs work | | |
| ☐ | E20 | Empty report | New report | Open builder | "Tick columns on the left, then Add selected" | | |
| ☐ | E21 | Many related sources (wizard) | Exchange Rate | Step 2 | Own columns open; documents, leg 1, leg 2 closed below | | |
| ☐ | E22 | All funds | H23 | Pick All funds | Fund filter gone | | |
| ☐ | E23 | No fund picker | Exchange Rate | Step 3 | No fund picker | | |
| ☐ | E24 | Nothing to suggest | Stakeholder only | Step 4 | "No suggestions for these columns" | | |
| ☐ | E25 | Blank name | H27 | Clear name › Save and open | Suggested name used | | |
| ☐ | E26 | Old links | Wizard report | Open old /wizard/aggregates link | Opens "What to show" | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Undo other entity | Developer-assisted | Omar requests undo | Refused | | |
| ☐ | X2 | Pivot preview unknown field | Developer-assisted | Request with `no_such` | "no_such isn't a field of capital commitments" | | |
| ☐ | X3 | Bad move | Developer-assisted | direction `up` | Refused; order unchanged | | |
| ☐ | X4 | Unknown table | Developer-assisted | Create with NotAModel | "Choose one of the listed tables" | | |
| ☐ | X5 | Wizard other entity | Omar | Open Acme wizard step URL | Refused | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1–J1.9 | Builder | Proposal Part A, steps A1–A9 | As in the step table | | |
| ☐ | J2.1–J2.6 | Wizard | Proposal Part B, steps B1–B6 | As in the step table | | |

---

## Role Sweep

| ID | Screen / action | Meera (edit) | Arjun (view) | Omar (other entity) |
|---|---|---|---|---|
| R1 | Open builder | ✓ | as today | ✗ |
| R2 | Add / move / remove / undo | ✓ | as today | ✗ |
| R3 | Wizard steps | ✓ | as today | ✗ |
| R4 | Preview | ✓ | ✓ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts | None new | | |
| ☐ | C2 | Dates | Filter date inputs and preview dates in the user's format | | |
| ☐ | C3 | Narrow width | Settings panel stacks above the preview; preview scrolls inside its card | | |
| ☐ | C4 | Tenant isolation | Omar can't reach any builder or wizard URL of Acme | | |
| ☐ | C5 | Regression | Report page, Excel, scheduling, pivots, templates still work | | |
| ☐ | C6 | Empty states | Builder, preview and wizard steps name the next action | | |
| ☐ | C7 | Screen reader | Icon buttons announce their label | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
