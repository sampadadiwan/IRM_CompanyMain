# funds/capital-call-journey Specification

## Purpose
Shows every capital call's progress through a defined journey (Full: Notify Investors, or Light: Record
Only) on the call page, says what the current step needs, and warns at approve and send time about steps
not yet done.

## Requirements

### Requirement: Seeded journeys
Each entity with funds SHALL have two capital call journey templates, "Capital Call — Full: Notify
Investors" and "Capital Call — Light: Record Only", each with a description of every step. One of them SHALL
be the entity's default for new capital calls, Full unless the admin chooses Light. Calls created by the
call importer SHALL get Light by default (a second, higher-priority auto-assign rule), because they are
usually historical and are never approved or notified in the app. Seeding SHALL be idempotent and SHALL NOT
overwrite a template an admin has edited.

The Full journey steps, in order:

| # | Step | Kind | Passes when | Not applicable when | Unlocks |
|---|---|---|---|---|---|
| 1 | Create remittances | system | generated calls: every commitment in the call's closes with a positive committed amount has a remittance; uploaded calls: the call has remittances and every import that created them has finished without errors. After a figures change, a successful Recompute Call must also have run since | — | — |
| 2 | Add call notice template | system | the fund has a call notice template (commitment templates only override it by name) | notices not applicable | — |
| 3 | Generate notices | system | every notifiable remittance has a generated notice (an investor with unverified KYC gets none, so the task stays current and says so) | notices not applicable | — |
| 4 | Approve notices | system | no generated notice on the call is unapproved | notices not applicable | — |
| 5 | Review email | acknowledge | confirmed after the call email template last changed | notices not applicable, or Send notices has passed | — |
| 6 | Check preview | acknowledge | confirmed after the call email template last changed | notices not applicable, or Send notices has passed | — |
| 7 | Approve call | system | the call is approved | the call was imported | Approve |
| 8 | Send notices | system | no notifiable remittance is unsent | notices not applicable | Send Notification |
| 9 | Collect payments | system | total collected ≥ total called | — | — |
| 10 | Verify remittances | system | every remittance is verified | — | — |
| 11 | Allocate units | system | every verified remittance has fund units | the call has no unit prices | — |

"Notices not applicable" means the call was imported or is set to not send notifications. "Notifiable"
excludes remittances whose commitment is set to skip document generation.

The Light journey steps, in order: Create remittances, Collect payments, Verify remittances, Allocate units,
with the same rules.

#### Scenario: Seeding a new entity
- **WHEN** the rollout task or entity setup runs for an entity with no journey templates
- **THEN** both templates exist with the steps above, Full is the default, and each step has an owner of "call creator"

#### Scenario: Imported calls get Light
- **WHEN** a call is created by the call importer in a seeded entity
- **THEN** it gets the Light journey, not Full

#### Scenario: Re-running seeding
- **WHEN** seeding runs again after an admin added a CFO sign-off step to Full
- **THEN** no template is duplicated and the admin's step is kept

