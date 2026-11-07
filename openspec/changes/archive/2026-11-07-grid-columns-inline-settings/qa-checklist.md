# Table columns and custom fields in place — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md) · [Business rules](business-rules.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail, put the defect
> link in Notes. Row IDs match [business-rules.md](business-rules.md) (H/E/X) and the design's journeys (J), so a
> failure maps straight to the automated test that should have caught it.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey step (J2.3 =
journey 2, step 3) · **R** = Role sweep · **C** = Cross-cutting check

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
| Environment | Staging (staging_in) |
| Accounts | Meera — company admin of Demo Capital; Ravi — Demo Capital employee (no company admin); Sam — CapHive support with company admin; an LP user of Demo Capital |
| Second entity | Other Capital, with its own admin, an investor and a report "Other LPs" with columns |
| Seed data | Fund "Growth Fund I"; investors Ravi Menon (Mumbai, HNI) and Acme Family Office (Bengaluru, FO); Investor form type "Default" with Risk rating (Select Low/Medium/High, required), Relationship manager (Text, internal), KYC due (Date), Net worth (Calculation); saved Investor columns Name, Category, City, Tags, Committed (remove them for rows that say "no saved columns"); report "LPs by city" with columns Name, City, Committed; a derived column "NAV / Commitment" on Investors for E1 |
| Background work | None — everything happens on Save |
| Tools | A second browser session (for E5, E18); browser dev tools to replay a request (for X rows; or ask a developer) |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Icon and columns list | Meera; saved Investor columns | 1. Open Investors 2. Point at the table 3. Click ▥ | Icon fades in on the table's top-right; panel "Investors columns", "Shared with everyone in your firm, on every Investors table"; Name, Category, City, Tags, Committed with types | | |
| ☐ | H2 | Edit and save in place | H1; search "Mumbai" | 1. Drag Committed above City 2. Rename Tags → Segment 3. ✕ City 4. Add Risk rating 5. Save | Table alone reloads: Name, Category, Committed, Segment, Risk rating; search still "Mumbai"; toast "Investors columns saved" | | |
| ☐ | H3 | First save keeps standard columns | No saved Capital Call columns | 1. Capital Calls › ▥ 2. Note the list matches the table 3. Add one column 4. Save | Table shows the same columns plus the new one, same order | | |
| ☐ | H4 | Form type created | Demo Capital has no Capital Call form type | 1. Capital Calls › ▥ › Save | Settings › Form Types now lists "CapitalCall" (Default) | | |
| ☐ | H5 | Report's own columns | — | 1. Open report "LPs by city" 2. ▥ 3. ✕ City 4. Save | Header "Columns of report 'LPs by city'"; report shows Name, Committed straight away; plain Investors table unchanged | | |
| ☐ | H6 | Reset | Saved Investor columns | 1. ▥ › Reset to standard columns 2. Read the warning 3. Save | Warning "Saving removes your firm's saved Investors columns, including derived fields"; table shows the page's standard columns | | |
| ☐ | H7 | Cancel / Esc | H1 | 1. ✕ City 2. Press Esc 3. Reopen ▥ | Panel closed; City still listed | | |
| ☐ | H8 | Firm-wide | After H2 | 1. Log in as Ravi 2. Growth Fund I › Investors tab | Same columns; no ▥ icon | | |
| ☐ | H16 | Configure Grids page | Saved Investor columns | 1. Settings › Form Types › Investor › Configure Grids | Same list as the panel in a card; Show / Edit / Delete on each saved row | | |
| ☐ | H17 | Save and delete on the full page | H16 | 1. Drag Category first, Save 2. Delete on City, confirm | Page refreshes with Category first; City gone | | |
| ☐ | H18 | Add a derived field | — | 1. ▥ › Add derived field: "RM", `custom_fields.relationship_manager`, String 2. Save | RM column with each investor's value | | |
| ☐ | H19 | Funds list unchanged by default | No saved Fund columns | 1. Open Funds | Same columns, links, Actions as before; ▥ beside the search box | | |
| ☐ | H20 | Add a column to Distributions | Custom field Tranche on a distribution | 1. Distributions › ▥ › add Tranche › Save | Tranche column with values | | |
| ☐ | H9 | AG grid columns | — | 1. Capital Commitments › grid view 2. ▥ 3. Add a column 4. Save | Icon on the grid; only the grid reloads with the column | | |
| ☐ | H10 | Fields icon and list | Meera | 1. Investors › Ravi Menon 2. Point at the details card 3. Click 🗎 | Icon on the card's corner; panel "Investor fields · Default", "Shared by every investor on the Default form type"; Risk rating, Relationship manager, KYC due, Net worth in order | | |
| ☐ | H11 | Edit fields and save | H10 | 1. Drag KYC due first 2. Rename Relationship manager → RM 3. Read only on Risk rating 4. ⌄ help "From the onboarding review" 5. Add Source of funds, Select, "Salary, Business, Inheritance" 6. Save | Page refreshes in place, same scroll position; card shows KYC due, Risk rating, RM; toast "Investor fields saved" | | |
| ☐ | H12 | Shared by the form type | After H11 | 1. Acme Family Office › Edit | "Source of funds" select with the 3 options | | |
| ☐ | H13 | Form type created and linked | A valuation with no form type; no Valuation form type | 1. Open the valuation 2. 🗎 3. Add "Method note" 4. Save | Settings › Form Types lists a Valuation form type with Method note; the valuation's edit form shows Method note | | |
| ☐ | H14 | Remove a field | Ravi Menon KYC due 31/03/2027 | 1. 🗎 2. ✕ KYC due 3. Read the warning 4. Save 5. Re-add a field labelled "KYC due" | Warning "Removed fields disappear from forms and pages; values already entered stay stored."; KYC due gone; after re-adding, 31/03/2027 shows again | | |
| ☐ | H15 | Fields Cancel / Esc | H10 | 1. Rename Risk rating 2. Esc 3. Reopen | Unchanged | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Derived column | Derived "NAV / Commitment" | 1. Rename it "NAV ratio" 2. Drag it first 3. Save | Same values, first, heading "NAV ratio"; Configure Grids shows the same key and data type | | |
| ☐ | E2 | Always-shown columns | — | 1. Capital Commitments (all funds) › ▥ | Fund and Stakeholder show "Always shown", cannot be dragged or removed | | |
| ☐ | E3 | Hidden on this page | Saved commitment columns include Investor | 1. Ravi Menon › Commitments tab › ▥ 2. Save | Investor shows "Not shown on this page"; still listed after reopening on the all-funds list | | |
| ☐ | E4 | Report without own columns | A report with no columns | 1. Open it › ▥ | Header names the firm's columns; saving changes the plain Investors table too | | |
| ☐ | E5 | Column removed meanwhile | Two browsers as Meera | 1. Browser A opens ▥ 2. Browser B removes City and saves 3. Browser A saves with City | Save succeeds; City absent | | |
| ☐ | E6 | Double click | — | 1. Double-click Save | No duplicate columns | | |
| ☐ | E7 | Blank heading | — | 1. Clear Category's heading 2. Save | Heading "Category" | | |
| ☐ | E8 | Duplicate in list | Developer-assisted request | 1. Replay a save listing City twice | City appears once | | |
| ☐ | E9 | Table in a tab | — | 1. Growth Fund I › Commitments tab › ▥ › Save | Only the tab's table reloads; tab stays open | | |
| ☐ | E10 | Related record field | — | 1. Capital Commitments › ▥ › add an investor field 2. Save | Column shows investor values | | |
| ☐ | E11 | Snapshot column | Snapshot view available | 1. Commitments snapshot view › ▥ | "Snapshot Date" not in the list | | |
| ☐ | E23 | Data type and alignment | — | 1. ⌄ on Committed: Decimal, right 2. Save | Committed cells right-aligned | | |
| ☐ | E24 | Derived key edit | Derived NAV / Commitment | 1. ⌄ change its key 2. Save | Values of the new key | | |
| ☐ | E25 | Page without a search box | — | 1. Open a table with `hide_search=true` | ▥ visible at the table's top-right | | |
| ☐ | E26 | Second form type | "Feeder" commitment form type | 1. Configure Grids on Feeder 2. Add a column 3. Save | Only Feeder changes | | |
| ☐ | E27 | Report page | Report without columns | 1. Report page › Configure Grids 2. Save | Panel listed standard columns; report now has its own | | |
| ☐ | E28 | Search and sort after customising | After H20 | 1. Type "Dec" in Search: 2. Sort by Name | Filters and sorts as before | | |
| ☐ | E29 | Configure Grids offered | — | 1. Form Types › Capital Distribution | Configure Grids button present | | |
| ☐ | E30 | Every converted list renders | One record each | 1. Open each of the 14 lists | Renders with ▥; no errors | | |
| ☐ | E12 | AG grid column rules | Saved commitment columns include Investor | 1. Ravi Menon › Commitments grid › ▥ › Save | Investor "Not shown on this page"; Fund locked | | |
| ☐ | E13 | Record without a form type | An investor with no form type | 1. 🗎 2. Add a field 3. Save | Panel showed Default's fields; investor now shows "Form Type: Default" | | |
| ☐ | E14 | Calculation locked | Meera | 1. 🗎 | Net worth shows "Support"; no toggles, no ✕, name not editable | | |
| ☐ | E15 | Support renames a calculation | Sam | 1. 🗎 2. Rename Net worth → "Net worth (₹)" 3. Save | Label changed; value unchanged | | |
| ☐ | E16 | Regulatory fields | A KYC with SEBI fields | 1. KYC page › 🗎 › Save | SEBI fields not listed; KYC form shows them where they were | | |
| ☐ | E17 | Rename keeps data | KYC due 31/03/2027 | 1. Rename to "KYC review date" 2. Save | Card shows "KYC review date 31/03/2027" | | |
| ☐ | E18 | Field removed meanwhile | Two browsers | 1. A opens 🗎 2. B removes KYC due, saves 3. A renames KYC due, saves | Save succeeds; KYC due stays removed | | |
| ☐ | E19 | Reporting fields list | A page with a reporting fields list | 1. Open it, point at the list | No 🗎 icon there | | |
| ☐ | E20 | Money field | — | 1. Add "Ticket size" as Money 2. Save 3. Edit an investor | Money input in INR | | |
| ☐ | E21 | Second form type | A commitment on form type "Feeder" | 1. Commitment page › 🗎 | Header "Capital commitment fields · Feeder"; save changes only Feeder | | |
| ☐ | E22 | Double click on fields Save | — | 1. Add Source of funds 2. Double-click Save | One Source of funds field | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Non-admin (columns) | Ravi | 1. Open Investors 2. Replay a settings and a save request | No icon; both refused; columns unchanged | | |
| ☐ | X2 | Acting as investor (columns) | Meera switched to investor role | 1. Open a table 2. Replay settings | No icon; refused | | |
| ☐ | X3 | Another firm (columns) | Developer-assisted | 1. Replay a save naming "Other LPs" | Refused; Other Capital's columns unchanged | | |
| ☐ | X4 | Forged column | Developer-assisted | 1. Replay a save adding `entity.users` | "entity.users cannot be added"; nothing saved | | |
| ☐ | X5 | Tampered / expired panel | Developer-assisted | 1. Alter the panel link's context 2. Or wait 13 h and save | Not found; nothing saved | | |
| ☐ | X6 | Empty list | — | 1. ✕ every column 2. Save | "Keep at least one column"; nothing saved | | |
| ☐ | X7 | Report not editable | Another user's draft report | 1. Replay a save for it | Refused | | |
| ☐ | X8 | Extra fields (columns) | Developer-assisted | 1. Replay a save adding entity, owner, data type | Only columns, headings, order changed | | |
| ☐ | X9 | Unknown record type (columns) | Developer-assisted | 1. Replay settings for a type without standard columns | Not found | | |
| ☐ | X19 | Invalid data type | Developer-assisted | 1. Replay a save with data type `Ruby` | "Ruby is not a data type"; nothing saved | | |
| ☐ | X20 | Other firm's Configure Grids | Developer-assisted | 1. Open Configure Grids for Other Capital's form type | Refused | | |
| ☐ | X10 | Non-admin (fields) | Ravi | 1. Ravi Menon page 2. Replay settings and save | No icon; refused; form type unchanged | | |
| ☐ | X11 | Acting as investor (fields) | Meera as investor | 1. Replay settings | Refused | | |
| ☐ | X12 | Another firm's record | Developer-assisted | 1. Replay settings and save for Other Capital's investor | Refused; their form type unchanged | | |
| ☐ | X13 | Duplicate name | H10 | 1. Add "Risk rating" 2. Save | "A field named Risk rating already exists"; nothing saved | | |
| ☐ | X14 | No label | — | 1. Click Add with an empty label | Field not added; label box asks for a label | | |
| ☐ | X15 | Select without options | — | 1. Add a Select with no options 2. Save | "Add at least one option"; nothing saved | | |
| ☐ | X16 | Calculation guarded | Meera; developer-assisted | 1. Replay a save renaming and removing Net worth | Net worth unchanged | | |
| ☐ | X17 | Extra fields (fields) | Developer-assisted | 1. Replay a save adding entity, form type name, a condition and options of an existing field | Only labels, flags, help, order, additions, removals changed | | |
| ☐ | X18 | Unknown record type (fields) | Developer-assisted | 1. Replay settings with type `Kernel` | Not found | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Investors table | Look at the search row | ① ▥ visible right of the search box, same height | | |
| ☐ | J1.2 | Investors table | Click ▥ | ② panel slides in from the right; ③ rows with drag handles, chips, ⓘ tooltips that show above the panel | | |
| ☐ | J1.3 | Columns panel | Edit and click Save | Spinner on Save; panel closes; table shimmers; toast | | |
| ☐ | J1.4 | Columns panel | Click ↗ | The full Configure Grids page for that record type | | |
| ☐ | J2.1 | Record page | Point at the details card | ① 🗎 fades in on the card's corner | | |
| ☐ | J2.2 | Record page | Click 🗎 | ② panel; ③ rows with ✱ 🔒 👁̸ toggles, ⌄ help, ✕ / ↶ | | |
| ☐ | J2.3 | Fields panel | Edit and Save | Spinner; page refreshes in place, scroll kept; toast | | |
| ☐ | J2.4 | Fields panel | Click ↗ | Form Types › Edit opens | | |

