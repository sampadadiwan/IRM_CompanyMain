# Spec Delta

## Purpose

Keeps investors' PAN, bank account, IFSC and verification data unreadable in the database and its
copies, while every screen, export, document, import and exact lookup that users rely on keeps working.

## ADDED Requirements

### Requirement: Investor PII is stored encrypted
The system SHALL store the following values encrypted, so that reading the database table directly
never shows them: PAN, bank account number, IFSC code, PAN verification reply and bank verification
reply on investor KYCs, secondary sale offers and secondary sale interests; bank account number and
IFSC code on advisor fees; PAN and the request, response and response-data replies on CKYC/KRA
lookups; PAN and the request and response replies on AML reports. Every screen, export, generated
document, API response and email SHALL show the same value as before encryption.

#### Scenario: Stored value is unreadable
- **WHEN** a KYC is saved with PAN `ABCPM1234K` and bank account `50100234567812`
- **THEN** the stored PAN and bank account values in the table are not the typed values and contain neither `ABCPM1234K` nor `50100234567812`

#### Scenario: Screens and exports show the real value
- **WHEN** a fund user opens the KYC page or downloads the KYC list as a spreadsheet
- **THEN** the PAN shows `ABCPM1234K` and the bank account shows `50100234567812`

#### Scenario: Generated documents and PDF passwords use the real value
- **WHEN** a document template prints the KYC's PAN, or a custom notification protects a PDF with the password field `investor_kyc.PAN`
- **THEN** the document shows `ABCPM1234K` and the PDF opens with `ABCPM1234K`

#### Scenario: Same PAN stored the same way, bank numbers never
- **WHEN** two KYCs are saved with the same PAN and the same bank account number
- **THEN** their stored PAN values are identical and their stored bank account values differ

### Requirement: PAN, IFSC and bank values are tidied before storage
The system SHALL trim surrounding spaces from PAN, IFSC code and bank account number, upper-case PAN
and IFSC code, and store a blank value as empty (no value). The same tidying SHALL apply to the value
a user searches or imports with.

#### Scenario: Lowercase PAN with spaces is tidied
- **WHEN** a KYC is saved with PAN ` abcpm1234k `
- **THEN** the KYC shows PAN `ABCPM1234K`

#### Scenario: Blank bank account is stored as no value
- **WHEN** a KYC is saved with an empty bank account number
- **THEN** the KYC counts as having no bank account in every "is blank" filter and readiness warning

### Requirement: Exact-match lookups keep working
The system SHALL find records by the full PAN or IFSC code wherever it does today: KYC imports matching
on "Pan/Tax Id", KYC document imports matching on "PAN/Tax ID", CKYC/KRA lookups, AML report reuse,
list filters "equals" / "not equals" / "is blank" / "is present" on the record or through a related
KYC, and the rule that a CKYC/KRA lookup PAN is unique per source and KYC.

#### Scenario: Import updates the KYC with a differently typed PAN
- **WHEN** a KYC import row has "Pan/Tax Id" `abcpm1234k ` and "Update Only" `Yes`, and the investor's KYC has PAN `ABCPM1234K`
- **THEN** that KYC is updated and no new KYC is created

#### Scenario: Filter PAN equals
- **WHEN** a fund user filters the KYC list with "PAN equals ABCPM1234K"
- **THEN** the KYC with that PAN is listed and no other

#### Scenario: Filter through a related KYC
- **WHEN** a fund user filters commitments with "Investor Kyc PAN equals ABCPM1234K"
- **THEN** the commitments whose KYC has that PAN are listed

#### Scenario: CKYC/KRA lookup found by PAN
- **WHEN** a CKYC lookup exists for PAN `ABCPM1234K` on a KYC and the user opens the CKYC/KRA comparison
- **THEN** that lookup is used

#### Scenario: AML report reused for the same PAN
- **WHEN** AML screening runs again for a KYC whose PAN `ABCPM1234K`, name and date of birth already have an AML report
- **THEN** the existing AML report is reused and no second report is created

#### Scenario: Is blank lists records without a value
- **WHEN** a fund user filters the KYC list with "PAN is blank" or "Bank Account Number is blank"
- **THEN** exactly the KYCs with no PAN, or no bank account, are listed

#### Scenario: Duplicate CKYC lookup refused
- **WHEN** a second CKYC lookup is created for the same KYC with PAN `ABCPM1234K`
- **THEN** it is refused with "should be unique for the same source and KYC"

