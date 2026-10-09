# Spec Delta

## Purpose

Shows each requested KPI report's progress from "KPI mappings set up" to "closed" as a journey on the
report page, tells the right employee what is needed, and lets the fund close a period and announce it.

## ADDED Requirements

### Requirement: Seeded KPI report journey
Each set-up entity SHALL have one journey template, "KPI Report Review", for KPI reports, each step
carrying a description, and one auto-assignment rule with no conditions launching it, created only when
the entity has no KPI report rule yet. Setup SHALL be idempotent, SHALL keep an admin's edits and added
steps, and SHALL turn on the entity's workflow templates permission.

The tasks, in order:

| # | Task | Kind | Done when | Not applicable when |
|---|---|---|---|---|
| 1 | Set up KPI mappings | system | the portfolio company has at least one KPI mapping that is not computed | — |
| 2 | Send upload request | system | the upload link was sent, or the report is past the link-sent status | the report is not set up for portco upload ("Uploaded by the fund") |
| 3 | Submit KPIs | system | the report is submitted or reviewed | the report is not set up for portco upload ("Uploaded by the fund") |
| 4 | Import workbook | system | the report's current workbook finished importing without blocking errors and the report has at least one KPI | — |
| 5 | Approve or reject KPIs | system | no KPI of the portfolio company awaits a decision | — |
| 6 | Close report | system | the report is reviewed | — |

#### Scenario: Setup seeds the template and rule
- **WHEN** an admin runs KPI report journey setup for an entity with no KPI report rule
- **THEN** the entity has the "KPI Report Review" template with the six tasks above and one catch-all rule for KPI reports

#### Scenario: No KPI mappings yet
- **WHEN** a report is requested for Beta, which has no KPI mappings
- **THEN** "Set up KPI mappings" is current with "No KPI mappings — imports will find nothing" and an "Open KPI mappings" link

#### Scenario: Fund upload skips the portco steps
- **WHEN** a fund user creates Acme's Sep 2026 report on the New KPI Report screen without portco upload
- **THEN** "Send upload request" and "Submit KPIs" show "n/a — Uploaded by the fund"

#### Scenario: Setup is idempotent and keeps edits
- **WHEN** setup runs again after an admin renamed a step and added a "Send completion email" step
- **THEN** no template, step or rule is added or changed

### Requirement: Only requested reports get a journey
A KPI report SHALL get a journey only when it is created as a request: from the New KPI Report screen, as
a report shell, or by sending a portco notification. A report created by importing a workbook (one per
period or tag found), by cumulating KPIs into roll-up periods, or by the bulk KPI import SHALL NOT get a
journey, at creation or on any later update. A report without a portfolio company SHALL NOT get a journey.

#### Scenario: Upload creates many reports, one journey
- **WHEN** a workbook with 31 periods is imported on Acme's Sep 2026 report
- **THEN** Sep 2026 has a journey and the 30 other reports the import created have none

#### Scenario: Asking the portco for an existing report
- **WHEN** the fund sends Acme a notification for Jun 2026, a report an earlier import created
- **THEN** Jun 2026 gets a journey

#### Scenario: Editing a by-product report later
- **WHEN** a user edits the notes on a report the import created
- **THEN** it still has no journey

#### Scenario: Company's own report
- **WHEN** a KPI report without a portfolio company is created
- **THEN** it has no journey

### Requirement: Existing reports get no journey
Setting up KPI report journeys SHALL NOT launch a journey on any report that already exists, and SHALL
email nobody. Only reports requested after setup SHALL get a journey.

#### Scenario: Setup leaves existing reports alone
- **WHEN** setup runs while Acme's Sep 2026 report has been sent to the portco but not submitted
- **THEN** it has no journey and nobody is emailed

### Requirement: Approval covers the whole upload
"Approve or reject KPIs" SHALL count every KPI of the report's portfolio company in the fund that awaits a
decision, on any report. Its message SHALL give the count and the number of periods. When every KPI of
the report was rejected, the report has no KPI left and "Import workbook" SHALL be current, saying so.

#### Scenario: Pending across periods
- **WHEN** 214 KPIs of Acme await a decision across 31 reports
- **THEN** the step is current with "214 KPIs across 31 periods await a decision" and a "Review pending KPIs" link to the pending grid for Acme

#### Scenario: Everything rejected
- **WHEN** every KPI on Acme's Sep 2026 report was rejected
- **THEN** "Import workbook" is current with "No KPIs on this report — they were rejected, or the workbook had no column for this period"

### Requirement: Close report
The KPI report page SHALL show a **Close report** button once the report's workbook has been imported
and the report is not reviewed. After a confirmation listing how many pending KPIs will be approved and
across how many periods, it SHALL approve every pending KPI of the portfolio company in the fund and mark
the report reviewed.

#### Scenario: Close approves everything pending
- **WHEN** a user clicks Close report on Acme Sep 2026 with 214 pending KPIs across 31 periods and confirms
- **THEN** all 214 are approved, the report is reviewed and "Approve or reject KPIs" and "Close report" pass

#### Scenario: Not shown before import
- **WHEN** a report has not been imported yet
- **THEN** no Close report button is shown

### Requirement: Managed by
A portfolio company SHALL have an optional **Managed by** field naming one employee of the fund. Only the
fund's employees SHALL be selectable.

#### Scenario: Pick a manager
- **WHEN** an admin sets Managed by on Acme to Priya, an employee of the fund
- **THEN** it is saved and shown on Acme's page

#### Scenario: Outsider refused
- **WHEN** a request sets Managed by to a user of another entity
- **THEN** the save fails with "must be an employee of this organisation"

