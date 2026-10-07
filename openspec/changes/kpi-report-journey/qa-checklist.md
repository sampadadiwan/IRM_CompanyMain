# KPI Report Journey — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X) and UI journeys (J).

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
| Environment | Staging (IN), then US separately |
| Accounts | Fund admin **Anita** (tagged Kpi); employees **Priya**, **Rahul**, **Vikram** (tagged Kpi); portco user **Meera** (Acme) |
| Second entity | A user of another fund, for isolation checks |
| Seed data | Fund "Kaveri Ventures". Portfolio companies **Acme Pvt Ltd** (40 KPI mappings incl. computed "ARPC" = `Revenue/Cycles`) and **Beta Foods** (no mappings). Workbook `acme_kpis.xlsx` with 31 periods (ask a developer for the fixture) |
| Journey setup | Workflow Templates → **Set up journeys** → **KPI report journeys** (or ask a developer to run `kpi_report_journeys:setup`). Then edit the template: owner of "Approve or reject KPIs" = Rahul; add step "Send completion email" with actor Rahul |
| Background work | Imports run on their own within a minute. Reminders run nightly at 00:30 — ask a developer to run the reminder job now. The journey refresh tick runs every 15 minutes |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Setup creates the template | Journeys not set up | 1. Workflow Templates → Set up journeys → KPI report journeys 2. Confirm | Template "KPI Report Review" with 6 steps; the menu item now shows "✓ … set up" | | |
| ☐ | H3 | One journey per upload | Acme Sep 2026 requested | 1. Upload `acme_kpis.xlsx` on Sep 2026 2. Wait for the import 3. Open another period's report (e.g. Jun 2026) | Sep 2026 has a step bar; Jun 2026 and the other new reports have none | | |
| ☐ | H4 | Pending count across periods | H3 | Open Sep 2026 | "214 KPIs across 31 periods await a decision" and **Review pending KPIs** | | |
| ☐ | H5 | Close report | H4 | 1. Click **Close report** 2. Read the popup 3. Confirm | Popup cards "Approve pending KPIs — 214 KPIs across 31 periods for Acme Pvt Ltd" and "Mark reviewed"; after: "Reviewed"; steps up to **Close report** ticked | | |
| ☐ | H6 | Set Managed by | Acme without a manager | 1. Edit Acme 2. Managed by = Priya 3. Save | Saved; Acme's page shows Managed by: Priya | | |
| ☐ | H7 | Manager gets reminders | H4 stalled 3 days, interval 2 (or ask a developer to time-travel) | Run the reminder job | Only Priya receives the reminder (Rahul does not) | | |
| ☐ | H8 | Completion email | H5 | Click **Send completion email** in the panel and confirm | Priya receives "KPIs for Acme Pvt Ltd — Sep 2026 are complete"; the journey shows complete | | |
| ☐ | H9 | Live update | Sep 2026 page open on "Import workbook" | Wait for the import to finish, without reloading | The step bar moves to "Approve or reject KPIs" by itself | | |
| ☐ | H10 | Approve all from the grid | Acme Sep and Dec 2026 both have journeys | Pending grid → Approve all for Acme | Both reports' step bars move on | | |
| ☐ | H11 | Delete unused mapping | Mapping "Headcount" with no KPIs | Delete it | Deleted with the usual message, no warning popup | | |
| ☐ | H12 | Delete warning | "Revenue" has KPIs | Click Delete on "Revenue" | Popup: "214 KPIs across 31 periods (180 approved)", "ARPC uses Revenue", "Cannot be undone" | | |
| ☐ | H13 | Confirmed delete | H12 | Confirm | "Revenue and 214 KPIs deleted"; KPI grid no longer shows Revenue | | |
| ☐ | H14 | Fund upload skips portco steps | — | New KPI Report for Acme Sep 2026 without portco upload | "Send upload request" and "Submit KPIs" show "n/a — Uploaded by the fund" | | |
| ☐ | H15 | No mappings | Beta has no mappings | Request a Beta report and open it | **Set up KPI mappings** current: "No KPI mappings — imports will find nothing" with **Open KPI mappings** | | |
| ☐ | H16 | Whole journey, portco upload | Acme with no mappings; Managed by Priya; template has "Send completion email" | 1. Send Acme an upload request for Jun 2026 2. Open the report: Set up KPI mappings is current 3. Add the mappings 4. As Meera, open the email link, upload the workbook, Submit Report 5. Open the report 6. Close report 7. Send completion email | Step bar moves task by task; after 5 "Approve or reject KPIs" is current and other periods have no step bar; after 7 "Journey complete" and Priya has the email | | |
| ☐ | H17 | Whole journey, fund upload | Acme with mappings; no completion task | 1. New KPI Report for Acme, Jun 2026, Month, with the workbook 2. Open the report 3. Close report | Send upload request and Submit KPIs show n/a; after 3 "Journey complete" | | |
| ☐ | H18 | Send from the report page | Acme with mappings and an approved portal user | 1. New KPI report for Acme, Sep 2026, Quarter, portco upload on 2. Click **Send upload request** in the step bar 3. Proceed | Popup says who is emailed and "no new report is created"; the portal user gets the link for Sep 2026; KPI Reports list has no new Acme report; bar on **Submit KPIs** | | |
| ☐ | H19 | Approvals in a new tab | a submitted upload with pending KPIs | 1. Report page → step bar **Review pending KPIs** 2. Approve a value, then **Approve All Staged** 3. Switch back to the report tab | 1 opens a new tab with the banner "N KPIs pending"; the count drops after each decision; after **Approve All** the banner says "All KPIs decided — next: Close report"; the report tab already shows **Close report** current, no reload | | |
| ☐ | — | Portco after submit | a portco upload request | Submit on the magic link, then open the link again | "KPIs submitted" page with import status and file name, no **Let's get started**; after the fund's **Reopen & ask to re-upload** the new link shows the upload steps | | |
| ☐ | — | Staged review has no empty chart | a submitted first upload, nothing approved | Report page → **View Including Staged** | no empty **KPIs** chart card; staged cards and grid shown; **Hide Staged** shows the chart again | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Setup re-run keeps edits | H1 + admin edits | Run setup again | "already set up"; no step added (no CFO step) | | |
| ☐ | E2 | By-product edit | A report created by H3 | Edit its notes, save | Still no step bar | | |
| ☐ | E3 | Company's own report | A report without a portfolio company | Create it | No step bar | | |
| ☐ | E4 | Existing reports untouched | An Acme report sent to the portco before setup | Run setup, open the report | No step bar; nobody emailed | | |
| ☐ | E5 | All rejected | Sep 2026 imported | Reject every KPI on Sep 2026 | **Import workbook** current: "No KPIs on this report — they were rejected, or the workbook had no column for this period" | | |
| ☐ | E6 | No Close before import | Report not yet imported | Open it | No **Close report** button | | |
| ☐ | E7 | Template owner | Beta (no manager), step owner Rahul, stalled | Reminder job | Rahul reminded | | |
| ☐ | E8 | Kpi team fallback | Beta, step without owner | Reminder job | Anita and Vikram each get one reminder | | |
| ☐ | E9 | Nobody to remind | Beta, no owner, nobody tagged Kpi | Open report; run job | Panel shows "Owner unavailable"; no email | | |
| ☐ | E10 | Double click | H8 | Click Send completion email again (or two tabs) | No second email; "Already sent" | | |
| ☐ | E11 | No completion step | Template without it | Close a report | Journey complete; no completion button | | |
| ☐ | E12 | Reopen after close | H8 | **Reopen & ask to re-upload** | Back on **Submit KPIs**; history shows the move back; completion email can be sent again later | | |
| ☐ | E13 | Unapprove | Journey complete | Unapprove one Acme KPI | Back on "Approve or reject KPIs": "1 KPI across 1 period awaits a decision" | | |
| ☐ | E14 | Old portco workflow gone | Acme has an Investor workflow template assigned | Import a workbook | No workflow starts on Acme's investor page | | |
| ☐ | E15 | Cancel delete | H12 popup | Cancel | Nothing deleted | | |
| ☐ | E16 | Last mapping deleted | Beta has one mapping and an open journey | Delete it and confirm | Beta's journey back on **Set up KPI mappings** | | |
| ☐ | E17 | Capital call reminders unchanged | A stalled capital call journey | Reminder job | The call's creator gets the reminder exactly as before | | |
| ☐ | E18 | Request on an old report | Jun 2026 created by an import | Send Acme a notification for Jun 2026 | Jun 2026 now has a step bar | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Outsider as manager | — | Ask a developer to submit Managed by = another entity's user | "must be an employee of this organisation" | | |
| ☐ | X2 | Delete fails | Developer forces a DB error | Confirm delete | "Could not delete Revenue — nothing was changed"; nothing deleted | | |
| ☐ | X5 | Parent mapping can't be deleted | "Net Sales" has children Enterprise and Retail | Open Net Sales; hover Delete | Delete is disabled; tooltip "Move or delete Enterprise, Retail first" | | |
| ☐ | X3 | Manager left | Priya deactivated | Reminder job | Rahul (step owner) reminded; panel shows Rahul | | |
| ☐ | X4 | Import fails | Meera submits a workbook that fails import (developer-provided) | Wait | Back on **Submit KPIs**: "Import failed — reopened for the portco" | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Reminder email | Open Priya's reminder link | Sep 2026 page, panel on "Approve or reject KPIs", "Owner: Priya S." | | |
| ☐ | J1.2 | Panel ② | Click **Review pending KPIs** | Acme's pending grid | | |
| ☐ | J1.3 | Report page ① | Click **Close report**, confirm | Popup cards, then "Reviewed"; panel on "Send completion email" | | |
| ☐ | J1.4 | Panel | Click **Send completion email** | Journey complete | | |

