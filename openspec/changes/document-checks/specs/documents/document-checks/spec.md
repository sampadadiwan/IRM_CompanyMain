# Spec Delta

## Purpose

Lets a fund configure AI checks that read values from a record's uploaded documents and fill fields,
compare them with the record, or test yes/no rules. Every outcome, including errors, is stored and
shown per check, so the results can be trusted and acted on.

## ADDED Requirements

### Requirement: Check sets per record type and variant
The system SHALL let an entity define at most one check set per record type and variant. For Investor
KYC the variants are Individual, Non-individual and All. When a record is checked, the system SHALL
use the set for the record's own variant if one exists, and otherwise the All set.

#### Scenario: Variant-specific set wins
- **WHEN** an entity has both an "Investor KYC — Individual" set and an "Investor KYC — All" set, and an individual KYC is checked
- **THEN** only the checks in the Individual set run

#### Scenario: Fallback to All
- **WHEN** an entity has only an "Investor KYC — All" set and a non-individual KYC is checked
- **THEN** the checks in the All set run

#### Scenario: Duplicate set refused
- **WHEN** a user tries to create a second "Investor KYC — Individual" set in the same entity
- **THEN** the save is refused with an error that the set already exists

### Requirement: Documents are chosen from the record's document list
The system SHALL offer, as documents to check, only the names on the entity's document list for that
record type: for KYC, the individual / non-individual KYC document lists and the KYC form's required
file fields. A check SHALL apply to a record's uploaded document when the names match ignoring case
and an "Upload " / "Attach your " prefix, by document name or owner tag, the same way required
documents are matched. When several uploaded documents match, the most recently updated one SHALL be
used.

#### Scenario: Document picked from list
- **WHEN** the entity's individual KYC document list is "CML, PAN Card, Passport" and the admin clicks Add document
- **THEN** the choices are CML, PAN Card and Passport, minus those already in the set

#### Scenario: Uploaded name differs in case and prefix
- **WHEN** a check is for "PAN Card" and the KYC has a document named "Upload pan card"
- **THEN** that document is checked

### Requirement: Three kinds of check with picked fields
Each check SHALL be one of Extract, Match or Rule, with a label (required, at most 100 characters,
unique within its document) and an optional hint (at most 255 characters). Extract and Match checks
SHALL name a field chosen from the record type's allowed fields: for KYC, a fixed list of standard
KYC fields plus the non-file custom fields of the KYC's form. Extract checks SHALL have a fill mode
of "Only if empty" (default) or "Always". Rule checks SHALL have an expected answer, Yes (default)
or No. A field outside the allowed list SHALL be refused with "Choose a field from the list".

#### Scenario: Field outside the allowed list refused
- **WHEN** an admin saves an Extract check whose field is "verified"
- **THEN** the save is refused with "Choose a field from the list"

#### Scenario: Field removed after setup
- **WHEN** a check names the custom field "dp" and that custom field is later deleted from the KYC form
- **THEN** the settings page shows "This field no longer exists — pick another" on that check

### Requirement: Presets add standard checks
The system SHALL provide presets for CML, PAN card, Aadhaar and Passport. Applying a preset SHALL add
its checks to the matching document in the set. Each check SHALL be mapped to the allowed field whose
name or label matches. A check with no matching field SHALL be added with an empty field and the
message "Pick a field before saving". A check whose label already exists for that document SHALL not
be added again.

#### Scenario: CML preset applied
- **WHEN** the admin applies the CML preset to a set where the KYC form has custom fields "dp" and "client"
- **THEN** checks for DP ID → dp, Client ID → client, PAN → PAN, First holder name → Full name and the other CML checks are added

#### Scenario: Preset applied twice
- **WHEN** the CML preset is applied a second time
- **THEN** no duplicate checks are added

### Requirement: The AI only reads values from documents
For each document, the system SHALL send the AI the document's image and each check's label and hint,
and SHALL NOT send any of the record's own values. The text of labels and hints SHALL be treated
only as text: no part of it is evaluated against the record. The AI's reply SHALL be matched to
checks by the check's identifier, never by a name chosen by the AI.

#### Scenario: Placeholder text is inert
- **WHEN** a check's hint contains "$destroy" and the checks are run
- **THEN** the hint is sent to the AI as plain text and the record is unchanged apart from the check's outcome

#### Scenario: One AI call per document
- **WHEN** a KYC has CML and PAN Card uploaded and both have checks
- **THEN** exactly two AI calls are made in the run

