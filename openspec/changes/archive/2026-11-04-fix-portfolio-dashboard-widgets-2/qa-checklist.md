# Fix Portfolio Dashboard Widgets (second batch) — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X) and UI journeys
> (J), so a failure maps straight to the automated test that should have caught it.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey
step (J2.3 = journey 2, step 3) · **R** = Role sweep · **C** = Cross-cutting check

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
| Environment | Staging, with the release build deployed and the clean-up script already applied |
| Accounts | Fund admin "Meera" (can edit dashboard widgets) in Golden Angels; employee without widget edit rights; LP "Ravi" (investor user) with an Allocated LP portfolio view on Alpha Growth Fund |
| Second entity | Any user of another entity, for isolation checks |
| Seed data | Portfolio company **Flipkart Unlisted** with portfolio investments (figures as in [design shared setup](design.md#worked-examples)); fund **Alpha Growth Fund** (INR, default units Crores) with portfolio investments; Ravi's folio allocated part of the holdings; **Note Summariser** agent enabled for Golden Angels with Summary period blank (Quarter). Golden Angels: firm currency INR, USD exchange rates set up, no SGD rates; tracking currency USD available for E20 |
| Notes | On Flipkart Unlisted: four notes dated 27/10/2026, 29/10/2026, 30/10/2026, 04/11/2026. For H12/X2, a second company with notes dated 10/08/2026 and 20/09/2026 |
| Dates | Expected periods below assume testing in Q4 2026 (Oct–Dec). If testing on another date, the expected period is the last *completed* quarter before today |
| Background work | Run Summariser queues a background job. Wait about a minute and reload; if nothing appears, ask a developer to check the Sidekiq queue |
| Widgets | On Flipkart Unlisted's dashboard: Portfolio Stats, Data Card, Notes, Note Summaries. On Alpha Growth Fund's Portfolio Dashboard: Portfolio Stats. On its Fund Dashboard: Fund Portfolio Stats |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Fields saved in picked order | Logged in as Meera | 1. Flipkart Unlisted › Dashboard › Portfolio Stats › Edit. 2. In Fields pick FMV, then Bought Amount. 3. Save. 4. Edit again | Fields shows FMV then Bought Amount; the dashboard shows the FMV card before the Bought Amount card | | |
| ☐ | H2 | Saved fields reopen in order | Widget saved with Sold Amount then Bought Amount | 1. Open Edit | Fields shows Sold Amount, then Bought Amount | | |
| ☐ | H3 | Field names hint | — | 1. Alpha Growth Fund › Fund Dashboard › Fund Portfolio Stats › Edit | Under Field names: "List the names in the same order as the Fields you picked, separated by commas. E.g. Bought Amount, Sold Amount, FMV → Buy, Sell, Fair value" | | |
| ☐ | H4 | Renamed label shows at once | Flipkart widget: Fields Bought Amount, Field names Buy; dashboard opened once | 1. Edit, change Field names to Invested, Save. 2. Reload the dashboard | The card reads "Invested" straight away | | |
| ☐ | H5 | Fund widget picks and names | — | 1. Alpha Growth Fund › Portfolio Dashboard › Portfolio Stats › Edit. 2. Pick FMV, then Sold + FMV. 3. Field names: Value, Total value. 4. Save | Two cards: "Value" ₹310.00 Cr, then "Total value" ₹350.00 Cr (40.00 + 310.00) | | |
| ☐ | H6 | Fund units and decimals | — | 1. Fund Dashboard › Fund Portfolio Stats › Edit. 2. Units Lakhs, Decimals 0. 3. Save | FMV reads ₹31,000 L; no decimals on any card | | |
| ☐ | H7 | Fund cards per row | Fund Portfolio Stats with no Fields | 1. Edit, Cards per row 2, Save | Five cards, two per row; the fifth fills its row | | |
| ☐ | H8 | Data Card offers Fields and Title | — | 1. Flipkart › Dashboard Widgets › New. 2. Choose Data Card | Settings offered: Fields and Title only; no Cols, no Field names | | |
| ☐ | H9 | Data Card help stays | Data Card Edit open | 1. Type "Category:" in Fields | Help text under Fields stays visible and mentions `custom_fields.` with the example `KPI Currency:custom_fields.kpi_currency` | | |
| ☐ | H10 | Window names the quarter | Logged in as Meera, any date in Q4 2026 | 1. Flipkart › Notes widget › Summarise Notes | Window shows "Summarises notes dated Jul 01, 2026 – Sep 30, 2026 (the last completed quarter)." | | |
| ☐ | H11 | Message after Run | Window open | 1. Click Run Summariser | Window closes; page shows "Summarising notes dated Jul 01, 2026 – Sep 30, 2026. The summary will appear in this Notes list as a note tagged 'summary' dated 30/09/2026, and in the Note Summaries widget." | | |
| ☐ | H12 | Summary note appears | Second company with notes dated 10/08/2026 and 20/09/2026 | 1. Summarise Notes › Run Summariser on that company. 2. Wait a minute, reload | Notes list has a note tagged "summary, quarter" dated 30/09/2026 with a summary of the two notes; Note Summaries shows the same summary with Notes processed 2 | | |
| ☐ | H13 | Default currency used | Flipkart widget: Default currency USD, Show currency filter ON, Tracking currency off | 1. Open the dashboard; don't touch the drop-down | Cards in USD; the Currency drop-down shows USD | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Lower-case fields | Ask a developer to save the Flipkart widget with `fields: 'fmv, sold amount'` (an old-style setting) | 1. Open the dashboard | FMV card, then Sold Amount card | | |
| ☐ | E2 | Fewer names than cards | Fields Bought Amount, Sold Amount, FMV; Field names Buy | 1. Open the dashboard | Cards read Buy, Sold Amount, FMV | | |
| ☐ | E3 | More names than cards; duplicate | Developer saves `fields: 'FMV, fmv'`, Field names `Value, Extra` | 1. Open the dashboard | One card, "Value" | | |
| ☐ | E4 | Decimals change shows at once | Flipkart widget Decimals 2; dashboard opened | 1. Set Decimals 0, Save. 2. Reload | Amounts show no decimals straight away | | |
| ☐ | E5 | Widget doesn't leak into Portfolio Investments page | Alpha Growth Fund Portfolio Stats with Fields FMV; dashboard opened | 1. Open Alpha Growth Fund › Portfolio Investments | The cards above the grid are the usual five: Bought Amount, Sold Amount, FMV, Cost Of Remaining, Income | | |
| ☐ | E6 | Fund widget with no settings looks as before | Clear all settings on the fund's Portfolio Stats | 1. Open the Portfolio Dashboard | Bought Amount, Sold Amount, FMV, Cost Of Remaining, Income in Cr with 2 decimals; no Sold + FMV card | | |
| ☐ | E7 | LP folio totals unaffected by settings | Fund Portfolio Stats Fields FMV; Alpha Growth Fund's LP view is Allocated | 1. Log in as Ravi. 2. Open Alpha Growth Fund's Portfolio Dashboard. 3. Open its Portfolio Investments page | Step 2: the holdings list, no Portfolio Stats widget (as today). Step 3: FMV card shows Ravi's folio total (₹62.00 Cr in the seed), not the fund's ₹310.00 Cr | | |
| ☐ | E8 | Monthly agent | Agent's Summary period set to Month | 1. Summarise Notes | Window shows "Summarises notes dated Oct 01, 2026 – Oct 31, 2026 (the last completed month)." (when testing in November 2026) | | |
| ☐ | E9 | Window and report agree | Quarterly agent | 1. Note the window's dates. 2. Run. 3. Open Note Summaries | Period shows Quarter (Jul 01, 2026 – Sep 30, 2026), the same as the window | | |
| ☐ | E10 | Notes only after the period | Flipkart's notes all in Oct–Nov 2026 | 1. Run Summariser. 2. Open Note Summaries, expand the entry | "Notes processed: 0" and "No notes dated Jul 01, 2026 – Sep 30, 2026. Notes dated after Sep 30, 2026 will be in the next quarter's summary."; no empty Summary box | | |
| ☐ | E11 | Unknown saved field dropped | Developer saves `fields: 'FMV, Total FMV'` | 1. Open Edit. 2. Save without changes | Fields shows only FMV; after saving, the widget shows only FMV | | |
| ☐ | E12 | Company stats: Default currency offered | — | 1. New widget › Portfolio Stats on Portfolio Company Dashboard | Tracking currency, Show currency filter and **Default currency** are offered; Default currency is a pick-list of USD and INR with the help text "Order: picked on page > Tracking currency (if ON) > Default currency > firm's currency" | | |
| ☐ | E13 | Fund stats: no currency settings | — | 1. New widget › Fund Portfolio Stats on Fund Dashboard | No Currency, Tracking currency or Show currency filter | | |
| ☐ | E14 | Year boundary | Ask a developer to confirm by test only (needs date change) | — | Run on 01 Jan 2027 covers Oct 01, 2026 – Dec 31, 2026 (automated test) | | |
| ☐ | E15 | Last day of a quarter | Automated test only | — | Run on Sep 30, 2026 covers Apr 01, 2026 – Jun 30, 2026 | | |
| ☐ | E16 | Agent disabled | Agent disabled for Golden Angels | 1. Open Flipkart's Notes widget | Summarise Notes is greyed out with a lock; clicking does nothing | | |
| ☐ | E17 | All chips removed | Widget Fields FMV | 1. Edit, remove the FMV chip, Save | Widget shows all cards | | |
| ☐ | E18 | New widget, name chosen later | — | 1. Dashboard Widgets › New, dashboard Portfolio Company. 2. Choose widget name Portfolio Stats. 3. Pick FMV in Fields. 4. Save | Fields is a searchable multi-select; saved widget shows only FMV | | |
| ☐ | E19 | Picked currency wins | As H13 | 1. Pick INR in the Currency drop-down | Cards switch to INR | | |
| ☐ | E20 | Tracking currency wins | Golden Angels tracking currency USD; Flipkart widget Tracking currency ON, Default currency INR | 1. Open the dashboard | Cards in USD | | |
| ☐ | E21 | Drop-down lists the firm's currencies | Golden Angels with SGD↔INR rates added; Flipkart widget Show currency filter ON | 1. Open the Currency drop-down. 2. Pick SGD | Lists INR, SGD, USD (as in the widget editor's Default currency); cards switch to S$, not 0.00 | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | No field matches | Developer saves Flipkart widget `fields: 'Total FMV'` | 1. Open the dashboard | All six default cards; no error | | |
| ☐ | X2 | Summary fails with notes present | Automated test only (needs the LLM to fail) | — | "Notes processed: 1"; no "No notes dated…" message; an editor sees the empty Summary box as today | | |
| ☐ | X3 | Default currency without rates | Developer saves the Flipkart widget with `currency: 'SGD'` | 1. Open the dashboard | Cards in INR (the firm's currency); no error | | |

---

## UI Journeys

Journey 1: setting up a stats widget (design [What users see](design.md#what-users-see)).

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Widget Configuration › Fields (①) | Click the box, type "fm" | Searchable list narrows to FMV and Sold + FMV | | |
| ☐ | J1.2 | Fields | Pick two cards, then remove the first chip | Chips update; order of the remaining chip kept | | |
| ☐ | J1.3 | Field names (②, ③) | Read the hint | Hint text as in H3 | | |

Journey 2: Summarise Notes (design [card ⑦](design.md#-run-window-and-run-message), [card ⑧](design.md#-note-summaries-entry)).

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J2.1 | Notes widget | Click Summarise Notes | Window with the description and the period line | | |
| ☐ | J2.2 | Window | Click Cancel | Window closes; no message; nothing queued | | |
| ☐ | J2.3 | Window | Open again, click Run Summariser | Page message as in H11 | | |
| ☐ | J2.4 | Note Summaries | Reload, expand the entry | Period, Notes processed, and either the summary or the empty-period message | | |

---

## Role Sweep

✓ = allowed and works, ✗ = correctly blocked, ! = wrong.

| ID | Screen / action | Fund admin (Meera) | Employee without widget edit | Investor / LP (Ravi) | Other-entity user |
|---|---|---|---|---|---|
| R1 | Edit stats / Data Card widget settings | ✓ | ✗ (as today) | ✗ | ✗ |
| R2 | See stats widgets with settings applied | ✓ | ✓ | ✓ (fund: folio totals only) | ✗ |
| R3 | Summarise Notes window and Run | ✓ | ✓ if they can see the company's notes (as today) | ✗ (no button) | ✗ |
| R4 | See Note Summaries entry | ✓ | ✓ (as today) | ✗ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts sent by this feature arrive | N/A: no emails. Only the on-page message after Run | | |
| ☐ | C2 | Dates on changed screens | Period dates as "Jul 01, 2026"; summary note date as "30/09/2026" | | |
| ☐ | C3 | Narrow / mobile width | Settings form multi-select usable; stats cards stack; no horizontal scroll | | |
| ☐ | C4 | Tenant isolation | Another entity's user cannot open these widgets' edit pages or run the summariser on Flipkart Unlisted, even with a direct URL | | |
| ☐ | C5 | Regression on modified screens | Portfolio Investments page cards unchanged; Aggregated Portfolio Dashboard "Stats" unchanged; Kpis / Documents widget settings still save; other agents' Run buttons (e.g. CP/CS on a portfolio investment) still show their progress panel | | |
| ☐ | C6 | Empty states | Stats widget with no portfolio investments shows ₹0 cards as before; Note Summaries with no runs shows its usual empty state | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
