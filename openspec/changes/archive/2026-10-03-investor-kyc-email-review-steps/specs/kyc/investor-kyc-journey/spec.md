# Spec Delta

> The base capability `kyc/investor-kyc-journey` is still carried by the in-flight change
> `investor-kyc-journey`; that change must be synced or archived before this one, so the MODIFIED
> requirement below matches the main spec by header.

## MODIFIED Requirements

### Requirement: Seeded KYC journey
Each set-up entity SHALL have one journey template, "Investor KYC", each step carrying a description. Setup
SHALL also create one auto-assignment rule launching it on every new KYC (no conditions) when the entity has
no KYC rule yet. Setup SHALL be idempotent, SHALL keep an admin's edits and added steps, and SHALL turn on
the entity's workflow templates permission.

The tasks, in order:

| # | Task | Kind | Done when | Not applicable when |
|---|---|---|---|---|
| 1 | Set up KYC email | acknowledge | a user confirmed it, after the entity's KYC-required email last changed | the KYC form has already been sent, or the KYC was filled in by the fund |
| 2 | Preview the email | acknowledge | a user confirmed it, after the entity's KYC-required email last changed | the KYC form has already been sent, or the KYC was filled in by the fund |
| 3 | Send KYC form | system | the KYC form link has been sent to the investor, or the investor has started or submitted it | the KYC was submitted or verified without a form ever being sent ("Filled in by the fund") |
| 4 | Submit KYC | system | the KYC is completed or verified | — |
| 5 | Upload required documents | system | a document exists for every required document name | no document is required |
| 6 | Validate documents | acknowledge | AI validation ran on the KYC and every answer passed, or a user confirmed it | — |
| 7 | Run AML screening | system | the KYC has an AML result | AML is not enabled for the entity |
| 8 | Clear AML match | system | the AML result was manually overridden to no match | AML is not enabled, or the AML result is no match without an override |
| 9 | Review KYC | acknowledge | a user confirmed it | — |
| 10 | Compliance sign-off | human | an approver signed off | no approver is set on the step |
| 11 | Verify KYC | system | the KYC is verified | — |

"Required document names" are the entity's required KYC document list for the KYC's type (individual or
non-individual) together with the KYC form's required document fields. Every task before "Verify KYC" SHALL
also be not applicable, with the reason "Verified without this step", when the KYC is verified and that task
is not otherwise done.

#### Scenario: Setting up an entity
- **WHEN** setup runs for a fund entity with no KYC journey
- **THEN** the "Investor KYC" template exists with the 11 tasks above, the rule exists, and workflow templates are enabled

#### Scenario: Re-running setup keeps edits
- **WHEN** setup runs again after an admin picked an approver on "Compliance sign-off" and removed "Run AML screening"
- **THEN** no template or rule is duplicated and the admin's changes are kept

#### Scenario: Entity already has a KYC rule
- **WHEN** setup runs for an entity that already has an auto-assignment rule for KYCs
- **THEN** the template is created, no rule is added, and the dry run says so

#### Scenario: Imported verified KYC
- **WHEN** a KYC is imported as verified into a set-up entity, with no documents and no AML result
- **THEN** it gets the journey, every task before "Verify KYC" is ✓ or "–" ("Verified without this step"), and the journey is complete

#### Scenario: A new KYC starts at the email tasks
- **WHEN** a KYC is created in a set-up entity and its journey is evaluated
- **THEN** "Set up KYC email" is the current task and "Send KYC form" is not yet

## ADDED Requirements

### Requirement: Setting up and previewing the KYC email
Before "Send KYC form", the journey SHALL ask a fund user to confirm two tasks about the email the investor
will receive, each offering its own control beside "Mark reviewed".

"Set up KYC email" SHALL name the email that will actually be sent. When the entity has a KYC-required
email of its own, the task SHALL say `Your KYC email "<subject>" will be sent — check it and mark reviewed`
and offer "Open KYC emails", which opens the entity's KYC notifications. When the entity has none, it SHALL
say "No KYC email is set up — CapHive's default text will be sent. Set one up, or mark reviewed to use the
default" and offer "Custom KYC Notification", which opens the new-notification form for KYC emails.

"Preview the email" SHALL say "Preview the email as <investor name> will receive it, then mark reviewed" and
offer "Preview KYC Required Notification", which SHALL open that KYC's own rendered preview of the
KYC-required email — the entity's template when it has one, otherwise the default — in a new tab.

Neither task SHALL be completable by data: only a user's confirmation completes it. Neither SHALL block any
action: sending the KYC form, the reminder and every other control SHALL behave exactly as before, whether
or not the tasks are confirmed. Investors SHALL NOT see these tasks, as they see no journey at all.

#### Scenario: Entity has its own KYC email
- **WHEN** a fund user opens a new KYC in an entity with a KYC-required email whose subject is "Complete your KYC"
- **THEN** the panel says `Your KYC email "Complete your KYC" will be sent — check it and mark reviewed` and offers "Mark reviewed" and "Open KYC emails"

#### Scenario: Entity has no KYC email
- **WHEN** a fund user opens a new KYC in an entity with no KYC-required email
- **THEN** the panel says the default CapHive text will be sent and offers "Mark reviewed" and "Custom KYC Notification"

#### Scenario: Confirming both tasks reaches the send task
- **WHEN** a fund user marks "Set up KYC email" reviewed and then "Preview the email" reviewed
- **THEN** "Send KYC form" is the current task with its existing message and "Send KYC Required Notification" control

