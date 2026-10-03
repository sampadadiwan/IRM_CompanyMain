# Spec Delta

## Purpose

Lets a fund configure AI checks that read values from a record's uploaded documents and fill in fields,
compare them with the record, or answer yes-no questions. Each item ends as OK or Needs attention, with
a plain reason and an on-the-spot way to resolve it.

## ADDED Requirements

### Requirement: One checks page per record type, a card per document
The system SHALL give each entity one Document Checks page per record type. For Investor KYC it SHALL
show one card per distinct document name taken from the entity's individual KYC document list, its
non-individual KYC document list and the KYC form's required file fields. Cards with checks SHALL come
first. Cards without checks SHALL be listed under "Other documents" with "No checks yet". With no
document names, the page SHALL say "Add the documents you collect in Settings → KYC documents.
They'll appear here."

#### Scenario: Cards from the KYC lists
- **WHEN** the individual list is "CML, PAN Card", the non-individual list is "PAN Card, Board Resolution" and the KYC forms have no required file fields
- **THEN** the page shows exactly three cards, CML, PAN Card and Board Resolution, with PAN Card once

#### Scenario: No documents yet
- **WHEN** the entity has no KYC document names
- **THEN** the page shows "Add the documents you collect in Settings → KYC documents. They'll appear here."

### Requirement: Checks are picked, not typed
A check SHALL be one of *Fill in*, *Compare* or *Yes-no question*. Fill in and Compare SHALL name a KYC
field picked from the record type's allowed fields: for KYC, a fixed list of standard fields plus the
non-file custom fields of the entity's KYC forms. A field SHALL be used at most once per document card.
*Look for* (at most 100 characters) SHALL default to the picked field's label. *Tip for the AI* SHALL be
optional (at most 255 characters). Fill in SHALL have *Replace existing values*, off by default.
Yes-no SHALL have an expected answer, Yes by default. Each card SHALL save on its own. A row that is
incomplete or invalid SHALL block that card's save and be marked on the row: "Pick a KYC field",
"Already used on this card" or "Say what to look for". A field outside the allowed list SHALL be refused
with "Pick a KYC field".

#### Scenario: Look for fills itself
- **WHEN** the admin adds a check on CML and picks the KYC field "DP ID"
- **THEN** Look for shows "DP ID"

#### Scenario: Same field twice refused
- **WHEN** the admin adds a second CML check for the field "PAN" and saves
- **THEN** the card is not saved and the row says "Already used on this card"

#### Scenario: Field outside the allowed list refused
- **WHEN** a request tries to save a Fill in check whose field is "verified"
- **THEN** the save is refused with "Pick a KYC field"

#### Scenario: Field removed after setup
- **WHEN** a check uses the custom field "dp" and that custom field is deleted from the KYC form
- **THEN** the page shows the banner "1 check uses a field that no longer exists — Show me" and the row "This field no longer exists — pick another"

### Requirement: Presets add only what they can map
A card whose document name contains "CML", "PAN", "Aadhaar" or "Passport" (any case) SHALL offer that
preset. Applying it SHALL add, as unsaved rows, only the preset's checks whose field exists on the KYC
and isn't already on the card. It SHALL list the rest under the card as "Not added: <labels> — your KYC
form has no matching field. Add a custom field to the KYC form, then use the preset again."

#### Scenario: CML preset with missing fields
- **WHEN** the admin uses the CML preset and the KYC form has custom fields "dp" and "client" but no email or mobile field
- **THEN** rows for DP ID, Client ID, Address, Bank account number, IFSC code, PAN, Full name and "Is it signed by the holder?" are added, and "Not added: Email, Mobile — …" is shown

#### Scenario: Preset used twice
- **WHEN** the CML preset is used again on a saved CML card
- **THEN** no row is added for checks already on the card

#### Scenario: No preset for other documents
- **WHEN** a card is named "Board Resolution"
- **THEN** it offers no preset button

### Requirement: A KYC's documents are those on its own list
A record's checks SHALL be those for the document names on that record's own document list. For KYC that
is the list for its type (individual or non-individual) plus its form's required file fields. A check
SHALL read the record's uploaded document whose name or owner tag matches, ignoring case and an "Upload
" / "Attach your " prefix, the same way required documents are matched, taking the most recently updated
one when several match.

#### Scenario: Company KYC ignores individual-only documents
- **WHEN** Passport is only on the individual list and a non-individual KYC is checked
- **THEN** no Passport items appear for that KYC

