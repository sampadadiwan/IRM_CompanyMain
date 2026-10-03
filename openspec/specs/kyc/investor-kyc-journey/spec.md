# kyc/investor-kyc-journey Specification

## Purpose
Shows every new investor KYC's progress from "created" to "verified" as a journey on the KYC page, says
what the current task needs, keeps the page live, and makes a fund user's "complete" tick and bulk Unverify
behave consistently with the rest of the KYC screens.

## Requirements

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

### Requirement: One default journey, or one per KYC form type
By default the seeded journey SHALL apply to every KYC through its single catch-all rule. An admin SHALL be
able to give any KYC form type its own journey by adding an auto-assignment rule for that form type with a
higher priority than the catch-all; KYCs of every other form type SHALL keep the default journey. The rule
form SHALL offer, for KYC rules, a "KYC form type" list of the entity's KYC form types (labelled by
individual / non-individual and tag) that sets the form-type condition. Workflow templates SHALL offer a
Duplicate action that creates "Copy of <name>" with the same steps, kinds, checks, skip checks, owners,
approvers and settings, not linked to setup.

#### Scenario: One journey for all form types
- **WHEN** an entity is set up and KYCs are created with the "Individual — Default", "Individual — Fund IV" and "Non Individual — Default" form types
- **THEN** all three get the "Investor KYC" journey

#### Scenario: Specific journey for one form type
- **WHEN** an admin duplicates "Investor KYC", renames the copy "Investor KYC — Fund IV", and adds a rule for it picking the form type "Individual — Fund IV" with priority 50
- **THEN** a new "Individual — Fund IV" KYC gets the copy, while new "Individual — Default" and "Non Individual — Fund IV" KYCs still get "Investor KYC"

#### Scenario: Form type list on the rule form
- **WHEN** a company admin creates an auto-assignment rule for KYCs
- **THEN** the form lists only that entity's KYC form types, and picking one saves the form-type condition

#### Scenario: Duplicate a template
- **WHEN** a company admin clicks Duplicate on a workflow template
- **THEN** "Copy of <name>" exists with identical steps, and re-running setup neither treats it as the seeded template nor changes it

### Requirement: New KYCs only
Only KYCs created after an entity is set up SHALL get a journey. Setup SHALL NOT launch a journey on any
existing KYC, whose page SHALL stay exactly as today.

#### Scenario: Existing KYC
- **WHEN** an entity is set up and a user opens a KYC created before
- **THEN** the page shows no step bar

#### Scenario: Entity not set up
- **WHEN** a KYC is created in an entity that was never set up
- **THEN** no journey is launched

### Requirement: Three setup entry points
Setup SHALL be available as (a) a rollout task that is a dry run unless told to execute and can be limited
to one entity, (b) part of new fund-company setup, and (c) a "Set up investor KYC journeys" item in the
Workflow Templates page's Set up journeys menu. All three SHALL run the same setup. The item SHALL be shown
only to company admins of Investment Fund and Angel Fund entities; while something is missing it SHALL
confirm what it will add and then report what it added; once everything exists it SHALL show a disabled
"✓ Investor KYC journeys set up".

#### Scenario: Dry run
- **WHEN** the rollout task runs without the execute flag
- **THEN** it prints per Investment Fund and Angel Fund entity what it would add and writes nothing

#### Scenario: Setup from the UI
- **WHEN** a company admin clicks the item and confirms
- **THEN** the notice reads "Investor KYC journeys set up: KYC journey, auto-assignment rule. New KYCs will get a journey." and the item turns into the disabled set-up state

#### Scenario: Not offered to others
- **WHEN** an employee who is not a company admin opens Workflow Templates, or posts the setup request directly
- **THEN** the item is not shown and the request is refused

### Requirement: Sending and submitting
"Send KYC form" SHALL say what is missing and offer the control that does it: "The KYC form has not been sent
— send it, or fill it in and tick complete" with "Send KYC Required Notification" when the investor has users
who can receive it, otherwise "The investor has no users to send the form to — add one, or fill it in
yourself" with "Edit". "Submit KYC" SHALL show "Waiting for the investor — form sent on <date>" with "Send KYC
Reminder" after a link was sent, "The investor saved a draft on <date> but has not submitted" after a draft,
and "Not submitted yet — fill it in and tick complete" with "Edit" when no form was sent.

#### Scenario: Form sent
- **WHEN** the fund sends the KYC Required Notification on a new KYC
- **THEN** "Send KYC form" is ✓ and "Submit KYC" is current with "Waiting for the investor — form sent on <date>"