#### Scenario: Preview opens this KYC's own email
- **WHEN** a fund user clicks "Preview KYC Required Notification" on "Preview the email"
- **THEN** the KYC's preview of the KYC-required email opens in a new tab, rendered with that investor's details

#### Scenario: Sending is never blocked
- **WHEN** a fund user sends the KYC form while neither email task is confirmed
- **THEN** the form is sent as it is today, and both email tasks become not applicable

### Requirement: The email tasks stand aside once nothing can change
Both email tasks SHALL be not applicable, and SHALL never make a KYC current at them, when reviewing can no
longer affect what the investor receives: with the reason "The KYC form has already been sent" when the form
link was sent or the investor has started or submitted the form, and with the reason "Filled in by the fund"
when the KYC was submitted or verified without a form ever being sent. A task that was already confirmed
SHALL keep its done mark rather than becoming not applicable, because the review genuinely happened.

#### Scenario: Form already sent
- **WHEN** a KYC whose form link was sent, and whose email tasks were never confirmed, is evaluated
- **THEN** both email tasks are "–" with "The KYC form has already been sent" and the journey is at a later task

#### Scenario: Form sent after the reviews were confirmed
- **WHEN** a fund user confirms both email tasks and then sends the form
- **THEN** both tasks keep their done mark and the journey moves to "Submit KYC"

#### Scenario: Filled in by the fund
- **WHEN** a KYC was submitted with no form ever sent
- **THEN** both email tasks and "Send KYC form" are "–" with "Filled in by the fund"

#### Scenario: Verified early
- **WHEN** an imported KYC is verified with no form sent and no documents
- **THEN** both email tasks are "–" with "Verified without this step" and the journey is complete

### Requirement: Changing the KYC email withdraws the confirmations
Creating, editing or deleting an entity's KYC-required email SHALL withdraw the "Set up KYC email" and
"Preview the email" confirmations on every KYC of that entity that has a journey and has not yet sent its
form, move those journeys back to "Set up KYC email", and show the reason "Email template changed after
review". A KYC whose form has already been sent SHALL NOT be affected, because the investor already has the
old email. Changing any other KYC email, including the KYC reminder, SHALL NOT affect these tasks.

#### Scenario: Email edited before sending
- **WHEN** a user edits the entity's KYC-required email while a KYC has both email tasks confirmed and its form unsent
- **THEN** that KYC's journey is back at "Set up KYC email" with "Email template changed after review"

#### Scenario: Email edited after sending
- **WHEN** a user edits the entity's KYC-required email and a KYC's form was already sent
- **THEN** that KYC's journey is unchanged

#### Scenario: A new KYC email is created
- **WHEN** a user creates the entity's first KYC-required email while a KYC has both email tasks confirmed and its form unsent
- **THEN** that KYC's journey is back at "Set up KYC email" with the reason (the task names the new email again once it is re-confirmed)

#### Scenario: Another KYC email is edited
- **WHEN** a user edits the entity's KYC reminder email
- **THEN** no KYC journey moves back

### Requirement: Adding the email tasks to a journey template that already exists
Setup SHALL add missing seeded tasks to an entity's existing "Investor KYC" template, inserting "Set up KYC
email" and "Preview the email" immediately before its "Send KYC form" task, in that order, and shifting the
later tasks down. It SHALL keep every other part of the template, including renamed tasks, removed tasks,
owners, approvers and the admin's own added tasks, and SHALL NOT duplicate a task the template already has.
When the template has no "Send KYC form" task, neither task SHALL be added, because that template never
emails the investor. The rollout's dry run SHALL report, per entity, which tasks it would add without
writing anything, and the "Set up journeys" confirmation SHALL say that the tasks will be added.

#### Scenario: Existing template gains the tasks
- **WHEN** setup runs for an entity whose "Investor KYC" template has the previous nine tasks
- **THEN** the template has 11 tasks with the two email tasks first, and the other nine keep their order, kinds and settings

#### Scenario: Dry run
- **WHEN** the rollout runs without EXECUTE for such an entity
- **THEN** it reports that it would add "Set up KYC email" and "Preview the email", and the template is unchanged

#### Scenario: Re-running setup does not duplicate
- **WHEN** setup runs again after the tasks were added
- **THEN** the template still has them once and nothing is reported

#### Scenario: Admin removed the send task
- **WHEN** setup runs for an entity whose "Investor KYC" template has no "Send KYC form" task
- **THEN** neither email task is added

#### Scenario: A KYC waiting to be sent moves to the email tasks
- **WHEN** the tasks are added to an entity whose KYC was current at "Send KYC form"
- **THEN** that KYC is current at "Set up KYC email"

### Requirement: The whole journey is covered end to end
The investor KYC journey SHALL be covered by an automated end-to-end scenario in which a fund user and the
investor each act on the same KYC: the fund user confirms the two email tasks and sends the form, the
investor opens their own link and submits the KYC with its required documents, and the fund user then
validates the documents, screens AML, reviews, signs off and verifies. The scenario SHALL assert the
journey's current task after each handover and SHALL end with the journey complete.

#### Scenario: Fund user and investor walk one KYC to verified
- **WHEN** a KYC in a set-up entity is taken through every task, the fund user acting on the KYC page and the investor acting through their own emailed link
- **THEN** each task is ✓ or "–" in order, the investor never sees the journey, and the journey is complete once the KYC is verified