### Requirement: Unsupported searches on encrypted fields are refused with a message
The system SHALL refuse, with a visible message and without applying the condition, any list filter
on PAN or IFSC code other than "equals", "not equals", "in", "not in", "is blank", "is present",
"is null" and "is not null", and any filter on bank account number other than "is blank",
"is present", "is null" and "is not null". This SHALL apply to every list filter, saved report,
report link (including links built by the AI report assistant) and to conditions reached through a
related record. Sorting by these fields SHALL leave the list in its default order. The system SHALL
never return an empty or filtered list as if such a condition had been applied.

#### Scenario: PAN contains is refused
- **WHEN** a fund user filters the KYC list with "PAN contains ABCPM"
- **THEN** the message `"PAN" is stored encrypted, so it can only be matched exactly. Use "equals" with the full value, or "is blank" / "is present".` is shown and the list shows every KYC the user can see

#### Scenario: Bank account equals is refused
- **WHEN** a fund user filters the KYC list with "Bank Account Number equals 50100234567812"
- **THEN** the message `"Bank Account Number" is stored encrypted, so it can only be filtered by "is blank" or "is present".` is shown and the filter is not applied

#### Scenario: Refused through a related record and a direct link
- **WHEN** a request to the commitments list carries `q[investor_kyc_PAN_cont]=ABCPM`
- **THEN** the PAN message is shown and the condition is not applied

#### Scenario: Filter picker offers only supported conditions
- **WHEN** a fund user picks PAN in the filter panel
- **THEN** the condition list offers only "equals", "not equals", "is blank" and "is present"

#### Scenario: Sort by PAN leaves default order
- **WHEN** a list request asks to sort by PAN
- **THEN** the list is shown in its default order with every row it would otherwise show

### Requirement: The search box matches PAN and bank account by full value without storing them in the index
The system SHALL let the KYC and Offer search boxes find a record by its full PAN or full bank account
number, after the same tidying as storage. The search index SHALL hold a one-way fingerprint of these
values and never the values themselves. Part of a PAN or bank account number SHALL NOT match on those
fields. The search box SHALL carry the hint "PAN and bank account numbers match only when typed in full."

#### Scenario: Full PAN finds the KYC
- **WHEN** a fund user types `abcpm1234k` in the KYC search box
- **THEN** the KYC with PAN `ABCPM1234K` is listed

#### Scenario: Full bank account finds the KYC
- **WHEN** a fund user types `50100234567812` in the KYC search box
- **THEN** the KYC with that bank account is listed

#### Scenario: Part of a PAN does not match on PAN
- **WHEN** a fund user types `ABCPM` in the KYC search box and no other field of any KYC starts with it
- **THEN** no KYC is listed

#### Scenario: The index holds no PAN or bank account
- **WHEN** the KYC and Offer search indexes are read directly
- **THEN** no document contains a PAN or bank account number value

#### Scenario: Search stays within the firm
- **WHEN** a user of another firm types the full PAN `ABCPM1234K` in their KYC search box
- **THEN** the Kestrel Capital KYC is not listed

### Requirement: Reports show encrypted values but do not compute on them
The report builder SHALL show PAN, bank account number and IFSC code of a related record as the real
value when shown as "Value" or "Latest", and as a row count with "Count". It SHALL NOT offer minimum,
maximum, sum, average, list, pivot or sort on these columns. A saved report that used an unsupported
option SHALL show "Value" instead with the tooltip "Stored encrypted — shown as is; can't be summed,
ranged, listed, pivoted or sorted."

#### Scenario: Related PAN value is readable
- **WHEN** a commitments report shows the related KYC's PAN as "Value"
- **THEN** each row shows the real PAN, e.g. `ABCPM1234K`

#### Scenario: Saved report with list on bank account
- **WHEN** a saved investors report shows related KYC bank accounts as "List"
- **THEN** the column shows "Value" for each investor with the tooltip, never encrypted text

#### Scenario: Pivot by PAN not offered
- **WHEN** a report builder user opens the pivot categories for related KYCs
- **THEN** PAN, bank account number and IFSC code are not offered

### Requirement: History records who changed encrypted fields, without their values
The history (audit trail) SHALL record every change to an encrypted field with the user and time,
and SHALL store and show the change as "<Field> changed (value hidden)" instead of the old and new
values. Existing history entries that hold PAN, bank account, IFSC or verification-reply values SHALL
be rewritten the same way during rollout.

#### Scenario: New bank account change
- **WHEN** a fund user changes a KYC's bank account
- **THEN** the KYC history shows the user, the time and "Bank Account Number changed (value hidden)", and the stored history entry contains neither account number

#### Scenario: Old history entry rewritten
- **WHEN** the history clean-up runs on a history entry that recorded PAN `ABCPM1234K` → `ABCPM1234L`
- **THEN** the entry keeps its user and time and no longer contains either PAN