### Requirement: Who is reminded and emailed
For a KPI report journey, step reminders SHALL go to the portfolio company's Managed by employee when set
and active; otherwise to the step's named owner; otherwise to every active employee of the fund tagged
"Kpi". The completion email SHALL go to the Managed by employee when set and active; otherwise to the
step's actors; otherwise to every active employee tagged "Kpi". When nobody resolves, nobody SHALL be
emailed and the panel SHALL show "Owner unavailable".

#### Scenario: Manager wins over template
- **WHEN** Acme is managed by Priya and the template names Rahul as owner of "Approve or reject KPIs"
- **THEN** the stalled-step reminder goes to Priya only

#### Scenario: Template owner when no manager
- **WHEN** Beta has no Managed by and the template names Rahul as owner
- **THEN** the reminder goes to Rahul

#### Scenario: Kpi-tagged fallback
- **WHEN** Beta has no Managed by and the step has no owner, and Anita and Vikram are tagged Kpi
- **THEN** both Anita and Vikram are reminded

#### Scenario: Nobody resolves
- **WHEN** no Managed by, no owner and nobody tagged Kpi
- **THEN** no reminder is sent and the panel shows "Owner unavailable"

### Requirement: Optional completion email step
The KPI report check list SHALL offer "Send completion email" (system). It SHALL NOT be seeded. In the step
editor the Actors picker SHALL be shown for it. While it is current, the journey panel SHALL offer **Send
completion email**; clicking it SHALL email the recipients "KPIs for <portco> — <period> are complete" with
a link to the report, record when it was sent, and the step SHALL pass. A second click SHALL send nothing.

#### Scenario: Send the email
- **WHEN** every earlier step is done and a user clicks Send completion email
- **THEN** Priya receives "KPIs for Acme — Sep 2026 are complete" and the journey is complete

#### Scenario: Double click
- **WHEN** the email was already sent and the button is clicked again
- **THEN** no second email is sent

#### Scenario: Not added
- **WHEN** the template has no completion step
- **THEN** the journey completes after "Close report" and no completion email is offered

### Requirement: KPI report journey moves back
These actions SHALL move the journey back and reset later sign-offs: Reopen & ask to re-upload and a
failed import (to "Submit KPIs"); unapproving a KPI of the portfolio company (to "Approve or reject KPIs"); deleting all KPIs
of the report (to "Import workbook"); deleting the portfolio company's last KPI mapping (to "Set up KPI
mappings"). Each SHALL clear the completion email record so it can be sent again. Approving or rejecting a
KPI SHALL only move journeys forward.

#### Scenario: Reopen after close
- **WHEN** a reviewed, emailed report is reopened for the portco
- **THEN** the journey is back on "Submit KPIs", history records the move back, and the completion email can be sent again once complete

#### Scenario: Import fails
- **WHEN** the import of Meera's submission fails
- **THEN** the journey is back on "Submit KPIs" with "Import failed — reopened for the portco"

#### Scenario: Unapprove a KPI
- **WHEN** a user unapproves one of Acme's KPIs while Sep 2026's journey is complete
- **THEN** Sep 2026 moves back to "Approve or reject KPIs" with "1 KPI across 1 period awaits a decision"

### Requirement: KPI report journey updates live
The journey SHALL be re-evaluated when a portco notification is sent, a report is submitted, an import
finishes or fails, KPIs are approved, rejected or unapproved, a report is closed, KPI mappings are created,
imported or deleted, and the completion email is sent. Changes that affect a portfolio company SHALL
re-evaluate every open journey of that portfolio company in one bulk call. An open report page SHALL
update without a reload.

#### Scenario: Import finishes while the page is open
- **WHEN** a user has Sep 2026 open on "Import workbook" and the import job finishes
- **THEN** the step bar moves to "Approve or reject KPIs" without a reload

#### Scenario: Approval on the grid
- **WHEN** a user approves all of Acme's pending KPIs from the grid
- **THEN** every open journey of Acme re-evaluates once

### Requirement: Portfolio company workflow no longer launched
A completed KPI import SHALL NOT launch any workflow on the portfolio company.

#### Scenario: Import with an Investor template assigned
- **WHEN** a portfolio company has an Investor workflow template assigned and its KPIs are imported
- **THEN** no workflow instance is started on the portfolio company

### Requirement: Send upload request from the report page
The KPI report page SHALL show the fund a **Send upload request** button while the report is set up for
portfolio company upload and its upload link has not been sent. It SHALL send the upload link for that
report, never finding or creating another report, after a confirmation popup saying who is emailed. The
journey's "Send upload request" task SHALL click this button. When the portfolio company has no approved
portal user who receives KPI emails the button SHALL be disabled with that reason, and a second click
before the page refreshes SHALL NOT send a second email.

#### Scenario: Send the request from the report page
- **WHEN** the fund clicks the journey's "Send upload request" on Acme's Sep 2026 quarterly report and confirms
- **THEN** Acme's portal users are emailed the link for that report, no other report is created and the step bar moves to "Submit KPIs"

#### Scenario: No portal user
- **WHEN** Acme has no approved portal user and the fund opens the report
- **THEN** "Send upload request" is disabled and says "Acme Pvt Ltd has no approved portal user for KPI requests — add one under Stakeholders first"

### Requirement: Approvals open in a new tab with a way back
The "Approve or reject KPIs" task's button SHALL open the portfolio company's KPI grid, including staged
values, in a new tab, leaving the report and its step bar open. The grid SHALL then show a banner naming
the report, how many KPIs still await a decision, and a link back to the report; once none are pending it
SHALL say all KPIs are decided and that Close report is next.

#### Scenario: Approvals open in a new tab
- **WHEN** the fund clicks "Review pending KPIs" in Acme's step bar and approves all staged KPIs in the new tab
- **THEN** the new tab's banner says "All KPIs decided" with "Back to the report", and the report tab, without reloading, shows "Close report" as the current task