#### Scenario: Uploaded name differs in case and prefix
- **WHEN** a check is for "PAN Card" and the KYC has a document named "Upload pan card"
- **THEN** that document is read

### Requirement: The AI only reads values from documents
For each document, the system SHALL send the AI the document's image and each check's look-for text and
tip, and SHALL NOT send any of the record's values. Look-for text and tips SHALL be treated only as
text: no part of them is evaluated against the record. The AI's reply SHALL be matched to checks by the
check's identifier, never by a name chosen by the AI. Exactly one AI call SHALL be made per document
read.

#### Scenario: Placeholder text is inert
- **WHEN** a tip contains "$destroy" and the documents are checked
- **THEN** the tip is sent as plain text and the record is unchanged apart from the check's outcome

#### Scenario: One AI call per document
- **WHEN** a KYC has CML and PAN Card uploaded and both have checks
- **THEN** exactly two AI calls are made

### Requirement: Every item ends OK or Needs attention, with a reason
The system SHALL give every check on every listed document one outcome, either OK or Needs attention,
with a reason shown in plain words:
- **Fill in**: value found and field empty → OK "filled in: V", and the field is set. Value found, field
  set, Replace off → OK "kept your value X (document says V)", unchanged. Replace on → OK "replaced X
  with V". Value not found → Needs attention "not found on this document". A date value that can't be
  read → Needs attention "couldn't read a date from 'V'".
- **Compare**: both values normalised by ignoring case, spaces and punctuation, and word order for
  name and address fields. Equal → OK "matches". KYC empty → Needs attention "the KYC has no value
  (document says V)". Different → Needs attention "doesn't match", showing both values. Not found →
  Needs attention "not found on this document".
- **Yes-no**: the answer equals the expected one → OK. Otherwise → Needs attention "answered <answer>",
  with the AI's reason.

#### Scenario: Fill in an empty field
- **WHEN** the CML's DP ID reads "IN303622" and the KYC's DP ID is empty
- **THEN** the item is OK "filled in: IN303622" and the KYC's DP ID is "IN303622"

#### Scenario: Fill in keeps an existing value
- **WHEN** the CML's Client ID reads "86478611", the KYC's Client ID is "86478612" and Replace is off
- **THEN** the item is OK "kept your value 86478612 (document says 86478611)" and the KYC is unchanged

#### Scenario: Value not found
- **WHEN** the AI finds no DP ID on the CML
- **THEN** the item needs attention "not found on this document"

#### Scenario: Compare ignores case and punctuation
- **WHEN** the document's PAN reads "abcpk 1234-f" and the KYC's PAN is "ABCPK1234F"
- **THEN** the item is OK "matches"

#### Scenario: Compare ignores word order for names
- **WHEN** the document's holder name reads "RAO ASHA" and the KYC's full name is "Asha Rao"
- **THEN** the item is OK "matches"

#### Scenario: Compare mismatch
- **WHEN** the document's PAN reads "ABCPK1234F" and the KYC's PAN is "ABCPK1243F"
- **THEN** the item needs attention "doesn't match" with "Document: ABCPK1234F · KYC: ABCPK1243F"

#### Scenario: Yes-no not as expected
- **WHEN** "Is it signed by the holder?" expects Yes and the AI answers No
- **THEN** the item needs attention "answered No" with the AI's reason

### Requirement: Problems reading a document are items, not silence
When a listed document can't be read, each of its checks SHALL still have an outcome of Needs attention:
not uploaded → "Not uploaded yet"; unsupported file type → "Couldn't read this file — upload it as a PDF
or image"; the AI's reply can't be understood → "Couldn't read the AI's answer for this document"; the
check's field no longer exists → "this check's KYC field no longer exists". A problem with one document
SHALL NOT stop the others being read. If the check can't run at all (AI service not configured or not
reachable, or no checks for the record's documents), the attempt SHALL be recorded as couldn't run, with
the reason, no record field SHALL change, and the earlier results SHALL stay as the current results.

#### Scenario: Unsupported file
- **WHEN** the KYC's PAN Card is a .doc file
- **THEN** its items need attention "Couldn't read this file — upload it as a PDF or image" and the CML is still read

#### Scenario: Not uploaded
- **WHEN** Passport is on the KYC's list and has checks but isn't uploaded
- **THEN** the Passport items need attention "Not uploaded yet"

