# Spec Delta

## Purpose

An ops-run assistant that onboards a fresh client entity from the client's own workbook, writing
only through the application's existing import and settings endpoints, with sandbox, ordering,
approval and reconciliation guarantees.

## ADDED Requirements

### Requirement: Fresh entities only
The assistant SHALL refuse to write to an entity that already has investors, funds, or users other
than the operating ops user.

#### Scenario: Fresh entity accepted
- **WHEN** ops starts an onboarding for an entity with no investors, no funds and only the ops user
- **THEN** the assistant reports the entity as fresh and proceeds to setup

#### Scenario: Entity in use refused
- **WHEN** ops starts an onboarding for an entity that has 14 investors
- **THEN** every write tool refuses with "Entity <id> is not fresh (14 investors)" and nothing is written

### Requirement: Sandbox forced on
The first write of every onboarding SHALL turn the entity's sandbox on with the ops user's email as
the sandbox email. Before every later write the assistant SHALL read the sandbox setting back and
refuse the write if it is off. The assistant SHALL provide no way to turn sandbox off.

#### Scenario: Sandbox set first
- **WHEN** the assistant performs its first write on a fresh entity
- **THEN** that write sets sandbox on and sandbox emails to the ops user's email, and the read-back confirms it

#### Scenario: Sandbox found off
- **WHEN** sandbox has been turned off in the UI and the assistant attempts any write
- **THEN** the write is refused with "Sandbox is off — stopping" and nothing is written

#### Scenario: Turning sandbox off is impossible
- **WHEN** the assistant asks to update entity settings with sandbox off
- **THEN** the request is refused and the setting is unchanged

### Requirement: Writes only through the application
Every change to client data SHALL go through the application's existing HTTP endpoints as the ops
user. The assistant SHALL have no database credentials, no network route to the database, no
writable copy of the application code, and its shell commands SHALL have no network access.

#### Scenario: Shell cannot reach the app or the database
- **WHEN** a shell command in the assistant's environment tries to open a connection to the app or the database
- **THEN** the connection is refused

#### Scenario: App code is read-only
- **WHEN** the assistant tries to write a file inside the application code snapshot
- **THEN** the write fails and the snapshot is unchanged

#### Scenario: Token not visible
- **WHEN** the assistant tries to read the ops user's token through its file or shell tools
- **THEN** the read is denied

### Requirement: Import order with investor access last
Imports SHALL follow the order: funds and unit settings, investors, KYCs, commitments, calls,
remittances, remittance payments, distributions, distribution payments, account entries and
documents. Investor access and investor advisors SHALL be refused until every earlier type that was
imported is reconciled. Custom-field uploads are allowed at any point.

#### Scenario: Out-of-order upload refused
- **WHEN** the assistant uploads commitments before any investors were imported
- **THEN** the upload is refused naming the missing earlier step

#### Scenario: Investor access refused early
- **WHEN** remittances are imported but not reconciled and the assistant uploads investor access
- **THEN** the upload is refused with "Investor access waits until remittances are reconciled"

#### Scenario: Investor access allowed last
- **WHEN** every imported type is reconciled and ops approves the investor access upload
- **THEN** the upload is made

### Requirement: Approvals and waivers
Read tools SHALL run without asking. Every write SHALL ask ops for approval unless ops has granted a
waiver for that client and import type. A waiver SHALL only be created by a human-approved request,
and SHALL never apply to undo, investor access, or investor advisors.

#### Scenario: Write asks
- **WHEN** the assistant uploads 120 commitments with no waiver
- **THEN** ops is asked to approve before the upload is made

#### Scenario: Waived type does not ask
- **WHEN** ops has approved a waiver for KYCs on this client and the assistant uploads KYCs
- **THEN** the upload is made without asking and the journal records it as waived

#### Scenario: Waiver cannot be self-granted
- **WHEN** the assistant tries to record a waiver by editing files or running shell commands
- **THEN** the attempt is denied and no waiver exists

#### Scenario: Undo and access never waived
- **WHEN** a waiver is requested for undo or investor access
- **THEN** it is refused, and those writes always ask

### Requirement: Every column accounted for
For each import, every column of the client's sheet SHALL be recorded as exactly one of: mapped to a
template column, a new custom field, or dropped with a reason. Custom fields SHALL be created with a
type inferred from the data before the import that uses them.

#### Scenario: Column accounting shown
- **WHEN** the assistant proposes a mapping for a 9-column sheet
- **THEN** the summary shows each column's outcome and the check "9 = mapped + custom + dropped"

#### Scenario: Typed custom field before import
- **WHEN** a commitments sheet has a "Lock-in Till" column of dates with no template match
- **THEN** a date custom field is created on the commitment form before the commitments upload

### Requirement: Check before upload
The assistant SHALL check each generated upload file against the template's columns and rules
before uploading it, and SHALL not upload a file with known problems.

#### Scenario: Problem caught before upload
- **WHEN** a generated file is missing a required template column
- **THEN** the assistant reports the problem and does not upload

### Requirement: Failures explained, fix or undo
When an upload has failed rows, the assistant SHALL read the upload's results file, explain each
failed row with its cause and a proposed fix, and stop for ops to choose fix-and-reimport or undo.
Undo SHALL delete only the data created by that upload, through the application.

#### Scenario: Failed rows explained
- **WHEN** 2 of 120 commitment rows fail with "Investor not found"
- **THEN** the assistant lists both rows, the cause and a proposed fix, and waits for ops

#### Scenario: Undo one upload
- **WHEN** ops approves undo of upload 9912
- **THEN** only the records created by upload 9912 are deleted and the journal records it

### Requirement: Reconciliation
After each import the assistant SHALL compare the client's sheet with CapHive: row count and money
totals, overall and per unit class. A type is reconciled only when every figure matches.

#### Scenario: Totals match
- **WHEN** the sheet has 120 commitments totalling ₹250.00 Cr and CapHive has the same
- **THEN** the type is marked reconciled

#### Scenario: Totals differ
- **WHEN** CapHive's total is ₹249.50 Cr against the sheet's ₹250.00 Cr
- **THEN** the type is not reconciled and the assistant shows the differing rows

### Requirement: Journal and resume
Every write, approval, waiver, refusal and reconciliation SHALL be recorded in the client's journal
with the upload id. A restarted assistant SHALL resume from the recorded state.

#### Scenario: Resume next day
- **WHEN** ops restarts the assistant after investors and KYCs were done
- **THEN** it reports those as done and proposes commitments next

### Requirement: App problems reported, not patched
When the cause of a failure is in the application, or the application's API lacks something the
assistant needs, the assistant SHALL write it up with where, why and a suggested fix, and pause that
step.

#### Scenario: Missing API data pauses
- **WHEN** an upload's result does not include row counts
- **THEN** the assistant records an API gap and pauses that import without guessing the outcome
