# workflows/evaluated-workflow-steps Specification

## Purpose
Lets a workflow mix steps that complete from the record's own data (system), from a single confirmation
(acknowledge) and from approver votes (human), so a workflow can track a multi-step business process,
not just an approval chain.

## Requirements

### Requirement: Step kinds
Every workflow step SHALL have a kind: `human`, `system` or `acknowledge`. Steps that existed before this
change, and steps created without a kind, SHALL be `human`. A `system` or `acknowledge` step SHALL name a
check registered for the template's record type. Any step MAY name a skip check registered for that type.

#### Scenario: Existing steps default to human
- **WHEN** the change is deployed onto a database with existing workflow steps
- **THEN** every existing step is of kind `human` and behaves exactly as before

#### Scenario: System step requires a valid check
- **WHEN** an admin saves a `system` step on a Capital Call template without a check, or with a check registered for a different record type
- **THEN** the step is not saved and the form shows "Check must be a Capital Call check"

#### Scenario: Check list is limited to the template's record type
- **WHEN** an admin edits a step on a Capital Call template
- **THEN** the Check and Skip when lists offer only checks registered for Capital Call

### Requirement: Human-only workflows unchanged
A workflow instance whose snapshot contains only `human` steps SHALL behave exactly as before this change.
This covers launching, voting, quorum, rejection routing, reset, reminders, magic links and button gating.

#### Scenario: Human-only approval chain
- **WHEN** a two-step human workflow on an Investor KYC is launched and both approvers approve
- **THEN** the instance completes, notifications and reminders match prior behaviour, and no journey UI is shown

### Requirement: Evaluating a workflow from data
For a workflow containing at least one non-human step, the system SHALL determine the current step by
walking the snapshot steps in position order. A step SHALL be treated as:
- **not applicable** when its skip check is true;
- **passed** when its check passes (system), when a still-valid confirmation exists (acknowledge), or when
  its votes have resolved to the passing state (human);
- **current** when it is the first step that is neither not applicable nor passed.

The instance SHALL be complete when no step is current. Each step's resulting status, status line and
action link SHALL be available for display.

#### Scenario: Several system steps pass at once
- **WHEN** at a call's first evaluation its remittances, template and notices are all already in place
- **THEN** the first three steps show as passed and the current step is "Approve notices"

#### Scenario: Skipped step does not block
- **WHEN** a step's skip check is true for the record
- **THEN** the step shows as not applicable with its reason and the next step can become current

#### Scenario: All steps passed
- **WHEN** every step is passed or not applicable
- **THEN** the instance is complete and records the completion time

#### Scenario: Human step after system steps
- **WHEN** an approver approves a human step and the following system steps already pass
- **THEN** the current step moves past all of them in the same action

### Requirement: Acknowledge steps
An `acknowledge` step SHALL pass when a user allowed to update the record confirms it and its check, if
any, passes. A confirmation made before the step was last invalidated SHALL NOT count. An acknowledge
step's check MAY instead report that the record's own data already confirms the step; the step SHALL then
pass without a confirmation, showing the check's message, provided that evidence is newer than the step's
last invalidation. An acknowledge step's check MAY also explicitly ask for review with its own message and
action; while the step is current, that message SHALL be shown in place of "Not confirmed yet" and that
action SHALL be offered next to "Mark reviewed". A check that does neither SHALL behave exactly as before.

#### Scenario: Confirming a step
- **WHEN** a user with update rights clicks "Mark reviewed" on the current acknowledge step
- **THEN** the confirmation is recorded with user and time, and the journey moves on

#### Scenario: Confirmation invalidated by later change
- **WHEN** an undoing action invalidates the step after the confirmation, e.g. the call email template is edited
- **THEN** the step is no longer passed, the confirmation is cleared and the reason shows, e.g. "Email template changed after review"

#### Scenario: Read-only user cannot confirm
- **WHEN** a user without update rights views the current acknowledge step
- **THEN** no "Mark reviewed" button is shown and a direct request to confirm is refused

#### Scenario: Data confirms the step
- **WHEN** a KYC's AI document validation passed every answer and its "Validate documents" step is reached
- **THEN** the step passes as "Validated by AI" with no confirmation, and history records it as passed by the system

#### Scenario: Data confirmation older than an invalidation
- **WHEN** a document is replaced after the AI validation passed, invalidating the step
- **THEN** the step is current again until a newer AI validation passes or a user confirms it

#### Scenario: Check message shown while waiting
- **WHEN** an acknowledge step is current and its check says "AI could not validate 2 of 12 answers — check them and mark reviewed"
- **THEN** the panel shows that message with "Mark reviewed" and the check's "Open validation" action