#### Scenario: AI unavailable
- **WHEN** the AI service fails with a connection error during a check
- **THEN** the attempt couldn't run with "the AI service is unavailable", no KYC field changes, and the earlier results are still shown

### Requirement: Progress, one check at a time, and toasts
While a record's documents are being checked, the system SHALL show which document is being read, as
"Checking <document> (<n> of <m>)…", and SHALL update the view without a page reload. Only one check
per record SHALL be queued or running at a time. A second request SHALL be refused with "Documents are
already being checked for <record>". The user who started it SHALL get a toast when it starts and when
it ends: "Documents checked for <record> — all OK", "— <n> need attention" (as a warning), or
"Couldn't check documents for <record> — <reason>. Try again later." (as an error).

#### Scenario: Summary toast
- **WHEN** a check ends with 2 items needing attention
- **THEN** the user gets a warning toast "Documents checked for Asha Rao — 2 need attention"

#### Scenario: Second check refused
- **WHEN** a check is running for a KYC and the user clicks Check documents again
- **THEN** no second check starts and the user sees "Documents are already being checked for Asha Rao"

#### Scenario: Progress shown
- **WHEN** the second of three documents is being read
- **THEN** the KYC's tab shows "Checking PAN Card (2 of 3)…"

### Requirement: Current results and changed documents
A record's current results SHALL be those of its latest completed, non-trial check. Each result SHALL
remember which version of the document file it read. When that document is replaced or removed after
the check, or a not-uploaded document is uploaded, that document's items SHALL show "Document changed
after this check" with Check again, and SHALL count as needing attention.

#### Scenario: Replaced document flagged
- **WHEN** a KYC's CML is replaced after its last check
- **THEN** CML shows "Document changed after this check" with Check again, and the other documents are unaffected

#### Scenario: New check replaces old results
- **WHEN** a document is removed from the KYC's list and the documents are checked again
- **THEN** no item for the removed document appears

### Requirement: Trial run changes nothing
*Try on a KYC* SHALL check the chosen KYC with the entity's current checks and show the results under the
banner "Trial run — nothing on this KYC was changed". It SHALL NOT write any field, SHALL NOT become the
KYC's current results, and SHALL NOT affect the KYC's journey or the attention list.

#### Scenario: Trial run on a KYC
- **WHEN** an admin tries the checks on Asha Rao's KYC and DP ID would be filled in
- **THEN** the trial shows "filled in: IN303622" under the banner, and Asha Rao's DP ID is still empty

### Requirement: Resolving an item on the spot
A user who can edit the record SHALL be able to resolve a Needs attention item of the current results:
- **Use document value** (Compare items with a document value): after confirming "Change <field> from X
  to Y?", the field is set to the document's value and the item becomes OK "updated from the document by
  <user>".
- **Mark as OK** (any item except "Not uploaded yet", "Document changed after this check" and couldn't-read
  items): requires a reason of at most 255 characters ("Say why this is OK") and makes the item OK
  "Marked OK by <user>: <reason>" with **Undo**.
- **Undo** returns a marked-OK item to Needs attention with its original reason.

Each resolution SHALL record who and when, and SHALL re-assess the record.

#### Scenario: Use document value
- **WHEN** Priya clicks Use document value on the PAN mismatch and confirms
- **THEN** the KYC's PAN is "ABCPK1234F" and the item reads "✓ PAN — updated from the document by Priya Shah"

#### Scenario: Mark as OK
- **WHEN** Priya marks the holder-name mismatch OK with "Initial matches passport"
- **THEN** the item reads "✓ Marked OK by Priya Shah: Initial matches passport" with Undo

#### Scenario: Mark as OK needs a reason
- **WHEN** Priya marks an item OK with no reason
- **THEN** it is refused with "Say why this is OK"

#### Scenario: Undo
- **WHEN** Priya clicks Undo on a marked-OK item
- **THEN** the item needs attention again with its original reason

### Requirement: All documents valid only when nothing needs attention
A record SHALL be treated as having all documents valid exactly when it has current results and none of
its items needs attention, counting changed documents as needing attention. For KYC this SHALL set
`all_docs_valid`.

#### Scenario: Not uploaded blocks validity
- **WHEN** every item is OK except the Passport items, which are "Not uploaded yet"
- **THEN** the KYC is not treated as having all documents valid

#### Scenario: Resolved items count as OK
- **WHEN** the only item needing attention is marked OK
- **THEN** the KYC is treated as having all documents valid