### Requirement: Outcomes are decided by the system
The system SHALL decide each check's result:
- **Extract**: a value found → pass, and the field is filled if the fill mode allows ("Filled <field>"),
  otherwise it is left ("Kept existing value <value>"). No value found → needs review ("Not found on
  the document").
- **Match**: both values normalised (case, spaces and punctuation ignored). Equal → pass. Different →
  fail for identifier fields, needs review for name and address fields.
- **Rule**: the answer equals the expected answer → pass, else fail.

The AI's explanation SHALL be stored with each result.

#### Scenario: Extract fills an empty field
- **WHEN** the CML's DP ID reads "IN303622" and the KYC's dp is empty
- **THEN** the result passes with "Filled DP ID" and the KYC's dp is "IN303622"

#### Scenario: Extract keeps an existing value
- **WHEN** the CML's Client ID reads "86478611", the KYC's client is "86478612" and the fill mode is Only if empty
- **THEN** the result passes with "Kept existing value 86478612" and the KYC is unchanged

#### Scenario: Extract value not found
- **WHEN** the AI reports no DP ID on the CML
- **THEN** the result is needs review with "Not found on the document"

#### Scenario: Identifier matches after normalising
- **WHEN** the document's PAN reads "abcpk 1234-f" and the KYC's PAN is "ABCPK1234F"
- **THEN** the result passes

#### Scenario: Identifier mismatch fails
- **WHEN** the document's PAN reads "ABCPK1234F" and the KYC's PAN is "ABCPK1243F"
- **THEN** the result fails showing both values

#### Scenario: Name mismatch needs review
- **WHEN** the document's first holder name reads "R. Kumar" and the KYC's full name is "Ravi Kumar"
- **THEN** the result is needs review showing both values

#### Scenario: Rule failed
- **WHEN** a Rule "Signed by holder?" expects Yes and the AI answers No
- **THEN** the result fails with the AI's explanation

### Requirement: Errors and missing documents are results, not silence
The system SHALL record, per document, a result for every check even when the document cannot be
checked:
- document not uploaded → skipped ("not uploaded");
- unsupported file type → error ("Can't read this file type — upload a PDF or image");
- unreadable AI reply → error ("The AI's reply couldn't be read — try again");
- the check's field no longer exists → error ("Field no longer exists").

A failure on one document SHALL NOT stop the other documents being checked. If the run cannot start
at all (no AI service configured or reachable, or no check set), the run SHALL be marked failed with
the reason and no record field SHALL change.

#### Scenario: Unsupported file
- **WHEN** the KYC's PAN Card is a .doc file
- **THEN** the PAN Card checks are errors with "Can't read this file type — upload a PDF or image" and the CML checks still run

#### Scenario: Document not uploaded
- **WHEN** the set has Passport checks and the KYC has no passport
- **THEN** the Passport checks are skipped and the group shows "not uploaded"

#### Scenario: AI unavailable
- **WHEN** the AI service raises a connection error
- **THEN** the run is failed with "the AI service is unavailable", the user is notified, and no KYC field changes

### Requirement: Runs, status and notifications
Each run SHALL record the record, the check set, who started it, how it was started (manual, bulk,
test), its status (queued, running, done, done with errors, failed), its times and counts. Only one
run per record SHALL be queued or running at a time: a second request SHALL be refused with "Document
Checks are already running for <record>". The starting user SHALL be notified on start and finish,
with counts, as a warning when anything failed, errored or needs review.

#### Scenario: Run summary notification
- **WHEN** a run finishes with 9 passed, 1 failed and 1 error
- **THEN** the run is "done with errors" and the user is notified "Document Checks finished for Asha Rao: 9 passed, 1 failed, 1 error"

#### Scenario: Second run refused
- **WHEN** a run is running for a KYC and the user clicks Run Document Checks again
- **THEN** no second run is created and the user sees "Document Checks are already running for Asha Rao"

### Requirement: Current results and staleness
A record's current results SHALL be those of its latest finished, non-test run. Each result SHALL
remember which version of the document file it read. When the document's file is replaced after the
run, its results SHALL show as out of date ("Out of date — document changed after this run").

#### Scenario: Re-uploaded document is out of date
- **WHEN** a KYC's CML is re-uploaded after its last run
- **THEN** the CML group shows "Out of date — document changed after this run" and the other groups do not

#### Scenario: New run replaces old results
- **WHEN** a document is removed from a KYC and the checks are run again
- **THEN** the current results contain no results for the removed document

### Requirement: Test run changes nothing
A test run SHALL run the checks against one chosen record and show the results with the banner "Test
run — nothing was saved to this KYC". It SHALL NOT write any field on the record, SHALL NOT become the
record's current results, and SHALL NOT affect the record's journey.

#### Scenario: Test run on a KYC
- **WHEN** an admin tests the Individual set on Asha Rao's KYC and DP ID would be filled
- **THEN** the result shows "Filled DP ID" with the test banner, and Asha Rao's dp is still empty

### Requirement: Accepting a result
A user who can update the record SHALL be able to accept a failed or needs-review result with a
required reason (at most 255 characters; error "Give a reason for accepting"). The system SHALL store
who accepted, when and why, show it on the result, and re-assess the record.

#### Scenario: Accept a mismatch
- **WHEN** Priya accepts the "First holder" needs-review result with reason "Initial matches passport"
- **THEN** the row shows "Accepted by Priya Shah — 'Initial matches passport'" and the record is re-assessed

#### Scenario: Accept without reason
- **WHEN** Priya clicks Accept without a reason
- **THEN** the acceptance is refused with "Give a reason for accepting"

### Requirement: Record is validated only when every current result is settled
A record SHALL be treated as having all documents valid exactly when its current results exist and
every result is passed or accepted, with none out of date. For KYC this SHALL set `all_docs_valid`.

#### Scenario: Skipped document blocks validation
- **WHEN** every result passes except the Passport checks, which are skipped as not uploaded
- **THEN** the KYC is not treated as having all documents valid

#### Scenario: Accepted result counts
- **WHEN** the only non-passing result is accepted
- **THEN** the KYC is treated as having all documents valid

### Requirement: KYC journey Validate documents step uses Document Checks
The KYC journey's *Validate documents* step SHALL be done ("Validated by AI") when the KYC's current
results settle it as above and the run finished after the step was last reset. It SHALL ask for review
with "Document Checks found N problems — check them and mark reviewed" when current results have any
failed, needs-review, error, skipped or out-of-date result. It SHALL show "Documents not checked yet —
run Document Checks or check them and mark reviewed" when a check set applies but no run exists. It
SHALL show "Check the documents and mark reviewed" when no check set applies. Accepting a result or
finishing a run SHALL re-evaluate the journey.

#### Scenario: All passed completes the step
- **WHEN** a KYC at Validate documents has a finished run where every result passed
- **THEN** the step is done with "Validated by AI" without anyone clicking

#### Scenario: Problems ask for review
- **WHEN** the latest run has 1 failed and 1 error result
- **THEN** the step asks "Document Checks found 2 problems — check them and mark reviewed"

#### Scenario: Re-upload resets the step
- **WHEN** a KYC's step was done "Validated by AI" and its CML is then re-uploaded
- **THEN** the step goes back to asking for review

### Requirement: Entity-wide results list
The system SHALL provide a list of current results across the entity's records, filterable by status
(passed, failed, needs review, error, skipped, out of date), document, check set and run date. Users
SHALL be able to select rows and re-run checks for their records.

#### Scenario: Filter to problems
- **WHEN** the user filters to Failed and Error
- **THEN** only current results with those statuses are listed

#### Scenario: Bulk re-run
- **WHEN** the user selects three KYCs and clicks Re-run selected
- **THEN** a run is queued for each of the three KYCs

### Requirement: Access and isolation
Setup pages SHALL be available only to users of an entity with the "Doc LLM validation" permission.
Results SHALL be visible only to users of the record's own entity who can view the record, and never to
investor users. No user SHALL see or act on another entity's check sets, runs or results.

#### Scenario: Other entity blocked
- **WHEN** a user from another entity opens a check set or run URL directly
- **THEN** access is denied

#### Scenario: Investor never sees results
- **WHEN** an investor user opens their KYC
- **THEN** no Document Checks tab or result is shown

### Requirement: Converting legacy Doc Questions
The system SHALL provide a support-run conversion, a dry run by default, that for each entity turns
its Investor KYC Doc Questions into checks in the entity's "Investor KYC — All" set:
- Extraction questions, and Validation questions whose text asks to extract, become Extract checks.
  The label is taken from the question, and the full question is kept as the hint.
- The field is taken from "field <name>" in the response hint, or from the label, resolved against the
  allowed fields by the same normalisation the old feature used.
- A question whose document is not on the entity's list, or whose field cannot be resolved, is not
  converted and is listed in the report.

The report SHALL list per entity: converted checks with their fields, and unconverted questions with
the reason. Running it again SHALL NOT duplicate checks. Legacy answers SHALL remain viewable on each
KYC under "Earlier AI answers".

#### Scenario: Dry run report
- **WHEN** support runs the conversion without the execute flag for Pravega Ventures
- **THEN** a report lists each question with its target field or the reason it can't convert, and no check is created

#### Scenario: Unresolvable field reported
- **WHEN** a question's hint says "Extract to field mobil_contact" and no such field exists
- **THEN** the question is listed as unconverted with "Field mobil_contact not found"

#### Scenario: Execute converts once
- **WHEN** support runs the conversion with the execute flag twice
- **THEN** the checks exist once