#### Scenario: Existing acknowledge steps unchanged
- **WHEN** a capital call's "Review email" step is current
- **THEN** it behaves exactly as before: "Mark reviewed" is required, the message is "Not confirmed yet" and no second button is shown

### Requirement: Step invalidation
An undoing action SHALL be able to invalidate named steps of a record's workflow, recording the time, actor
and reason. An invalidated `system` step SHALL pass again only when its check passes on evidence newer than
the invalidation. An invalidated `acknowledge` step SHALL pass again only on a confirmation made after it.
Invalidating a step that is not current SHALL count as moving back to it.

#### Scenario: System step invalidated
- **WHEN** an action invalidates a passed system step whose existing evidence predates the invalidation
- **THEN** the step becomes current with the invalidation reason until newer evidence exists

#### Scenario: Invalidating an unlaunched or human-only workflow
- **WHEN** an action invalidates a step key on a record without a journey, or whose journey has no step with that key
- **THEN** nothing changes and no error is raised

### Requirement: Moving back
When evaluation finds an earlier step current than before, the system SHALL record a history entry with the
step moved back to, the reason and, when known, the user and action that caused it.

#### Scenario: Move back recorded
- **WHEN** a step that had passed stops passing
- **THEN** the step shows ↺ and the history shows "Moved back to <step> — <reason>"

### Requirement: Sign-off reset only on undoing actions
Sign-offs SHALL be cleared only by a user's undoing action. When an undoing action's evaluation finishes,
every human vote and acknowledge confirmation that (a) belongs to a step after the first step not done, and
(b) was given before the undoing action started, SHALL be cleared, unless its step is marked "Keep sign-off
when moved back". This holds even if a page view or tick evaluated in the meantime and already recorded the
move back. The approvers of cleared human steps SHALL be notified; cleared confirmations are shown in the
history only. A move back found in any other way (page view, tick, software change) SHALL be recorded but
SHALL NOT clear any sign-off.

#### Scenario: Undoing action clears later sign-off
- **WHEN** a CFO approved a human step at position 7 and a user then unapproves a notice, causing a move back to step 4
- **THEN** the CFO's vote is archived, the CFO is notified, and the history names the user and action

#### Scenario: Keep sign-off opt-out
- **WHEN** the same happens but step 7 is marked "Keep sign-off when moved back"
- **THEN** the CFO's vote remains and step 7 passes again once step 4 passes

#### Scenario: Passive move back does not clear sign-off
- **WHEN** a page view finds a step no longer passing and no undoing action was recorded for it
- **THEN** a history entry is written and no vote or confirmation is cleared

#### Scenario: Undo and redo between page views
- **WHEN** a user unapproves a notice and re-approves it a minute later, with no page view or tick in between
- **THEN** the move back was still recorded at the unapprove and the later CFO sign-off was cleared

#### Scenario: Passive evaluation during a long undo job
- **WHEN** a tick evaluates while a recompute job is still running, and records the move back passively
- **THEN** the job's own evaluation at the end still clears later sign-offs given before the recompute started

### Requirement: Per-step button unlocking
A step MAY list button labels it unlocks. For a template that uses unlocks, a listed button SHALL count as
unlocked once its step is passed or not applicable, regardless of later steps. In advisory mode a locked
button SHALL stay clickable and its confirmation SHALL list the earlier steps not yet passed. Templates
that use no unlocks SHALL keep the existing whole-workflow gating.

#### Scenario: Approve unlocks before journey completes
- **WHEN** "Approve call" unlocks "Approve" and every step before it has passed while later steps are pending
- **THEN** Approve is not reported as gated

#### Scenario: Advisory warning
- **WHEN** a user clicks Approve while "Review email", a step before "Approve call", has not passed
- **THEN** the confirmation lists "Review email" with its status line and the user can still proceed

#### Scenario: Legacy gating preserved
- **WHEN** a human-only template sets gated button labels and its instance is still active
- **THEN** those buttons are disabled exactly as before

### Requirement: Step owners and reminders
A `system` or `acknowledge` step SHALL have owners, resolved in this order: the record's override owner
when its record type defines one (e.g. a KPI report's portfolio company manager); else a named user of the
entity set on the step; else the record's default owners (the record's creator by default; a record type
MAY define several). When such a step has been current longer than its effective reminder interval, each
owner SHALL receive a reminder email with the step name, status line and a link to the record. The
reminder SHALL repeat each interval while the step stays current. In such workflows, reminders for human
steps SHALL also be timed from when the step became current, not from the instance's last update. The time
a step passed, and so the time the next step became current, SHALL be taken from the record's data where
the data records it (never earlier than the previous step passed, never later than now), falling back to
the time of detection. Human-step reminders SHALL be unchanged. Record types that define neither an
override nor several default owners SHALL behave exactly as before.