### Requirement: Documents needing attention across the entity
The system SHALL list every item needing attention in the current results of the entity's records, newest
first, filterable by reason (Doesn't match, Not found, Unexpected answer, Couldn't read, Not uploaded,
Document changed), document and checked date. Selecting rows and clicking Check again SHALL queue a check
for each selected record. With nothing to list it SHALL say "Nothing needs attention."

#### Scenario: Filter by reason
- **WHEN** the user filters to Doesn't match
- **THEN** only items with that reason are listed

#### Scenario: Check again in bulk
- **WHEN** the user selects rows for three KYCs and clicks Check again
- **THEN** a check is queued for each of the three KYCs

### Requirement: Access and isolation
The setup page and the attention list SHALL be available only to users of an entity with the "Doc LLM
validation" permission. Results SHALL be visible only to users of the record's own entity who can view the
record, and never to investor users. Resolving and checking SHALL need permission to edit the record. No
user SHALL see or act on another entity's checks, results or attempts.

#### Scenario: Other entity blocked
- **WHEN** a user from another entity opens the setup page or a result URL directly
- **THEN** access is denied

#### Scenario: Investor never sees results
- **WHEN** an investor user opens their KYC
- **THEN** no Document checks tab or result is shown

### Requirement: Converting legacy Doc Questions
The system SHALL provide a support-run conversion, a dry run by default, that for each entity turns its
Investor KYC Doc Questions into Document Checks:
- Extraction questions, and Validation questions whose text starts with "Extract", become Fill in checks;
  other Validation questions become Yes-no questions.
- The field is taken from "field <name>" in the response hint, or else from the question, resolved against
  the allowed fields by the same normalisation the old feature used.
- The full question text is kept as the tip.

A question whose document isn't on the entity's KYC lists, whose field can't be resolved, or whose field is
already used on that document SHALL NOT be converted, and SHALL be listed with the reason. Running it again
SHALL NOT duplicate checks. Legacy answers SHALL remain viewable on each KYC under "Earlier AI answers".

#### Scenario: Dry run report
- **WHEN** support runs the conversion without the execute flag for Pravega Ventures
- **THEN** a report lists each question with its field or the reason it can't convert, and no check is created

#### Scenario: Unresolvable field reported
- **WHEN** a question's hint says "Extract to field mobil_contact" and no such field exists
- **THEN** it is listed as not converted with "Field mobil_contact not found"

#### Scenario: Execute converts once
- **WHEN** support runs the conversion with the execute flag twice
- **THEN** the checks exist once

#### Scenario: Earlier AI answers shown
- **WHEN** a KYC has legacy Doc Questions answers and a user opens its Document checks tab
- **THEN** a collapsed "Earlier AI answers (before Document Checks)" section shows them

### Requirement: Doc Questions screens are gone
After the retirement deploy, the system SHALL NOT offer Doc Questions anywhere: the Doc Questions settings
pages and their URLs, the "DocQuestion" import type and its sample file, the KYC "validate docs with AI"
action URL, and the document page's QnA tab SHALL no longer exist (their URLs respond as not found). The KYC
page's Check documents button and bulk action SHALL start Document Checks. Earlier "DocQuestion" import
records SHALL remain viewable.

#### Scenario: Old settings pages gone
- **WHEN** a fund admin opens the old Doc Questions list or new-question URL
- **THEN** the page is not found and the Settings menu shows "Document Checks" instead

#### Scenario: Old import type gone
- **WHEN** a fund admin starts a new import
- **THEN** "DocQuestion" is not offered, while an earlier DocQuestion import record still opens

#### Scenario: Old KYC action gone
- **WHEN** a request posts to the old "validate docs with AI" KYC URL
- **THEN** it is not found

### Requirement: Legacy data is removed, answers kept
The retirement SHALL remove the stored Doc Questions and the unused document QnA data, and SHALL keep each
KYC's earlier AI answers for display. It SHALL refuse to remove the stored Doc Questions in an environment
where any question has neither been converted nor recorded as reviewed-and-not-converted by the conversion.

#### Scenario: Data removed, history kept
- **WHEN** the retirement has run
- **THEN** stored Doc Questions and document QnA data no longer exist, and a KYC's earlier AI answers still show under "Earlier AI answers"

#### Scenario: Unconverted questions block removal
- **WHEN** the retirement runs while 3 questions were never converted or reviewed
- **THEN** it stops with "3 Doc Questions are not converted — run doc_checks:convert_doc_questions first" and removes nothing