### Requirement: Automatic launch
A capital call created after release SHALL get the entity's default journey launched automatically. The
launch SHALL NOT evaluate the journey (it runs inside the call's create transaction); the first evaluation
is the next view of the call page or the next periodic evaluation. A call
that already has a workflow SHALL NOT get a second one. Switching a call to the other journey is not
supported in this change.

#### Scenario: New call
- **WHEN** a user creates a capital call in an entity whose default is Full
- **THEN** the Full journey is launched for the call, and it is first evaluated when the creator lands on the call page

#### Scenario: Imported call
- **WHEN** a seeded entity's admin has pointed both rules at Full and a call is imported
- **THEN** its notice, email and Approve call steps show as not applicable, so it can still complete

#### Scenario: Entity without seeded journeys
- **WHEN** a call is created in an entity where seeding never ran
- **THEN** no journey is launched and the call page is unchanged

### Requirement: New calls only
Only capital calls created after an entity's journeys are seeded SHALL get a journey. The rollout SHALL
seed templates and the auto-launch rule only; it SHALL NOT launch journeys on existing calls, whatever their
age or state. Existing calls SHALL keep today's page with no step bar. The rollout SHALL support a dry run
that reports, per entity, what it would seed without changing anything.

#### Scenario: Dry run
- **WHEN** the rollout is run without the execute flag
- **THEN** it prints, per entity, the templates and rule it would create and the flag it would enable, and writes nothing

#### Scenario: Existing call untouched
- **WHEN** the rollout runs with execute while a call created yesterday is approved but not fully verified
- **THEN** no journey is launched for that call and its page is unchanged

#### Scenario: Call created after rollout
- **WHEN** a call is created the day after the rollout ran for its entity
- **THEN** the entity's default journey is launched for it

### Requirement: Step bar and "What's needed now" panel
The capital call page SHALL show, for a call with a journey, a step bar with every step's status (done,
current, not yet, not applicable with reason, moved back) and a panel with the current step's name,
position, owner, how long it has been current, a status line from data and an action link or "Mark reviewed"
button. Until "Send notices" has passed or is not applicable, the panel SHALL also list readiness warnings:
investors with nobody subscribed to Capital Call notifications, and commitments set to skip document
generation. A call without a journey SHALL show
neither.

#### Scenario: Notices partly approved
- **WHEN** 12 of 40 generated notices are approved
- **THEN** the panel shows "Approve notices", "28 of 40 call notices await approval" and a "View notices to approve →" link to those documents

#### Scenario: Missing template
- **WHEN** the call's fund has no call notice template
- **THEN** "Add call notice template" is current with "The fund has no call notice template" and a link to the fund's templates

#### Scenario: Skip-doc-gen warning
- **WHEN** 1 commitment on the call has Skip Doc Gen set
- **THEN** the panel shows "1 commitment has Skip Doc Gen set and will not be emailed" until notices are sent

#### Scenario: Light journey
- **WHEN** a call on the Light journey has its remittances created, paid, verified and units allocated
- **THEN** its step bar shows only Create remittances, Collect payments, Verify remittances and Allocate units, and the journey completes

#### Scenario: Call set not to notify
- **WHEN** a Full-journey call has "send call notice" switched off
- **THEN** Add call notice template through Check preview and Send notices show n/a "This call is set to not notify investors"

#### Scenario: Readiness warnings
- **WHEN** 2 investors on the call have no user subscribed to Capital Call notifications
- **THEN** the panel shows "2 investors have nobody subscribed to Capital Call emails" at every step before notices are sent, and not after

#### Scenario: Journey complete
- **WHEN** every step is done or not applicable
- **THEN** the panel shows "Journey complete" with the completion date

#### Scenario: Not-applicable reason
- **WHEN** the user hovers a greyed "Send notices" on an imported call
- **THEN** it reads "Notices are not sent for imported calls"

### Requirement: Undoing actions update the journey immediately
These capital call actions SHALL be treated as undoing actions. Each SHALL evaluate the call's journey as
part of the action, or as part of the job that carries the action out, and record the acting user:
- Unapprove;
- unapproving a generated notice (one, or in bulk on the Documents screen);
- Generate Documents (for the call or for one remittance) when it replaces notices;
- Mark Notification Unsent;
- Unverify, including the bulk toggle;
- editing a call's percentage called, amount to be called or fund closes once remittances exist;
- changing the call date (it triggers a recompute);
- Recompute Call;
- editing or deleting the call's own or the fund's capital call email template.

Deleting a payment or fund units is not an undoing action: the journey notices it within 15 minutes, and no
sign-off comes after those tasks in either seeded journey.

Approved notices are never replaced by Generate Documents (existing behaviour). When notices must be
regenerated, the panel SHALL tell the user to unapprove them on the Documents screen first.