#### Scenario: Investor submits
- **WHEN** the investor submits the form from the emailed link
- **THEN** "Submit KYC" is ✓ and the fund user's open KYC page updates without a reload

#### Scenario: Documents uploaded first
- **WHEN** the investor uses the documents-first form, uploads documents and the form is pre-filled, but the investor has not submitted
- **THEN** "Submit KYC" stays current and no later task is completed by the pre-filling

### Requirement: Fund user marks a KYC complete
When a fund user saves a KYC with "I confirm all details provided are complete…" newly ticked, the KYC SHALL
become completed with the current time as its submitted time. Unticking it SHALL keep its existing behaviour
(back to draft).

#### Scenario: Fund fills in the KYC
- **WHEN** a fund user fills in a KYC that was never sent, ticks "I confirm … complete" and saves
- **THEN** the KYC is completed, "Send KYC form" shows "–" "Filled in by the fund" and "Submit KYC" is ✓

#### Scenario: Fund unticks complete
- **WHEN** a fund user unticks "I confirm … complete" on a completed KYC and saves
- **THEN** the KYC is back in draft and the journey moves back to "Submit KYC"

### Requirement: Required documents
"Upload required documents" SHALL list the missing names, e.g. "2 required documents missing: PAN Card,
Address Proof", with a button that opens the Documents tab.

#### Scenario: Missing documents
- **WHEN** the entity requires "PAN Card" and "Address Proof" for individuals and the KYC has only "Photo"
- **THEN** the task is current with "2 required documents missing: PAN Card, Address Proof"

#### Scenario: Nothing required
- **WHEN** the entity has no required document list and the KYC form has no required document fields
- **THEN** the task shows "–" "No documents are required"

### Requirement: Validating documents
"Validate documents" SHALL pass by itself, showing "Validated by AI", when the KYC's Document Checks have
current results and none of its items needs attention (items resolved with Use document value or Mark as OK
count as OK). Otherwise it SHALL be current with "Mark reviewed" and a message:
- "Documents not checked yet — check documents or mark reviewed", with "Check documents", when the entity
  has document checks for the KYC's documents and they haven't been checked;
- "<n> document items need attention — resolve them or mark reviewed", with "Open document checks", when
  the current results have items needing attention;
- "Check the documents and mark reviewed" when the entity has no document checks for the KYC's documents.

Uploading, replacing or deleting a KYC document after the task passed SHALL move it back with "Documents
changed after validation". It SHALL then pass only on a newer completed document check, a newer resolution,
or a newer confirmation.

#### Scenario: AI full pass
- **WHEN** a document check finishes and no item needs attention
- **THEN** the task is ✓ "Validated by AI" with no click, and the open page updates

#### Scenario: AI could not validate
- **WHEN** a document check finishes with 2 items needing attention
- **THEN** the task is current with "2 document items need attention — resolve them or mark reviewed", and a user's Mark reviewed passes it as "Reviewed by <user>"

#### Scenario: Resolving the last item completes the task
- **WHEN** the only item needing attention is marked OK
- **THEN** the task is ✓ "Validated by AI" without anyone clicking Mark reviewed

#### Scenario: Not checked yet
- **WHEN** the entity has checks for the KYC's documents and the KYC has never been checked
- **THEN** the task is current with "Documents not checked yet — check documents or mark reviewed"

#### Scenario: No document questions
- **WHEN** the entity has no document checks for the KYC's documents
- **THEN** the task is current with "Check the documents and mark reviewed" until a user marks it reviewed

#### Scenario: Document replaced after validation
- **WHEN** a user replaces the PAN Card after the task passed
- **THEN** the journey moves back to "Validate documents" with "Documents changed after validation"

### Requirement: AML screening
When AML is enabled for the entity, "Run AML screening" SHALL be current with "Generate AML Report" until the
KYC has an AML result, showing "AML report requested — waiting for the result" while a report is pending.
"Clear AML match" SHALL be current with "AML found a potential match — review the report and override it if
it is a false positive" and "View AML Reports" while the result is a potential match with no override, SHALL
show "AML match confirmed — this KYC should not be verified" when it was overridden to a potential match, and
SHALL pass as "Overridden by <user>: <reason>" when overridden to no match.

#### Scenario: Potential match
- **WHEN** the AML report comes back as a potential match
- **THEN** "Run AML screening" is ✓ and "Clear AML match" is current with the potential-match message