---

## Role Sweep

| ID | Screen / action | Company admin (Meera) | Employee (Ravi) | Acting as investor / LP | Other-entity admin | Support (Sam) |
|---|---|---|---|---|---|---|
| R1 | ▥ icon on a table | ✓ | ✗ | ✗ | ✗ (on Demo's data) | ✓ |
| R2 | Open / save columns panel | ✓ | ✗ | ✗ | ✗ | ✓ |
| R3 | Report columns | ✓ (own / editable reports) | ✗ | ✗ | ✗ | ✓ if editable |
| R4 | 🗎 icon on a record page | ✓ | ✗ | ✗ | ✗ | ✓ |
| R5 | Open / save fields panel | ✓ | ✗ | ✗ | ✗ | ✓ |
| R6 | Change a calculation field | ✗ (locked) | ✗ | ✗ | ✗ | ✓ (label / order) |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts | N/A — the feature sends none | | |
| ☐ | C2 | Dates on changed screens | Date fields on record pages still in the locale format (e.g. `31/03/2027` for en) | | |
| ☐ | C3 | Narrow / mobile width | Panel fills the screen width; icons visible (quieter) on touch screens | | |
| ☐ | C4 | Tenant isolation | Other Capital's admin cannot open or save Demo Capital's columns or fields, even with a direct URL | | |
| ☐ | C5 | Regression | Report builder Columns tab drag-reorder still saves; Form Types › Edit still saves; dashboard widget settings panel still works | | |
| ☐ | C6 | Empty states | Columns panel never empty (Save refused); fields panel on a form type with no fields shows "No custom fields yet — add one below" | | |
| ☐ | C7 | Looks like the rest of CapHive | Both panels match the dashboard widget settings panel | | |
| ☐ | C8 | No full page reloads for small actions | Columns save reloads the table only; fields save keeps the scroll position | | |
| ☐ | C9 | Explains itself | ⓘ tooltips on "Shown columns", "Add a column", "Fields", "Add a field"; chips and toggles have titles | | |
| ☐ | C10 | Speed on a large entity | Panel opens in under ~1 s; table reload under ~2 s on the largest entity | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