Editing figures or the call date SHALL invalidate "Create remittances" and "Generate notices", because the
existing remittances and notices still carry the old amounts. "Create remittances" passes again only once
Recompute Call has finished without errors after the edit. Recompute Call SHALL invalidate "Generate
notices", which passes again only once every notice is newer than the recompute. Editing the email template
SHALL invalidate "Review email" and "Check preview" on calls whose "Send notices" has not passed; they pass
again only once re-confirmed after the edit.

Forward progress, such as payments, notice approvals, approval, sending and unit allocation, SHALL be shown
on the next view of the call page, and in any case within 15 minutes, without those actions having to
notify the journey.

#### Scenario: Unapprove moves back
- **WHEN** a user unapproves a call whose journey had passed "Approve call", with a CFO sign-off earlier in the journey
- **THEN** "Approve call" is current with ↺, the CFO sign-off is kept (it comes before), and the banner reads "Moved back to Approve call — unapproved by <user> on <date>"

#### Scenario: Regenerating notices
- **WHEN** a user unapproves the call's approved notices and then regenerates them
- **THEN** "Approve notices" becomes current with ↺ at the unapprove, and the "Review email" and "Check preview" confirmations, given before the unapprove, are reset (they must be confirmed again for the new notices)

#### Scenario: Unverified KYC blocks notices
- **WHEN** notices are generated while 2 investors on the call have unverified KYC
- **THEN** "Generate notices" stays current with "2 investors have unverified KYC — notices are not generated for them"

#### Scenario: Email template edited
- **WHEN** the call email template is edited after "Review email" was confirmed
- **THEN** "Review email" and "Check preview" are no longer passed with "Email template changed after review" and the earlier confirmations are cleared

#### Scenario: Figures edited after notices generated
- **WHEN** a user changes percentage called on a call whose notices were generated and approved
- **THEN** "Create remittances" becomes current with ↺ and "Remittances were calculated before the call figures changed — recompute"

#### Scenario: Recompute after figures change
- **WHEN** the user then runs Recompute Call
- **THEN** "Create remittances" passes and "Generate notices" is current with ↺ and "Notices were generated before the remittances changed — unapprove them on the Documents screen, then click Generate Documents"

#### Scenario: Uploaded remittances
- **WHEN** an Upload-basis call's remittance import for 25 of the fund's 40 investors finishes
- **THEN** "Create remittances" passes; while the import is still running it shows "Remittance upload in progress"

#### Scenario: Email edit after sending
- **WHEN** the fund's capital call email template is edited after a call's notices were sent
- **THEN** that call's journey is unchanged (its review tasks are n/a once Send notices has passed)

#### Scenario: Sent notices picked up
- **WHEN** the Send Notification job finishes at 10:05 and nobody opens the call
- **THEN** by the 10:15 tick "Send notices" has passed and "Collect payments" is current

#### Scenario: Payment recorded
- **WHEN** the last outstanding payment is recorded and the call page is next opened
- **THEN** "Collect payments" passes and "Verify remittances" becomes current

### Requirement: Approve and Send stay advisory
Approve and Send Notification SHALL NOT be blocked by the journey, and their confirmations SHALL NOT
repeat the journey: the step bar and "What's needed now" panel are on the same page, and a second copy
inside the dialog would be the only journey state outside the panel, so it could go stale while the page
is open. The existing rule that refuses approval while generated notices are unapproved SHALL stay. Calls
without a journey SHALL show the confirmations as today.

#### Scenario: Approve with an outstanding task
- **WHEN** all notices are approved and a user clicks Approve while "Review email" is current
- **THEN** the confirmation shows its usual message with no journey section, and confirming approves the call

### Requirement: Documented journeys
The capital calls user guide SHALL document both journeys step by step, covering for each step what it
checks, when it is not applicable, what moves it back, who is reminded, and how to resolve it. It SHALL
include a mermaid diagram per journey and FAQs. The workflow user guide SHALL document the new step kinds,
owners, unlocks and "Keep sign-off when moved back".

#### Scenario: Guide covers every step
- **WHEN** the user guide lint runs
- **THEN** the Capital Call Journey section has an entry for each of the 11 Full and 4 Light steps and passes the FAQ lint
