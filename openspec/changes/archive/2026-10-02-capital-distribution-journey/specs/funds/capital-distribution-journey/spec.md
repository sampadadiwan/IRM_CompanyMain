# Spec Delta

## Purpose

Shows every new capital distribution's progress through a defined journey (Full: Notify Investors, or
Light: Record Only) on the distribution page, says what the current task needs, keeps the page live, and
tightens who may approve a distribution and when its payments may be bulk-completed.

## ADDED Requirements

### Requirement: Seeded distribution journeys
Each fund entity that is set up SHALL have two journey templates, "Capital Distribution — Full: Notify
Investors" and "Capital Distribution — Light: Record Only", each step carrying a description. Setup SHALL
also create two auto-assignment rules when the entity has no capital distribution rule yet: imported
distributions → Light (priority 10), every other distribution → Full (priority 100). Setup SHALL be
idempotent, SHALL keep an admin's edits and added steps, and SHALL turn on the entity's workflow templates
permission.

The Full journey tasks, in order:

| # | Task | Kind | Done when | Not applicable when |
|---|---|---|---|---|
| 1 | Create payments | system | generated basis: every commitment the fund had when the distribution was created has a payment; Upload basis: the distribution has payments and every upload that created them finished without errors | — |
| 2 | Generate notices | system | every emailable payment has a generated notice | notices not used |
| 3 | Approve notices | system | no generated notice on the distribution's payments is unapproved | notices not used |
| 4 | Review email | acknowledge | someone confirmed after the distribution email last changed | no email goes out, or Email investors has passed |
| 5 | Check preview | acknowledge | as Review email | as Review email |
| 6 | Approve distribution | system | the distribution is approved | the distribution was imported |
| 7 | Mark payments completed | system | every payment is completed | — |
| 8 | Email investors | system | every completed, emailable payment has been sent its email | no email goes out |
| 9 | Redeem units | system | every completed payment with a face value for redemption has fund units | the distribution has no unit prices |

"No email goes out" means the distribution was imported, its Send Notification setting is off, or every
commitment of its payments is set to Skip Doc Gen. "Notices not used" means no email goes out, or the
fund has no Distribution Template (commitment templates only override a fund template by name). "Emailable" excludes payments whose
commitment is set to Skip Doc Gen.

The Light journey tasks, in order: Create payments, Mark payments completed, Redeem units, with the same
rules.

#### Scenario: Setting up an entity
- **WHEN** setup runs for a fund entity with no distribution journeys
- **THEN** both templates exist with the tasks above, both rules exist, and workflow templates are enabled

#### Scenario: Re-running setup keeps edits
- **WHEN** setup runs again after an admin added a "CFO sign-off" step to Full
- **THEN** no template or rule is duplicated and the admin's step is kept

#### Scenario: Imported distribution gets Light
- **WHEN** a distribution is created by the distribution importer in a set-up entity
- **THEN** it gets the Light journey

### Requirement: New distributions only
Only distributions created after an entity is set up SHALL get a journey. Setup SHALL NOT launch a journey on
any existing distribution, whose page SHALL stay exactly as today.

#### Scenario: Existing distribution
- **WHEN** an entity is set up and a user opens a distribution created before
- **THEN** the page shows no step bar and no Workflow tab change in behaviour

#### Scenario: Entity not set up
- **WHEN** a distribution is created in an entity that was never set up
- **THEN** no journey is launched

### Requirement: Three setup entry points
Setup SHALL be available as (a) a rollout task that is a dry run unless told to execute and can be limited to
one entity, (b) part of new fund-company setup, and (c) a "Set up capital distribution journeys" button on
the Workflow Templates page. All three SHALL run the same setup. The button SHALL be shown only to company
admins of Investment Fund entities; while something is missing it SHALL confirm what it will add and then
report what it added; once everything exists it SHALL show a disabled "✓ Capital distribution journeys set
up".

#### Scenario: Dry run
- **WHEN** the rollout task runs without the execute flag
- **THEN** it prints per entity what it would add and writes nothing

#### Scenario: Setup from the UI
- **WHEN** a company admin clicks the button and confirms
- **THEN** the notice reads "Capital distribution journeys set up: Full and Light journeys, auto-assignment rules. New distributions will get a journey." and the button turns into the disabled set-up state

#### Scenario: Not offered to others
- **WHEN** an employee who is not a company admin opens Workflow Templates
- **THEN** no distribution setup button is shown, and a direct request is refused

### Requirement: Journey panel on the distribution page
A distribution with a journey SHALL show the step bar (every task by name with its mark) and a "What's
needed now" panel naming the current task, a specific message and, where one exists, a button. The button
SHALL activate the control on the page that does the work (opening its menu and running its own
confirmation); when that control is not on the page it SHALL act as a link. Readiness warnings (Skip Doc Gen
commitments, investors with nobody subscribed to Distribution emails, KYCs without bank details) SHALL show
until Email investors passes or is not applicable. The panel SHALL be the only place journey state appears:
confirmation dialogs SHALL NOT repeat it.

#### Scenario: Panel while notices are partly approved
- **WHEN** 1 of 3 generated notices is approved and the user opens the distribution
- **THEN** the panel says "Approve notices: 2 of 3 notices await approval" and its "View notices to approve" button clicks the Actions menu's "View Generated Notices To Approve"

