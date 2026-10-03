# Spec Delta

## Purpose

Shows every new investor KYC's progress from "created" to "verified" as a journey on the KYC page, says
what the current task needs, keeps the page live, and makes a fund user's "complete" tick and bulk Unverify
behave consistently with the rest of the KYC screens.

## ADDED Requirements

### Requirement: Seeded KYC journey
Each set-up entity SHALL have one journey template, "Investor KYC", each step carrying a description. Setup
SHALL also create one auto-assignment rule launching it on every new KYC (no conditions) when the entity has
no KYC rule yet. Setup SHALL be idempotent, SHALL keep an admin's edits and added steps, and SHALL turn on
the entity's workflow templates permission.

The tasks, in order:

| # | Task | Kind | Done when | Not applicable when |
|---|---|---|---|---|
| 1 | Send KYC form | system | the KYC form link has been sent to the investor, or the investor has started or submitted it | the KYC was submitted or verified without a form ever being sent ("Filled in by the fund") |
| 2 | Submit KYC | system | the KYC is completed or verified | — |
| 3 | Upload required documents | system | a document exists for every required document name | no document is required |
| 4 | Validate documents | acknowledge | AI validation ran on the KYC and every answer passed, or a user confirmed it | — |
| 5 | Run AML screening | system | the KYC has an AML result | AML is not enabled for the entity |
| 6 | Clear AML match | system | the AML result was manually overridden to no match | AML is not enabled, or the AML result is no match without an override |
| 7 | Review KYC | acknowledge | a user confirmed it | — |
| 8 | Compliance sign-off | human | an approver signed off | no approver is set on the step |
| 9 | Verify KYC | system | the KYC is verified | — |

"Required document names" are the entity's required KYC document list for the KYC's type (individual or
non-individual) together with the KYC form's required document fields. Every task before "Verify KYC" SHALL
also be not applicable, with the reason "Verified without this step", when the KYC is verified and that task
is not otherwise done.

#### Scenario: Setting up an entity
- **WHEN** setup runs for a fund entity with no KYC journey
- **THEN** the "Investor KYC" template exists with the tasks above, the rule exists, and workflow templates are enabled

#### Scenario: Re-running setup keeps edits
- **WHEN** setup runs again after an admin picked an approver on "Compliance sign-off" and removed "Run AML screening"
- **THEN** no template or rule is duplicated and the admin's changes are kept

#### Scenario: Entity already has a KYC rule
- **WHEN** setup runs for an entity that already has an auto-assignment rule for KYCs
- **THEN** the template is created, no rule is added, and the dry run says so

#### Scenario: Imported verified KYC
- **WHEN** a KYC is imported as verified into a set-up entity, with no documents and no AML result
- **THEN** it gets the journey, every task before "Verify KYC" is ✓ or "–" ("Verified without this step"), and the journey is complete

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
"Validate documents" SHALL pass by itself, showing "Validated by AI", when AI validation has run on the KYC
and every answer passed. Otherwise it SHALL be current with "Mark reviewed" and a message: "Documents not
validated yet — run AI validation or check them and mark reviewed" with "Validate Document Data" when the
entity has document questions and AI validation has not run; "AI could not validate <n> of <m> answers —
check them and mark reviewed" with "Open validation" when it ran and some answers did not pass; "Check the
documents and mark reviewed" when the entity has no document questions. Uploading, replacing or deleting a
KYC document after the task passed SHALL move it back with "Documents changed after validation"; it SHALL
then pass only on a newer AI validation or a newer confirmation.

#### Scenario: AI full pass
- **WHEN** AI validation finishes and every answer passed
- **THEN** the task is ✓ "Validated by AI" with no click, and the open page updates

#### Scenario: AI could not validate
- **WHEN** AI validation finishes and 2 of 12 answers did not pass
- **THEN** the task is current with "AI could not validate 2 of 12 answers — check them and mark reviewed", and a user's Mark reviewed passes it as "Reviewed by <user>"

#### Scenario: No document questions
- **WHEN** the entity has no document questions for KYCs
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