#### Scenario: Override clears match
- **WHEN** a user overrides the AML status to no match with a reason
- **THEN** "Clear AML match" is ✓ "Overridden by <user>: <reason>"

#### Scenario: AML not enabled
- **WHEN** the entity does not have AML enabled
- **THEN** both AML tasks show "–" "AML screening is not enabled"

### Requirement: Review, sign-off and verify
"Review KYC" SHALL be current with "Mark reviewed" until a user confirms it. "Compliance sign-off" SHALL show
"–" "No approver set — pick one on this step in the journey template" until an approver is set on the step.
"Verify KYC" SHALL be current with "Not verified yet" and the "Verify" button until the KYC is verified.

#### Scenario: Verify from the panel
- **WHEN** a user with the KYC approve permission clicks the panel's "Verify"
- **THEN** the page's Verify control runs and the journey is complete

### Requirement: Panel for fund users only
The step bar and panel SHALL be shown on a KYC with a journey to fund users who can view it, and SHALL NOT be
shown to investors (logged in or via an emailed link). Warnings SHALL show until the KYC is verified: PAN
verification failed, bank verification failed, the investor has no users to email, and the KYC's expiry date
has passed.

#### Scenario: Investor opens their KYC
- **WHEN** an investor opens their KYC page
- **THEN** no step bar, panel or warnings are shown

#### Scenario: Other entity
- **WHEN** a user of another entity requests the KYC's journey panel
- **THEN** access is denied

#### Scenario: Bank verification failed warning
- **WHEN** the KYC's bank verification failed and the KYC is not verified
- **THEN** the panel shows "Bank account verification failed"

### Requirement: Moving back
These actions SHALL move the journey back when a task no longer passes, reset later confirmations and
sign-offs given before the action, and name the action and user: UnVerify (single and bulk) "Unverified",
Request Updates "Updates requested", a fund user unticking complete "Marked incomplete", deleting a document
"Document deleted", a new AML result that is a potential match "New AML result". Editing a KYC's details, or
extracting data into it from its documents, after "Review KYC" passed SHALL move it back to "Review KYC" with
"KYC details changed after review". An action on a KYC whose tasks have not reached the affected task SHALL
NOT record a move back.

#### Scenario: Request Updates
- **WHEN** a user requests updates on a KYC at "Compliance sign-off" whose review was confirmed
- **THEN** the journey moves back to "Submit KYC" with "Updates requested by <user>", and the Review KYC confirmation and any sign-off are reset

#### Scenario: UnVerify
- **WHEN** a user clicks UnVerify on a verified KYC whose tasks were all done
- **THEN** the journey moves back to "Verify KYC" with "Unverified by <user>"

#### Scenario: Edit after review
- **WHEN** a fund user edits the KYC's address after "Review KYC" was confirmed
- **THEN** the journey moves back to "Review KYC" with "KYC details changed after review"

#### Scenario: Document uploaded before validation is reached
- **WHEN** a document is uploaded while "Submit KYC" is current
- **THEN** no move back is recorded

### Requirement: Bulk Unverify matches UnVerify
Bulk Unverify from the KYC list SHALL set each KYC to completed, the same as the single UnVerify, and each
affected journey SHALL be re-checked once.

#### Scenario: Bulk Unverify
- **WHEN** a user bulk-unverifies three verified KYCs
- **THEN** each is completed (not link sent), the investor cannot edit it, and each journey is back at "Verify KYC"

### Requirement: Live updates
The KYC page SHALL update its step bar without a reload when the KYC changes from the page, a background job
(form sending, AI validation, AML report, import, bulk action) or another user's action.

#### Scenario: AML report arrives
- **WHEN** a user has the KYC open at "Run AML screening" and the AML report job finishes
- **THEN** the step bar moves on without a reload

#### Scenario: Colleague bulk-verifies
- **WHEN** a colleague bulk-verifies KYCs including the open one
- **THEN** the open page shows "Verify KYC" ✓ without a reload

### Requirement: No journey, no work
Actions on KYCs without a journey SHALL behave exactly as today and SHALL NOT evaluate any journey.

#### Scenario: KYC created before setup
- **WHEN** a user verifies or bulk-verifies KYCs created before setup
- **THEN** they are verified as today and no journey evaluation runs for them

### Requirement: Delete
A KYC with a journey SHALL be deletable under the existing rules.

#### Scenario: Delete with journey
- **WHEN** a user deletes an unverified KYC that has a journey
- **THEN** the KYC is deleted

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