### Requirement: Raw database readers never expose or mis-read encrypted values
The fund-manager support chatbot SHALL NOT receive PAN, bank account number or IFSC code, and SHALL
answer requests for them with "PAN, bank account number and IFSC code are not available to the
assistant — open the KYC page." The firm's database download SHALL contain the real values, as today.

#### Scenario: Chatbot cannot read PAN
- **WHEN** the support chatbot runs a query on investor KYCs that names the PAN column
- **THEN** the query is refused and the assistant replies with the not-available message

#### Scenario: Chatbot query without PAN still works
- **WHEN** the support chatbot counts verified KYCs for the firm
- **THEN** the count is returned as before

#### Scenario: Database download is readable
- **WHEN** a company admin generates the firm's database download
- **THEN** the KYC table in the file shows PAN `ABCPM1234K` and bank account `50100234567812`

### Requirement: Super-admin search does not search encrypted fields
The CapHive super-admin offer and interest screens SHALL search every other text field as today and
SHALL NOT search PAN, bank account number or IFSC code.

#### Scenario: Admin search by name still works
- **WHEN** a super admin searches offers for `Anil`
- **THEN** Anil Mehta's offer is listed

### Requirement: Existing records are converted per region with a dry run, verify and a way back
Operations SHALL convert existing records with a task that is a dry run unless told to execute, names
and checks the region it runs on, converts in batches without changing timestamps, history or
notifications, can be re-run and skips values already encrypted. A verify task SHALL report how many
plain values remain. A reverse task SHALL return every value to plain text. During the transition
window the system SHALL read both plain and encrypted values and find a PAN in either form; after the
window closes, a plain value SHALL be reported as an error, never shown as if valid.

#### Scenario: Dry run changes nothing
- **WHEN** operations runs the conversion without EXECUTE=1
- **THEN** it reports the counts it would convert per table and field and no stored value changes

#### Scenario: Conversion encrypts, tidies and keeps timestamps
- **WHEN** operations runs the conversion with EXECUTE=1
- **THEN** every PAN, bank account, IFSC and reply is encrypted, PANs are tidied, each record's "updated at" is unchanged and no history entry or email is created

#### Scenario: Interrupted conversion is re-run
- **WHEN** the conversion stops part-way and is run again
- **THEN** only the values still in plain text are converted and verify reports 0 plain values

#### Scenario: Lookup during the window
- **WHEN** one KYC with PAN `ABCPM1234K` is still in plain text and another is encrypted, during the transition window
- **THEN** an import or "PAN equals" lookup for `ABCPM1234K` finds both

#### Scenario: Plain value after the window closes
- **WHEN** a plain-text PAN is found after the window has closed
- **THEN** the page shows the standard error and operations is alerted by the existing error email

#### Scenario: Reverse conversion
- **WHEN** operations runs the reverse task with EXECUTE=1
- **THEN** every converted value is stored in plain text again and the verify task reports 0 encrypted values

### Requirement: Regions never share keys and tasks never cross regions
Each region SHALL use only its own keys. The pre-flight task SHALL report whether the keys are present
and a short fingerprint of them, and SHALL refuse to continue when the fingerprint equals the one
recorded for another region. Every rollout task SHALL refuse to run when the region it is asked for is
not the region it is running in.

#### Scenario: Pre-flight reports keys and counts
- **WHEN** operations runs the pre-flight for production India on a production India machine
- **THEN** it reports that the keys are present, their short fingerprint, and the number of rows and filled values per table and field, and changes nothing

#### Scenario: Pre-flight with missing keys
- **WHEN** the region's credentials have no encryption keys
- **THEN** the pre-flight stops with "Encryption keys missing for production.in — stop"

#### Scenario: Pre-flight on matching fingerprints
- **WHEN** the pre-flight for production India finds a fingerprint equal to the one recorded for production US
- **THEN** it stops with "Fingerprint matches the value recorded for production.us — stop" and nothing is converted

#### Scenario: Task run against the wrong region
- **WHEN** the conversion is started for production US on a production India machine
- **THEN** it refuses and changes nothing

### Requirement: Developer copies of production hold no real investor PII
A scrub task for restored production copies SHALL replace every encrypted value with a fake value
that reads correctly with the developer key, keep equal PANs equal, and refuse to run anywhere except
a development database.

#### Scenario: Scrubbed copy shows fake values
- **WHEN** a developer restores a production copy and runs the scrub
- **THEN** KYC pages open and show fake PANs and bank accounts, and two KYCs that shared a PAN still share one fake PAN

#### Scenario: Scrub refuses production
- **WHEN** the scrub is started against a production or staging database
- **THEN** it refuses and changes nothing