---

## Role Sweep

| ID | Screen / action | Fund admin | Fund employee (KPI access) | Portco user (Meera) | Other-entity user |
|---|---|---|---|---|---|
| R1 | See the journey panel | ✓ | ✓ | ✗ | ✗ |
| R2 | Close report | ✓ | ✓ if allowed to review | ✗ | ✗ |
| R3 | Send completion email | ✓ | ✓ if allowed to edit | ✗ | ✗ |
| R4 | Set Managed by | ✓ | ✓ if allowed to edit investors | ✗ | ✗ |
| R5 | Delete KPI mapping | ✓ | per mapping permission | ✗ | ✗ |
| R6 | Set up KPI report journeys | ✓ | ✗ | ✗ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Completion and reminder emails | Right recipients, subject, link to the report; dates like `Sep 30, 2026` | | |
| ☐ | C2 | Dates on the report page | Locale format (e.g. `30/09/2026` for en) | | |
| ☐ | C3 | Narrow / mobile width | Step bar wraps; buttons reachable; no horizontal scroll | | |
| ☐ | C4 | Tenant isolation | Another fund's user gets "not authorised" on the report, journey and new actions by direct URL | | |
| ☐ | C5 | Regression | Portco submit, reopen, approve/reject, Approve all, mapping create/import, investor edit and capital call / KYC journeys all work as before | | |
| ☐ | C6 | Empty states | Report with no journey shows no empty panel | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |

