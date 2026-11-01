# Report Builder you can trust — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X) and UI journeys
> (J), so a failure maps straight to the automated test that should have caught it.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey
step (J1.3 = journey 1, step 3) · **R** = Role sweep · **C** = Cross-cutting check

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
| Accounts | **Meera**: Acme Capital employee who can create/edit reports · **Arjun**: Acme Capital employee who can view reports |
| Second entity | **Omar**: user in Beta Partners |
| Seed data | As in the design's shared setup: funds Growth Fund II (INR) and Global Fund (USD); investors Aditi Rao, Kiran Mehta, Zeta Holdings, Nova LP; commitments C1–C4 with the amounts listed there; calls "Call 1 — GF2" and "Call 2 — GF2"; remittances R1–R4 (R2 on Call 2); payments P1 (UTR001) and P2 (UTR002); KYC names "Aditi Rao Family Trust" and "Mehta HUF"; fund units; distribution payment DP1; one KPI report for "Orbit Labs" |
| Report "LPs" | Investor report; related data *Capital commitments* with the related filter Fund = Growth Fund II; columns Stakeholder, Category, Committed, Called, Collected |
| Background work | Excel export runs in the background; wait for the "Your report … is ready" alert, then click its link |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Fund name on a commitment report | Meera | 1. New Capital Commitment report 2. Add related *Fund* 3. Add its Name 4. Refresh Preview | C1–C3 show "Growth Fund II"; C4 shows "Global Fund" | | |
| ☐ | H2 | Call name on a payment report | Meera | 1. New Capital Remittance Payment report 2. Add related *Capital call*, Name 3. Preview | P1 shows "Call 1 — GF2"; P2 shows "Call 2 — GF2" | | |
| ☐ | H3 | Funds through commitments | Meera | 1. New Investor report 2. Add related *Capital commitments › Fund* (Drill Down), Name, total List 3. Preview | Aditi: "Global Fund, Growth Fund II"; Kiran: "Growth Fund II" | | |
| ☐ | H4 | Two-step next to first-level | H3 | 1. Also add Committed from Capital commitments 2. Preview | Kiran shows 2,50,00,000.00 and "Growth Fund II" | | |
| ☐ | H5 | Documents count only own | Meera | 1. Capital Commitment report 2. Add related Documents, count 3. Preview | C1 shows 1 | | |
| ☐ | H6 | Investing Entity | Meera | 1. Capital Remittance report 2. Add Investing Entity 3. Preview | R1 shows "Aditi Rao Family Trust" | | |
| ☐ | H7 | Committed gets Sum | Report "LPs" | 1. Add Committed again from a fresh report (Investor + Capital commitments) 2. Look at its total | Total shows **sum**; Aditi 5,00,00,000.00 | | |
| ☐ | H8 | Ratio formula | Meera | 1. Capital Commitment report with Committed and Called 2. Add Formula `ROUND([committed_amount] / [call_amount], 2)` 3. Preview | C1 shows 2.50 (no ₹) | | |
| ☐ | H9 | Own minus related | Meera | 1. Capital Commitment report, related Capital remittances › Collected (Sum) 2. Formula `[committed_amount] - [capital_remittances.collected_amount]` | C1 shows 3,20,00,000.00 | | |
| ☐ | H10 | Formula stays where dragged | "LPs" + formula Called % | 1. Drag Called % to just after Called 2. Preview 3. Open report page 4. Export | Called % immediately after Called in all three | | |
| ☐ | H11 | Pivot block moves | Investor report, commitments pivot by Unit Type | 1. Drag the pivot row to position 2 2. Preview | Pivot columns A and B appear together from column 2 | | |
| ☐ | H12 | Pivot header names | Investor report: commitments pivot by Unit Type and fund units pivot by Unit Type | Preview | Headers "Capital commitments · A (sum)" and "Fund units · A (sum)" | | |
| ☐ | H13 | Only investors that have commitments | Report "LPs" | 1. Turn on **Only investors that have capital commitments** 2. Preview | Nova LP gone; "All 3 rows" | | |
| ☐ | H14 | Only rows + related filter | Investor report with Capital remittances, related filter Status = Overdue | 1. Turn on the switch 2. Preview | Only Aditi Rao | | |
| ☐ | H15 | Same look in preview and page | Report with Committed, Commitment date, Onboarding completed | 1. Preview 2. Open report page | Same text in both: "5,00,00,000.00", date in your format, "Yes"; numbers right-aligned | | |
| ☐ | H16 | Excel cell types | Same report | Export and open in Excel | Committed is a number (sums with Excel's AutoSum); date is a date; "Yes" | | |
| ☐ | H17 | Totals | Report "LPs" | Open report page | Total Committed 8,50,00,000.00 | | |
| ☐ | H18 | Called % total | "LPs" + Called % | Open report page | Total Called % 40.00 | | |
| ☐ | H19 | Excel totals row | "LPs" | Export | Last row bold totals; no "Totals" sheet | | |
| ☐ | H20 | Header sort | "LPs" | Click Committed header twice | Aditi, Kiran, Zeta; ▼ on Committed | | |
| ☐ | H21 | Name opens report | Reports list | Click "LPs" | The report page opens, not the editor | | |
| ☐ | H22 | Green only when saved | Builder | Change Default Sort | Green "Sort saved" | | |
| ☐ | H23 | Apply template asks | Builder with 5 columns | 1. Templates 2. Apply Template 3. Confirm | Popup "Immediate Actions" with cards; after confirming, the template's columns replace yours | | |
| ☐ | H24 | Preview count | Investor report with 25 investors | Preview | "20 of 25 rows"; totals labelled "Total (these 20 rows)" | | |
| ☐ | H25 | Wizard Summarize | Guided Wizard with Capital commitments | Add Committed on Summarize | Dropdown "Sum"; preview shows values | | |
| ☐ | H26 | Wizard change kept | H25 | Change to Count; reload the page | Still "Count" | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Missing parent | Document report | Add related Capital commitment › Folio | D3's cell empty; page fine | | |
| ☐ | E2 | Defaults by type | "LPs" | Add Commitment date, Onboarding completed, Unit type | Totals: Latest date, Any yes, Latest | | |
| ☐ | E3 | Old report column without total | A report saved before the release with Committed from commitments | Open report page | Values shown (summed) | | |
| ☐ | E4 | All yes | Investor report, Onboarding completed with Minimum, no fund filter | Preview | Aditi "No"; Zeta "Yes" | | |
| ☐ | E5 | Count of yes/no | Same with Count | Preview | Aditi 2 | | |
| ☐ | E6 | Divide by zero | Commitment report, formula `[call_amount] / [collected_amount]` | Preview | C3 empty; C1 1.11 | | |
| ☐ | E7 | Old report order | Report saved before the release with a formula and a pivot | Open report page | Pivot columns then the formula at the end, as before | | |
| ☐ | E8 | Remove formula | H10 | Remove Called % | No empty column left | | |
| ☐ | E9 | Clear pivot | H11 | Clear the pivot | No empty column left | | |
| ☐ | E10 | Remove related data with pivot | H11 | Remove Capital commitments | Pivot columns gone; no empty column | | |
| ☐ | E11 | Switch off by default | "LPs" | Preview | Nova LP present with 0.00 | | |
| ☐ | E12 | Filter-only field | Capital Distribution report | Look at columns, then filters | "Carry" not in columns; in filters | | |
| ☐ | E13 | Related columns stored only | Commitments added as related data | Look at its columns | No "Investing Entity" | | |
| ☐ | E14 | Every column works | Each table in New Report | Ask a developer to confirm the column drift test passed on this build | Passed | | |
| ☐ | E15 | Amounts not called "amount" | Distribution payment report: Gross Payable, Net Payable, Units quantity | Report page | "13,00,000.00", "12,34,567.00", "100.00", right-aligned | | |
| ☐ | E16 | Currency only on amounts | Fund units report with Display Currency INR | Report page | Amount "₹ 1,000.00"; Quantity "1,000.00" | | |
| ☐ | E17 | Non-summing totals blank | Report with Average, Latest, Min, Max, List columns | Report page | Their totals empty | | |
| ☐ | E18 | Page total | "LPs" with `per_page=2` in the address | Report page 1 | "Total (this page)" 7,50,00,000.00 | | |
| ☐ | E19 | No totals row | Investor report: Stakeholder, Category | Report page | No totals row | | |
| ☐ | E20 | Few rows | "LPs" | Preview | "All 4 rows"; "Total" | | |
| ☐ | E21 | Saved sort kept | After H20 | Meera opens the report | Saved order | | |
| ☐ | E22 | Sort across pages | H20 with `per_page=2` | Go to page 2 | Zeta, then Nova | | |
| ☐ | E23 | Large report note | Developer-assisted (cap lowered on a test build) | Sort by a related total | "Sorted within the first … rows" | | |
| ☐ | E24 | Other reports | A non-builder report on the list | Click its name | Opens as before | | |
| ☐ | E25 | Network error | Builder; switch the browser offline | Change sort | Red "Sort wasn't saved"; dropdown back to the saved value | | |
| ☐ | E26 | Template cancel | Builder with 5 columns | Apply Template, Cancel | Still 5 columns | | |
| ☐ | E28 | Funds through commitments default | "LPs" | Add Capital commitments › Fund › Name | Total is List | | |
| ☐ | E30 | Empty value in a total | Nova with switch off | Report page | Nova's cell empty; total unchanged | | |
| ☐ | E31 | Unpaid total | "LPs" + Unpaid = Called − Collected | Report page | Total Unpaid 60,00,000.00 | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Broken related path | Developer-prepared report with a removed association | Open report page | That column empty; rest fine | | |
| ☐ | X2 | Unknown total refused | Developer-assisted direct request | Set total "median" | Refused; total unchanged | | |
| ☐ | X3 | Refused save | Developer-assisted (forced invalid value) | Change sort | Red "Sort wasn't saved — …"; no green message; dropdown reverts | | |
| ☐ | X4 | Bad sort in the address | Report page | Add `?sort=not_a_column` | Saved order; no error | | |
| ☐ | X5 | Other entity | Omar | Open Acme's report page URL with `?sort=…` | Access refused | | |
| ☐ | X6 | Odd column type | Developer-prepared column | Report page and export | Shown as text; export completes | | |
| ☐ | X7 | Bad formula | Developer-prepared broken formula | Report page | Formula cells empty; page fine | | |
| ☐ | X8 | Other entity changes switch | Omar, developer-assisted request | Turn on only-with-rows on Acme's report | Refused | | |
| ☐ | X9 | Switch on one-per-row | Commitment report with Fund | Developer-assisted request for Fund | Refused; report unchanged | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Reports list → report | Click "LPs" | ① Report page with Edit and Export XLSX | | |
| ☐ | J1.2 | Report page | Click a header | ② Re-sorted; arrow on that header | | |
| ☐ | J1.3 | Report page | Read the bottom row | ③ "Total" or "Total (this page)" | | |
| ☐ | J1.4 | Report page | Next page | ④ Sort kept | | |

---

## Role Sweep

| ID | Screen / action | Meera (edit) | Arjun (view) | Omar (other entity) |
|---|---|---|---|---|
| R1 | Open report page, header sort | ✓ | ✓ | ✗ |
| R2 | Preview in builder | ✓ | as today | ✗ |
| R3 | Only-with-rows switch | ✓ | as today (edit rights) | ✗ |
| R4 | Change a total | ✓ | as today | ✗ |
| R5 | Apply template | ✓ | as today | ✗ |
| R6 | Export | ✓ | ✓ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts | Export-ready alert unchanged; a scheduled report email arrives with the new Excel (totals last row) and its dates in `Aug 19, 2026` form | | |
| ☐ | C2 | Dates on changed screens | Preview and report page dates follow the user's locale format (e.g. `19/08/2026` for en) | | |
| ☐ | C3 | Narrow / mobile width | Report page table scrolls inside its card; header arrows visible | | |
| ☐ | C4 | Tenant isolation | Omar cannot open, preview, export or change any Acme report, even by URL | | |
| ☐ | C5 | Regression | Builder add/remove column and join, pivot apply/clear, filters save, wizard steps, export still work | | |
| ☐ | C6 | Empty states | Report with no rows: "No data found matching your filters."; no totals row | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