#### Scenario: Owner reminded
- **WHEN** "Approve notices" has been current for 3 days with a 2-day interval and owner "call creator"
- **THEN** the call's creator receives one reminder naming the step and "28 of 40 call notices await approval"

#### Scenario: Step completed while nobody was looking
- **WHEN** the last notice is approved Monday 10:00, nobody opens the call, and the reminder interval for the next step is 2 days
- **THEN** history records the step passed at Monday 10:00, the next step is current since Monday 10:00, no reminder is sent on Wednesday's 00:30 run (under 2 days), and its owner is reminded on Thursday's 00:30 run

#### Scenario: No interval, no reminder
- **WHEN** a step and its template have no reminder interval
- **THEN** no reminder is sent

#### Scenario: Owner left the company
- **WHEN** the owner user no longer exists or is inactive
- **THEN** no email is sent and the panel shows "Owner unavailable — update the journey template"; the owner is read from the live template step, so fixing the template fixes in-flight calls

#### Scenario: Record override wins
- **WHEN** a KPI report's portfolio company is managed by Priya and the step's named owner is Rahul
- **THEN** only Priya is reminded

#### Scenario: Several default owners
- **WHEN** a KPI report step has no override and no named owner, and the default owners are Anita and Vikram
- **THEN** Anita and Vikram each receive one reminder

### Requirement: Periodic evaluation
The system SHALL evaluate, at least every 15 minutes, every active workflow instance containing a non-human
step, and every such instance that completed within the last 30 days (so a late undo is still noticed). A periodic evaluation SHALL be passive: it SHALL record moves back but SHALL NOT clear any
sign-off. When it makes a human step current, that step's actors SHALL receive the step-activation
notification, as when a vote advances a workflow. Instances whose snapshot contains only human steps SHALL
NOT be evaluated periodically.

#### Scenario: Approver notified without anyone viewing
- **WHEN** the last notice before a human sign-off step is approved at 16:00 and nobody opens the record
- **THEN** by 16:15 the sign-off step is current and its approvers have received the step-activation email

#### Scenario: Human-only workflows untouched by the tick
- **WHEN** the periodic evaluation runs while a human-only KYC workflow is active
- **THEN** that instance is not evaluated or changed

### Requirement: Human steps inside an evaluated workflow
In a workflow containing a non-human step, rejecting a human step SHALL NOT end the workflow: the step
stays current and shows "Rejected by <user>: <note>", its votes are archived so the approvers can vote again,
and the instance status stays active. Admin advance and reset on such a workflow SHALL be followed by an
evaluation, so the data decides the final position.

#### Scenario: Rejected journey step
- **WHEN** the CFO rejects the CFO sign-off step with the note "Fee looks wrong"
- **THEN** the step stays current showing "Rejected by Arjun M: Fee looks wrong", the journey stays active, and the CFO can vote again

### Requirement: Check keys are permanent
A registered check key SHALL never be removed or renamed while any workflow snapshot uses it; a changed
meaning SHALL get a new key. An unknown key SHALL show "Unknown check" on that step and stop the walk there.

#### Scenario: A check fails with an error
- **WHEN** a step's check raises an error or its key is unknown
- **THEN** the step shows "Could not check this step — support has been notified", the error is reported, and the walk stops at that step

### Requirement: Checks are fast on large records
Each check SHALL compute its result with database counts or existence queries. It SHALL NOT load every
related remittance, document or account entry into memory.

#### Scenario: Large call
- **WHEN** the call page is opened for a call with 5,000 remittances
- **THEN** journey evaluation completes without loading the remittance rows

### Requirement: Closing step
A `system` step's check MAY be declared closing. When a closing step's check passes, every earlier step
that is neither passed nor not applicable SHALL be shown as not applicable with the closing check's reason
(e.g. "Verified without this step"), so the journey can complete. Steps already passed SHALL keep their
status, and no confirmation or vote SHALL be cleared by closing. When the closing check stops passing, the
steps SHALL be evaluated normally again.

#### Scenario: Verified before earlier tasks
- **WHEN** a KYC is verified while "Upload required documents" and "Run AML screening" are not done
- **THEN** both show "–" "Verified without this step", passed tasks keep ✓, and the journey is complete

#### Scenario: Closing check fails again
- **WHEN** the same KYC is unverified
- **THEN** "Upload required documents" is current again and the move back is recorded

#### Scenario: Journeys without a closing check
- **WHEN** a capital call or distribution journey is evaluated
- **THEN** no step is closed and the walk is exactly as before
