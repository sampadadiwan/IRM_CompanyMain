# Fix Portfolio Dashboard Widgets — Manual QA Checklist

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
| Environment | Staging build under test (note the URL in Sign-off) |
| Accounts | **Meera** — company admin of Acme Capital. **An Acme employee** — non-admin fund user. **Priya** — portfolio-company user of Flipkart Unlisted (sees Actual KPI reports only). **An LP** — investor user with a shared Flipkart page. |
| Second entity | **Beta Fund** admin (different entity from Acme), with a folder "Beta Board Pack" that has a document |
| Seed data | Acme Capital with a portfolio company **Flipkart Unlisted** (category Portfolio Company). KPI mappings: Revenue ("show in report" ticked), EBITDA (not ticked). KPI reports for Flipkart (Actual): 31 Jan 2022, 31 Oct 2025, 31 Mar 2026; plus a Budget report for 31 Mar 2026. Two portfolio investments in two funds (Fund A Equity, Fund B Preference). An Acme folder "Acme Shared Docs" (outside Flipkart's own folder) holding "Board Pack.pdf". On the **Portfolio Company Dashboard** (layout "Default") create three widgets, all Enabled: **Kpis** (position 1, tags "Kpis", Show Menu on), **Portfolio Investments** (position 2, tags "Portfolio Inv", Show Menu on), **Documents** (position 3, tags "Docs", Show Menu off). |
| Background work | None of these checks depend on background jobs. |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Menu lists only Show Menu widgets, in order | Seed widgets as in Test Setup | 1. Log in as Meera. 2. Open Flipkart Unlisted. | The page shows Kpis, Portfolio Inv and Docs. The menu links are "Kpis" then "Portfolio Inv"; there is no "Docs" link. | | |
| ☐ | H2 | A menu link takes you to its widget | As H1 | 1. Click the "Kpis" menu link. | The page moves to the Kpis widget. | | |
| ☐ | H3 | Compound is shown as Data-only view | A Kpis widget exists | 1. Go to Dashboard Widgets. 2. Edit the Kpis widget. 3. Look at Widget Configuration. | A field labelled **Data-only view** is shown (no "Compound"). Text beneath: "ON groups KPIs by category and shows data only (chart selection is off). OFF shows the full table with a plot checkbox per KPI." | | |
| ☐ | H4 | Show action buttons has helper text | As H3 | 1. On the same edit page find **Show action buttons**. | Text beneath: "ON shows the heading and the filter, chart and settings buttons above the table. OFF by default." | | |
| ☐ | H5 | Budget vs Actual offers only the default category | A Kpis Budget vs Actual widget exists | 1. Edit that widget. | No **Categories** field; **Default category** with a line of help beneath. | | |
| ☐ | H6 | Settings that do nothing are gone | A Kpis Performance Table, a Key Kpis, a Kpis and a Documents widget exist | 1. Edit each in turn and look at Widget Configuration. | Performance Table: no **Chart**. Key Kpis: no **Kpis**. Kpis: no **Show table**, **Show chart** or **Budget View**. Documents: no **Entity**. | | |
| ☐ | H7 | Key KPIs shows the flagged KPIs | A Key Kpis widget enabled; Mar 2026 report has Revenue and EBITDA | 1. Open Flipkart Unlisted. 2. Look at Key KPIs. | A **Revenue** card is shown; **EBITDA** is not. | | |
| ☐ | H8 | A whole-number ID is saved | A Documents widget exists | 1. Edit it. 2. Type 42 in **Folder ID**. 3. Save. 4. Reopen the edit page. | **Folder ID** shows 42. | | |
| ☐ | H9 | Documents shows a folder outside the company's own | Documents widget with the Folder ID of "Acme Shared Docs" and Enabled | 1. Open Flipkart Unlisted. 2. In the Documents widget, choose the folder **Acme Shared Docs** in its tree. | The Documents widget lists **Board Pack.pdf**. | | |
| ☐ | H10 | Month list comes from the reports | Performance Table widget enabled; reports Jan 2022, Oct 2025, Mar 2026 | 1. Open the Performance Table. 2. Open the month dropdown. | Options are exactly **Mar 2026, Oct 2025, Jan 2022**, in that order. **Mar 2026** is selected and its table is shown. | | |
| ☐ | H11 | Reach an old month in one step | As H10 | 1. Choose **Jan 2022**. | The Jan 2022 table is shown. The dropdown still lists all three months. | | |
| ☐ | H12 | Budget View is no longer offered | A Kpis widget exists | 1. Edit it and look at Widget Configuration. | No **Budget View** field; **Data-only view** and **Show action buttons** are there. | | |
| ☐ | H13 | Kpis widget shows the KPI grid | A Kpis widget; Mar 2026 report | 1. Open Flipkart Unlisted. | The KPI grid is shown. | | |
| ☐ | H14 | Group by column is a pick-list | A Portfolio Investments widget exists | 1. Edit it. 2. Open **Group by column**. | A drop-down list that includes **Instrument**, **Portfolio Company** and **Fund Name**. Text beneath: "Rows are grouped by this column. Choosing one uses the AG grid, whatever the Ag setting." | | |
| ☐ | H15 | Grouping works with AG Grid OFF | Portfolio Investments widget: **Ag = OFF**, **Group by column = Fund Name** | 1. Open Flipkart Unlisted. | The investments grid is shown, grouped by fund (Fund A, Fund B groups). | | |
| ☐ | H16 | Grouping works with AG Grid on Default | As H15 but **Ag = Default** | 1. Open Flipkart Unlisted. | Same grouped grid as H15. | | |
| ☐ | H17 | Defaults appear when nothing is configured | An entity with no widgets for this dashboard | 1. Open a company page as that entity's admin. | The default widgets are shown (Valuations, Fund Ratios, Kpis, Data Card, …) and the menu lists them. | | |
| ☐ | H18 | Enabled widgets with no Show Menu | Seed widgets; untick Show Menu on Kpis and Portfolio Inv | 1. Open Flipkart Unlisted. | Kpis and Portfolio Inv (and Docs) are shown. No menu row is drawn. | | |
| ☐ | H19 | Kpis action buttons are off by default | A Kpis widget with no Show action buttons setting | 1. Open Flipkart Unlisted. | The KPI grid has no heading and no filter, Saved Charts or settings buttons above it. | | |
| ☐ | H20 | Show action buttons ON | A Kpis widget saved with **Show action buttons** ON | 1. Open Flipkart Unlisted. | The heading and the filter, Saved Charts and settings buttons are above the grid. | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Every widget disabled gives defaults | Untick **Enabled** on all three seed widgets | 1. Open Flipkart Unlisted. | Default widgets on the page and in the menu. | | |
| ☐ | E2 | The reported bug: one widget, Show Menu off | Only Kpis enabled, Show Menu unticked | 1. Open Flipkart Unlisted. 2. Look at the top bar. | Only Kpis is on the page. No menu row is drawn (no Valuations, Fund Ratios, … links). | | |
| ☐ | E3 | A disabled widget never appears | Kpis enabled; Portfolio Inv **disabled** with Show Menu ticked | 1. Open Flipkart Unlisted. | Portfolio Inv is neither on the page nor in the menu. | | |
| ☐ | E4 | Menu row hides Reports and layout selector too (accepted) | A Report is tagged for this dashboard and Acme has a second layout; no widget has Show Menu | 1. Open Flipkart Unlisted. | No menu row: no widget links, no **Reports** drop-down and no layout selector. The company logo/title heading (if any) is still shown. This is the accepted limitation. | | |
| ☐ | E5 | Multi-portfolio dashboard follows the same rules | Multi-portfolio widgets enabled, none with Show Menu | 1. Open the multi-portfolio dashboard. | No menu row; default widgets are not added. | | |
| ☐ | E6 | LP company page follows the same rules | An LP layout "LP" with enabled widgets, none with Show Menu | 1. Log in as the LP. 2. Open the shared Flipkart page. | The widgets show; no menu row; the default catalogue is not used. | | |
| ☐ | E7 | Widgets hidden by tags show nothing | Kpis enabled with Tag List "Ecom"; Flipkart tagged "AI" | 1. Open Flipkart Unlisted. | Empty page; default widgets are not shown. | | |
| ☐ | E8 | A saved Compound setting still works | A Kpis widget saved earlier with Compound ON | 1. Open the page. 2. Edit the widget. | The page shows the grouped, data-only view. The edit page shows **Data-only view** = ON. | | |
| ☐ | E10 | Letters are refused in ID fields | Documents edit page | 1. Click **Folder ID**. 2. Type e12. | The field shows only 12. | | |
| ☐ | E11 | Pasting mixed text keeps only digits | Documents edit page | 1. Paste 1.5e3 into **Owner ID**. | The field shows only digits. | | |
| ☐ | E12 | Company with no KPI report | A portfolio company with no KPI reports and a Performance Table widget | 1. Open its page. | The message "No KPI reports have been uploaded for this company yet." The month dropdown has no choices. | | |
| ☐ | E13 | A month with no report | Reports for Jan 2022 and Mar 2026 only | 1. Open the table for Feb 2026 (use a link or ask a developer for the URL). | The message "No KPI report found for the specified date. Try any of the dates below" with links for Mar 2026 and Jan 2022. | | |
| ☐ | E14 | You only see months you may view | Priya (Actual only); Oct 2025 report tagged Budget | 1. Log in as Priya. 2. Open the Performance Table dropdown. | Mar 2026 and Jan 2022 are listed; Oct 2025 is not. | | |
| ☐ | E15 | An old Budget View widget shows the grid | A Kpis widget saved earlier with Budget View ON and Compound ON | 1. Open the page. | The KPI grid (data-only because of Compound). | | |
| ☐ | E16 | No group column | Portfolio Investments **Ag = OFF**, no Group by column | 1. Open the page. | The aggregate table (as before this change). | | |
| ☐ | E17 | A saved list of group columns is kept | A widget saved with Group by column "fund_name, investment_instrument_name" (ask a developer) | 1. Edit the widget. 2. Save. 3. Check Raw Metadata. | The drop-down shows that value as the current choice. After saving, Raw Metadata still holds the same value. | | |
| ☐ | E18 | Two reports in one month list the month once | Mar 2026 has an Actual and a Budget report | 1. Open the Performance Table dropdown. | **Mar 2026** appears once. | | |
| ☐ | E19 | A report dated mid-month | A report dated 15 Mar 2026 | 1. Choose Mar 2026 in the dropdown. | The table for that report is shown (not "No KPI report found"). | | |
| ☐ | E20 | Same folder once shared with the investor | As X3, then share the folder and its documents with the portfolio company | 1. Reload the page as the investor user. | The widget lists **Board Pack.pdf**. | | |
| ☐ | E21 | Documents widget viewed by an employee who is not a company admin | An employee of Acme without the company admin role; Documents widget (in Acme) with the Folder ID of "Acme Shared Docs" | 1. Log in as that employee. 2. Open Flipkart Unlisted. | The widget lists **Board Pack.pdf** without choosing the folder. | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Documents widget with another entity's folder | Documents widget with the Folder ID of Beta's "Beta Board Pack" | 1. Log in as Meera. 2. Open Flipkart Unlisted. | The widget says "No documents to show."; the Beta folder's name and documents are not shown; no error is raised to anyone. | | |
| ☐ | X3 | Documents widget with a company folder not shared with an investor user | An investor user of the portfolio company; Documents widget (in that user's entity) with the Folder ID of "Acme Shared Docs", not shared with them | 1. Log in as that investor user. 2. Open Flipkart Unlisted. | The widget says "No documents to show."; the folder name and its documents are not shown. | | |
| ☐ | X2 | Direct link to a report you may not see | Priya; Oct 2025 report tagged Budget | 1. Log in as Priya. 2. Open the Performance Table link for Oct 2025 by URL (ask a developer for it). | You do not see that report's data; the normal "not authorised" behaviour of the app applies. | | |

---

## UI Journeys

**Journey 1 — viewing the company page**

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Company page | Open Flipkart Unlisted | The widgets and a menu of only the Show Menu widgets (④ in the design wireframe) | | |
| ☐ | J1.2 | Company page menu | Click a menu link | The page moves to that widget | | |
| ☐ | J1.3 | Kpis Performance Table | Open the month dropdown | Every report month, latest selected (⑤) | | |

**Journey 2 — setting up widgets (admin)**

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J2.1 | Dashboard Widgets › Edit (Kpis) | Open Widget Configuration | **Data-only view** and **Show action buttons** each with a line of help; no Show table / Show chart / Budget View | | |
| ☐ | J2.2 | Same | Set Show action buttons ON, tick Enabled and Show Menu, Save | The widget saves; the list shows it Enabled | | |
| ☐ | J2.3 | Dashboard Widgets › Edit (Portfolio Investments) | Pick **Fund Name** under Group by column; leave Ag on Default; tick Enabled; untick Show Menu; Save | Saves; the pick-list showed the grid's columns | | |
| ☐ | J2.4 | Dashboard Widgets › Edit (Documents) | Type e12 in **Folder ID** | The field shows 12 | | |

---

## Role Sweep

✓ = allowed and works, ✗ = correctly blocked, ! = wrong. Everything is "as before this change" except the items under test.

| ID | Screen / action | Fund admin | Fund employee | Portfolio-company user | LP | Other-entity user |
|---|---|---|---|---|---|---|
| R1 | Open the company page and see the menu per the three rules | ✓ | ✓ | ✓ (their company) | ✓ (LP layout only) | ✗ |
| R2 | Edit a widget (new labels, help, whole-number fields) | ✓ | as before | ✗ | ✗ | ✗ |
| R3 | Performance Table month list | ✓ all months | ✓ all months | ✓ Actual months only | ✓ Actual months for their fund only | ✗ |
| R4 | Documents widget with a Folder ID of another entity | no documents | no documents | no documents | no documents | no documents |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts | N/A — this change sends none | | |
| ☐ | C2 | Dates on changed screens | The month dropdown shows the same "Mon YYYY" style as before (for example "Mar 2026") | | |
| ☐ | C3 | Narrow / mobile width | The company page and the widget edit form have no horizontal scroll; the menu links remain reachable | | |
| ☐ | C4 | Tenant isolation | A Beta Fund user cannot see Acme's widgets, KPI months or documents, even by direct URL | | |
| ☐ | C5 | Regression on modified screens | Company page, Fund and Investor dashboards (menu), widget edit form, Performance Table, Kpis grid, Budget vs Actual widget, Documents widget and Portfolio Investments widget still work as before | | |
| ☐ | C6 | Empty states | A company with no KPI reports and a dashboard with no widgets both show a clear message or the defaults, not a blank error | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