#### Scenario: Panel button runs the real control
- **WHEN** the current task is Mark payments completed and the user clicks the panel button
- **THEN** the Actions menu's "Mark Payments Completed" confirmation appears, and confirming completes the payments

#### Scenario: Notices not used
- **WHEN** the fund has no Distribution Template
- **THEN** Generate notices and Approve notices show as not applicable with "No distribution notice template"

#### Scenario: Warnings until emailed
- **WHEN** one commitment is set to Skip Doc Gen and investors have not been emailed
- **THEN** the panel warns "1 commitment has Skip Doc Gen set and will not be emailed", and the warning disappears once Email investors passes

### Requirement: Notices to approve link
The distribution's Actions menu SHALL offer "View Generated Notices To Approve" to users who may update the
distribution. It SHALL open, in a new window, the Documents screen filtered to this distribution's generated,
unapproved notices with the notice-approval hint.

#### Scenario: Opening the notices to approve
- **WHEN** the user clicks "View Generated Notices To Approve"
- **THEN** a new window shows only this distribution's unapproved generated notices, and the distribution page stays open

### Requirement: Live updates
An open distribution page SHALL update its journey panel without a reload when the journey's state changes,
whoever or whatever changed it. Each viewer SHALL see the panel as their own rights allow. A change that
leaves every task's state the same SHALL NOT update the page.

#### Scenario: Notices generated in the background
- **WHEN** the page is open on Generate notices and the notice generation job finishes
- **THEN** without a reload the bar shows Generate notices ✓ and Approve notices ●

#### Scenario: A colleague completes payments
- **WHEN** a colleague marks the payments completed in another session
- **THEN** the open page moves on to Email investors without a reload

### Requirement: Progress hooks
Every action that can complete a task SHALL re-check the journey of the affected distribution(s) at once:
payment generation, payment import, adding a payment, approving, bulk and single completion, notice
generation, approving notices (single, bulk and by date range), sending emails (bulk and single) and
redeeming units. Bulk operations SHALL re-check each affected distribution once. Distributions without a
journey SHALL cost nothing extra.

#### Scenario: Approving notices by date range
- **WHEN** a user approves documents by date range including notices of two distributions with journeys
- **THEN** both distributions' journeys are re-checked once each

#### Scenario: No journey, no work
- **WHEN** notices are approved for a distribution created before setup
- **THEN** no journey is evaluated and the action behaves as today

### Requirement: Undo moves the journey back
These actions SHALL re-check the journey and, when it moved back, record why and reset later sign-offs given
before the action: Recompute Fees, changing the distribution date, unticking a payment's Completed box,
deleting a payment, regenerating notices that existed, unapproving a notice, deleting redeemed units, and
creating, editing or deleting the distribution email (distribution-level, or fund-level for distributions not
yet emailed). Editing the email SHALL also reset Review email and Check preview.

#### Scenario: Recompute Fees after approval
- **WHEN** a CFO signed off and Recompute Fees then changes the payments
- **THEN** the panel shows "Moved back to …" with "Fees recomputed", and the CFO sign-off is pending again

#### Scenario: Unticking Completed
- **WHEN** a user unticks Completed on one payment of a distribution at Email investors
- **THEN** the journey moves back to Mark payments completed

#### Scenario: Email edited after review
- **WHEN** the distribution's email is edited after Review email was confirmed and before investors were emailed
- **THEN** Review email and Check preview are pending again with "Email template changed after review"

### Requirement: Deleting a distribution with a journey
A distribution whose only active workflows are journeys SHALL be deletable as today; its journey SHALL be
removed with it.

#### Scenario: Delete
- **WHEN** a user deletes a distribution that has a journey and no fund units
- **THEN** the distribution is deleted

### Requirement: Approver role for approval
Approving a distribution SHALL require the Approver role in addition to update rights, for the menu item and
for the request itself.

#### Scenario: User without the role
- **WHEN** a user with update rights but no Approver role opens the distribution
- **THEN** Actions shows no Approve, and a direct approve request is refused without changing the distribution

#### Scenario: Approver
- **WHEN** an approver clicks Approve and confirms
- **THEN** the distribution is approved and records the approver

### Requirement: Bulk completion needs approval
"Mark Payments Completed" on a distribution SHALL be refused, on the server, for an unapproved distribution.

#### Scenario: Direct request on unapproved
- **WHEN** a request to mark all payments completed is made for an unapproved distribution
- **THEN** it is refused with "Access Denied" and no payment changes

### Requirement: Accurate Send Notification hint
The distribution form's Send Notification checkbox SHALL read "Allow emailing investors about this
distribution. Emails are sent from Actions → Send Payment Notifications." and SHALL NOT claim that completing
a payment sends an email.

#### Scenario: Form hint
- **WHEN** a user opens the new distribution form
- **THEN** the Send Notification hint reads as above

### Requirement: Reliable background reporting
Payment generation SHALL report its errors to the user who triggered it, or log them when no user triggered
it, without failing again while reporting. Recompute Fees SHALL name the distribution in its first progress
message.

#### Scenario: Generation error with no user
- **WHEN** payment generation hits an error for a distribution created by an import
- **THEN** the error is logged and the job does not raise a second error while reporting it