---

## Local pre-QA run — 2026-10-07 (not a deployed-build sign-off)

Run by Claude against the local dev app (`localhost:3000`, Sidekiq, letter_opener), headless Chromium driving the
real screens, seed entity "Kaveri Ventures QA" (dev DB). Reminders were triggered by calling the reminder job for
the QA reports only; emails were read from letter_opener. **Task 9.1 (tester sign-off on a deployed build) is still open.**

| ID | Result | Notes |
|---|---|---|
| H1 | Pass | Set up journeys menu shows "KPI report journeys set up" (seeded when the company was created) |
| H3 | Pass | Upload of `01_success_realistic_mis.xlsx` created Apr/May/Jun; only Jun has a journey |
| H4 | Pass | "12 KPIs across 3 periods await a decision"; **Review pending KPIs** opens the staged grid |
| H5 | Pass | Popup "Approve pending KPIs — 12 KPIs across 3 periods for Acme Pvt Ltd"; "Report closed — 12 KPIs approved across 3 periods." |
| H6 | Pass | Managed by set on the stakeholder edit form |
| H7 | Pass | Only Priya (manager) reminded, not Rahul (template owner) |
| H8 | Pass | "KPIs for Acme Pvt Ltd — Jun 30, 2026 are complete" to Priya; panel "Journey complete" |
| H9 | Not run locally | Covered by Cucumber (page_marker survives the import) |
| H10 | Not run locally | Covered by Cucumber |
| H11 | Pass | Unused mapping deleted with the plain confirm |
| H12 | Pass | "3 KPIs across 3 periods (3 approved)", "ARPC uses Revenue", "Cannot be undone" |
| H13 | Pass | "Total shareholders equity and 3 KPIs deleted." |
| H14 / H17 | Pass | New Kpi Report + `02_success_template_shape.xlsx`: request/submit n/a, Close report → next task |
| H15 | **Fail → fixed** | Requesting from a company with no portal users created the report without a journey (see findings) |
| H16 | Pass | Grid Send Reminder → magic-link upload and submit → Close report → completion email |
| E6 | Pass | No Close report button on a report without KPIs |
| E7 / E8 / E9 | Pass | Template owner; Kpi team (Anita, Vikram); nobody → panel "Owner unavailable" |
| E10 | Pass | Two tabs: "Completion email sent to Priya Sharma." / "The completion email was already sent." |
| E12 | Pass | Reopen → ↺ Submit KPIs; Send completion email button gone |
| E13 | Pass | Unapprove → ↺ "1 KPI across 1 period awaits a decision"; re-approve → completion email due again |
| E15 / E16 / X5 | Pass | Cancel keeps data; last mapping → Set up KPI mappings; parent: disabled Delete "Move or delete No. of orders first" |
| X3 | Pass | Inactive manager → template owner Rahul reminded |
| E1–E5, E11, E14, E17, E18, X1, X2, X4 | Not run locally | Covered by Cucumber |
| R (portco, other fund) | Pass | Magic link shows no step bar; journey URL → sign-in; other fund's user denied; PATCH completion email sends nothing |
| C1 | Pass with finding | Completion email date `Jun 30, 2026`; see finding 3 |
| C2 / C3 / C4 | Pass | en-US user sees `06/30/2026`; no horizontal scroll at 390 px; isolation as R |

### Findings

1. **Fixed (this change):** `SendPortcoNotificationJob` returned before the journey started when the company had no approved portal users, so the report had no step bar. The job now starts the journey before that check; scenario added to `kpi_report_journey.feature`.
2. **Pre-existing bug (not fixed):** the **Send Portco Notification** modal on the KPI Reports page (`kpi_reports/new_notification.html.erb`) has one more `</div>` than `<div>`; the footer with **Send Reminders** renders outside the dialog and form, so the button can't submit. The grid's per-company **Send Reminder** works.
3. **Duplicate completion email:** with the optional step, the recipient also gets the engine's generic "Complete: KPI Report Review – Acme Pvt Ltd - 2026-06-30" email, whose subject date is ISO (not the email date format).
4. **UX note:** on the Send completion email step the panel's owner chip shows who is reminded (Kpi team / manager), not the step's actors who receive the email when nobody manages the company.
5. **By design, worth knowing:** after an unapprove the report stays **Reviewed**, so Close report isn't offered; the panel points to **Review pending KPIs**, and approving completes the journey again.
