# Portfolio Report Combined Packet — Manual QA Checklist

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
| Environment | Staging, build with this change deployed; the background worker for the low-priority queue is running |
| Accounts | **Meera** (fund admin, can manage portfolio reports) · **Esha** (employee without Fund Portfolios access) · **Ines** (investor / LP user) · **Omar** (fund admin of a different entity, "Other Fund") |
| Second entity | "Other Fund" with Omar, its own portfolio company and its own report, used for isolation checks |
| Seed data (Alpha Ventures) | Portfolio companies **Ace Limited**, **Beta Corp**, **Gamma Corp** (create them in the order Gamma, Ace, Beta). Ace and Beta have KPI data and investments. Gamma has no KPI data and no logo |
| Reports | **Analyst Report** (normal, with sections; template **Company One-Pager**, 1 page; extracts already generated for Ace and Beta only). **Portfolio Overview** (tick **Consolidated**; template **Cover and Summary**, 2 pages, lists every company's name and its IRR in each fund). **Disclaimer** (tick **Consolidated**; template **Legal Disclaimer**, 1 page, no merge fields). Ask a developer for the three Word templates if you do not have them |
| Extract data | **Delta Inc**: a portfolio company with notes dated in the period and Revenue KPIs in its latest KPI report in the period (plus an older report with a Headcount KPI), and **no documents** on its KPI reports. **Ace Limited**: extracts for the Analyst Report ending Q1 and Q2 with data, and a newer Q3 extract with no data (use Edit Data to clear it, or ask a developer). Ask a developer for a company with no documents, notes or KPIs at all (**Nova Ltd**) |
| Period | Start 2026-01-01, End 2026-09-30 |
| Background work | After **Generate Report** or **Generate Extracts Only**, wait for the completion message at the top of the screen (up to a few minutes). If none appears after 10 minutes, ask a developer to check the low-priority queue |
| Where files land | Each company's report: the company's folder › Portfolio Reports. The combined file: Documents › Portfolio Reports › Generated Portfolio Reports |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Tick Consolidated | Meera, new report form | 1. Portfolio Reports › New. 2. Name "Portfolio Overview". 3. Tick **Consolidated**. 4. Save. 5. Open Edit | The report is saved; **Consolidated** is ticked on Edit | | |
| ☐ | H2 | Companies appear A to Z in a consolidated report | Seed data above | 1. Bulk Generate (Legacy). 2. Select Ace, Beta, Gamma, **Next**. 3. Single row: Portfolio Overview / Cover and Summary. 4. Dates as above, **Generate Report**. 5. Open the saved file from the message | The cover lists Ace Limited, Beta Corp, Gamma Corp in that order, each once | | |
| ☐ | H3 | Each company shows its own figures | As H2, with Ace and Beta each invested in a fund with an IRR run | Read the IRR shown for Ace and Beta in the cover | Each value matches that company's IRR in the fund on its own one-company report for the same period | | |
| ☐ | H4 | No extracts needed | No extracts exist for Portfolio Overview | After H2, open Portfolio Reports › Extracts (or the report's extract list) | No extract was created for Portfolio Overview for any company | | |
| ☐ | H5 | Three-row list gives one combined file | Seed data | 1. Bulk Generate, select the 3 companies, **Next**. 2. Row 1: Portfolio Overview / Cover and Summary. 3. **Add report**: Analyst Report / Company One-Pager. 4. **Add report**: Disclaimer / Legal Disclaimer. 5. Dates, **Generate Report**. 6. Wait for the message, open the link | Message "Queued report generation for 3 companies." then a completion message linking to "Cover and Summary 2026-01-01 to 2026-09-30 - 3 companies" in Portfolio Reports › Generated Portfolio Reports. The file reads: cover (2 pages), Ace, Beta, Gamma one-pagers, disclaimer = 6 pages. Each company's own one-pager is in its folder. No separate file exists for the cover or the disclaimer | | |
| ☐ | H6 | One normal report is unchanged | Seed data | 1. Bulk Generate, select the 3 companies. 2. One row: Analyst Report / Company One-Pager. 3. Generate | Same as before this release: one combined file "… - 3 companies" with Ace, Beta, Gamma in that order, and each company has its own report | | |
| ☐ | H7 | Add and remove rows | Options page, 3 companies | 1. Note one row and no **Remove**. 2. **Add report** twice. 3. **Remove** row 2. 4. **Remove** until one row is left | 1 row → 3 rows → 2 rows; the last row has no **Remove** button | | |
| ☐ | H8 | Templates follow the row's report | Two reports with different templates | 1. Change row 1's report to another report. 2. Open its template list | Only that report's templates are listed and the first is selected; other rows unchanged | | |
| ☐ | H9 | Extracts Only on normal reports | Rows: Portfolio Overview and Analyst Report | Click **Generate Extracts Only** | "Queued extract generation for 3 companies." Extracts appear for Analyst Report; none for Portfolio Overview | | |
| ☐ | H10 | Consolidated label | Options page | Open the Report dropdown | "Portfolio Overview (Consolidated)" and "Disclaimer (Consolidated)" carry the suffix; "Analyst Report" does not | | |
| ☐ | H11 | Extract built without documents | Delta Inc (notes and KPIs, no documents) | 1. Bulk Generate, select Delta Inc, **Next**. 2. Row: Analyst Report. 3. **Generate Extracts Only**. 4. Open the extract | One amber warning at the end of the run: "Extracts built from notes and KPIs, no documents found:" followed by "No documents found for Delta Inc … Extract built from notes and KPIs." The extract has content drawn from the notes and the Revenue KPIs of the latest KPI report (nothing from the older Headcount report); it lists no source documents | | |
| ☐ | H12 | Widget skips a blank extract | Ace Limited with Q1 and Q2 extracts with data and a blank Q3 one | Open Ace Limited's dashboard with the portfolio report widget for Analyst Report | The widget shows the Q2 extract's content (not hidden) | | |
| ☐ | H13 | Delete an extract | An extract's details page | 1. Click **Delete**. 2. Confirm | You land on the report's extract list with "Portfolio report extract deleted successfully."; the extract is not in the list | | |
| ☐ | H14 | Preview with no match says so | The company step | Pick filters that match no company, click **Preview** | "No portfolio companies match the selected filters." is shown | | |
| ☐ | H15 | Fund totals row | Seed data; Ace, Beta, Gamma invested in one fund; the Cover and Summary template has a Grand Total row reading `fund_totals` | Generate as in H2 and read the Grand Total row | FMV and cost of investment equal the sum of the three companies' figures in that fund; Committed equals the sum of their `investment_commitment` | | |
| ☐ | H16 | Sections hidden when consolidated | The new report form | Tick **Consolidated**; untick it; tick it again and save with a name only | The Sections block and **Add Section** hide when ticked and show when unticked; the report saves with no section | | |
| ☐ | H17 | Normal report without a section | The new report form | Leave **Consolidated** unticked, give a name, leave the section blank and save | The report is saved with no section | | |
| ☐ | H18 | Report without sections is ready | A report with no section and one template | Open Portfolio Reports | The report shows **Ready**, and it is offered in Generate Reports | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Old reports stay normal | A report created before this release | Open its Edit page; generate it for one company | **Consolidated** unticked; generates as before | | |
| ☐ | E2 | Only a consolidated row | Seed data | One row: Portfolio Overview / Cover and Summary, Generate | A combined file "Cover and Summary … - 3 companies" with just the cover; no company one-pagers | | |
| ☐ | E3 | One normal report, one company | Seed data | Select only Ace; one row Analyst Report; Generate | No combined file; the message links to Ace's own report | | |
| ☐ | E4 | Company with no investments or logo | Gamma has none | Run H2 and read Gamma's entry | Gamma is listed with no fund lines; the file generates | | |
| ☐ | E5 | No extract, generate-missing off | Gamma has no extract; leave "Generate missing report extracts" unticked | Run H5 | Gamma's one-pager says "No data available". The message says "The following companies had no extract: Gamma Corp." and is not red | | |
| ☐ | E6 | Rows keep screen order after removals | Options page | Add 3 rows (4 in total), remove row 2, fill the rest, Generate | Final file follows the order of the rows left on screen | | |
| ☐ | E7 | Same report, two templates | Analyst Report has two templates; no extracts for one company; tick "Generate missing report extracts" | Rows 1 and 2: Analyst Report with template A then template B; Generate | Each company gets one extract for the report (check the extract list); both templates use it | | |
| ☐ | E8 | Old single-report form post | Ask a developer to post the earlier form fields | Submit with one report and one template, no row list | Queued as one row; completes as in H6 | | |
| ☐ | E9 | A run queued before release | Ask a developer to enqueue the job with the earlier arguments | Let it run | Completes as in H6 | | |
| ☐ | E10 | Regenerating | H5 already done | Repeat H5 with the same inputs | Each company's one-pager is replaced (no duplicate names in its folder); a second combined file is saved | | |
| ☐ | E11 | Different templates join cleanly | Cover and Company One-Pager are different Word templates | Open the combined file from H5 in Word | Opens without a repair prompt; all text and images visible; the look matches the cover | | |
| ☐ | E12 | KPIs alone are enough | A company with KPIs, no notes, no documents | Generate Extracts Only for it | Warning appears; extract has content from the KPIs | | |
| ☐ | E13 | Documents present: unchanged | Ace Limited has a KPI report with documents | Generate Extracts Only for it | No warning; extract as before this release | | |
| ☐ | E14 | Nothing at all | Nova Ltd | Generate Extracts Only for it | The extract is empty; Nova Ltd is reported in the red completion message as before (not the amber warning) | | |
| ☐ | E15 | Only blank extracts | A company whose every extract for the report is blank | Open its dashboard | The widget is not shown | | |
| ☐ | E16 | Deleted extract is regenerated when asked | H13 done for a company | Generate the report for it and the same period with "Generate missing report extracts" ticked; repeat unticked after deleting again | Ticked: a new extract is created. Unticked: the one-pager says "No data available" | | |
| ☐ | E17 | A fixed row clears its message | X2's message showing | Change the repeated row's template | The message disappears and **Generate Report** submits | | |
| ☐ | E18 | Cancel keeps the extract | An extract's details page | Click **Delete**, then cancel | The extract is still there | | |
| ☐ | E19 | Next needs a company | The company step | Look at **Next** with no company chosen; choose one; remove it | **Next** is disabled, then enabled, then disabled again | | |
| ☐ | E20 | One total per fund | Ace and Beta in fund Alpha, Gamma only in fund Beta; template without the fund-name check | Generate and read the Grand Total rows | Alpha is Ace + Beta; Beta is Gamma alone | | |
| ☐ | E21 | Blank custom field counts as zero | One company has no `investment_commitment` | Generate and read the Committed total | The total is the sum of the other companies' values; the blank company adds nothing | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Row without a template | A report with no template (or clear the template list by choosing such a report) | Select it in row 2, Generate | The page does not submit; "Choose a template for every report in the list." appears under row 2; no loading or reload happens | | |
| ☐ | X2 | Repeated template | Two rows with Company One-Pager | Generate | The page does not submit; "Each template can be used only once in a list. Remove the repeated template." appears under the repeated row | | |
| ☐ | X3 | Template from another report | Ask a developer to tamper a row's template | Generate | Taken back to the company step with "The selected template does not belong to the chosen report."; nothing queued | | |
| ☐ | X4 | Report from another entity | Ask a developer to post Other Fund's report id | Generate | Not found page; nothing queued | | |
| ☐ | X5 | Extracts Only, all consolidated | Rows: Portfolio Overview and Disclaimer | Click **Generate Extracts Only** | The page does not submit; "Consolidated reports don't use extracts, so there is nothing to generate." is shown | | |
| ☐ | X6 | A company's section fails | Ask a developer to make Beta's one-pager fail | Run H5 | Red message and error email name Beta Corp; the combined file still has the cover, Ace, Gamma and the disclaimer | | |
| ☐ | X7 | A consolidated part fails | Ask a developer to make Cover and Summary fail | Run H5 | Red message and email name "Cover and Summary (consolidated)"; combined file has the one-pagers and the disclaimer | | |
| ☐ | X8 | Everything fails | Ask a developer to fail every part | Run H5 | Red message and email; no combined file | | |
| ☐ | X9 | Joining fails | Ask a developer to make the join fail | Run H5 | Red message "Error merging portfolio report documents …" and email; each company's one-pager is still saved | | |
| ☐ | X10 | Company from another entity | Ask a developer to post Other Fund's company id with yours | Generate | The other entity's company is not generated; yours are | | |
| ☐ | X11 | No access | Esha (no portfolio access) | Open Bulk Generate (Legacy); try to reach the options step | Access refused; nothing queued | | |
| ☐ | X12 | Posted row without a template | Ask a developer to post a row with no template | Submit | Taken back to the company step with "Choose a template for every report in the list."; nothing queued | | |
| ☐ | X13 | Posted repeated template | Ask a developer to post one template in two rows | Submit | Taken back to the company step with "Each template can be used only once in a list. Remove the repeated template."; nothing queued | | |
| ☐ | X14 | Posted Extracts Only, all consolidated | Ask a developer to post it | Submit | Taken back to the company step with "Consolidated reports don't use extracts, so there is nothing to generate."; nothing queued | | |
| ☐ | X15 | Delete without permission | A user who is not a company admin | Ask a developer to send the delete request directly | The request is refused; the extract remains | | |
| ☐ | X16 | Another entity's extract | Omar and Alpha Ventures' extract link | Ask a developer to send Omar's delete for that id | Not found; the extract remains | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Portfolio Reports › Edit | Open an existing report | **Consolidated** checkbox, unticked, with the hint "One document for all selected companies. The template loops over every company. Sections and extracts are not used." | | |
| ☐ | J1.2 | Same | Tick it, Save, reopen | Ticked | | |
| ☐ | J2.1 | Bulk Generate (Legacy) › Options | Arrive with 3 companies | "Generating for 3 portfolio companies: Ace Limited, Beta Corp, Gamma Corp"; one row; first report and template selected | | |
| ☐ | J2.2 | Options | Click **Add report** | A second row below the first, with its own Report and Template and a **Remove** button; row 1 also gets **Remove** | | |
| ☐ | J2.3 | Options | Change row 2's report | Row 2's templates change to that report's; row 1 unchanged | | |
| ☐ | J2.4 | Options | Click **Remove** on row 2 | Row 2 disappears; the last row shows no **Remove** | | |
| ☐ | J2.5 | Options | Repeat a template and click **Generate Report** | The page does not reload; the message appears under the repeated row; the other rows, dates and ticks are untouched. Change the template and the message goes | | |
| ☐ | J2.6 | Options | Fill valid rows, click **Generate Report** | "Queued report generation for 3 companies." | | |
| ☐ | J2.7 | Message at the top | Wait, then click the link | "Portfolio Report Generation completed. … Saved in Portfolio Reports / Generated Portfolio Reports: <name>"; the link opens the file | | |
| ☐ | J3.1 | Extract details | Open an extract | **Delete** button beside **Edit Data** (only for users who may delete) | | |
| ☐ | J3.2 | Extract details | Click **Delete** | A confirmation popup | | |
| ☐ | J3.3 | Extract details | Confirm | The report's extract list with "Portfolio report extract deleted successfully." | | |
| ☐ | J3.4 | Message at the top | Generate extracts for a company with no documents | The normal completion message, then one amber (warning) message listing the company | | |
| ☐ | J3.5 | Company dashboard | Open a company with a blank newest extract | The widget shows the earlier extract with content | | |

---

## Role Sweep

✓ = allowed and works · ✗ = correctly blocked · ! = wrong.

| ID | Screen / action | Fund admin (Meera) | Employee without portfolio access (Esha) | Investor (Ines) | Other-entity user (Omar) |
|---|---|---|---|---|---|
| R1 | Tick **Consolidated** on a report | ✓ | ✗ | ✗ | ✗ (cannot see Alpha's reports) |
| R2 | Open the options step | ✓ | ✗ | ✗ | ✓ for his own entity only |
| R3 | Submit **Generate Report** with several rows | ✓ | ✗ | ✗ | Only with his own entity's reports, templates and companies |
| R4 | Open the combined file's link | ✓ | ✗ unless granted the folder | ✗ | ✗ |
| R5 | **Delete** an extract | ✓ | ✗ (no button, request refused) | ✗ | ✗ (not found for Alpha's extracts) |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Messages and the error email | Completion message at the top of the screen; the error email (if any) goes to the requesting user's entity as today; no new emails when everything succeeds | | |
| ☐ | C2 | Dates on the options page | Start/End dates follow the user's locale format | | |
| ☐ | C3 | Narrow / mobile width | The rows stack, no horizontal scroll, **Add report** and **Remove** reachable | | |
| ☐ | C4 | Tenant isolation | Omar cannot see or open Alpha's reports, companies, extracts, or combined files, even by direct link | | |
| ☐ | C5 | Regression on modified screens | The portfolio report form (create / edit / clone), the single-company "Portfolio Report (Legacy)" generate page, and the company-selection step of Bulk Generate all work as before | | |
| ☐ | C6 | Empty states | A report with no templates shows an empty template list and, on Generate, the X1 message | | |
| ☐ | C7 | Extract screens | The extract list, details, Edit Data and the tear sheet still work; the dashboard widget still shows for a company with a good latest extract | | |
| ☐ | C8 | Footnotes, endnotes and comments in a combined file | Generate a list with templates that contain footnotes, endnotes or Word comments (cover and a normal report) and open the combined file in Word | Text of the first file's footnotes is intact. Footnotes, endnotes and comments that sit in a later file's content are NOT carried over (known limitation of the joiner: only images and hyperlinks are brought across); note which templates are affected and avoid footnotes in them | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
