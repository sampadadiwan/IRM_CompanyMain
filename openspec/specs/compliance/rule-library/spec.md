# compliance/rule-library Specification

## Purpose
Lets CapHive publish versioned rule packs per regulatory regime, and lets each fund manager build its own entity packs, as data (classifications, measures, checks, manual duties) so new regimes and fund-agreement rules need no code release.

## Requirements

### Requirement: Rule pack with its own classifications
The system SHALL store a rule pack with a name, regime, version, effective date, status (Draft, Published, Retired), owner (CapHive or one entity), a period basis (calendar quarters, or financial year April–March) that its duty schedules follow, and at least one classification of its own (e.g. SEBI: Category I, Category II, Category III, Category I — Large Value Fund, Category II — Large Value Fund). A Draft pack MUST NOT be visible to any customer.

#### Scenario: Draft pack invisible to customers
- **WHEN** a CapHive content admin creates a pack "SEBI — Alternative Investment Funds" and leaves it in Draft
- **THEN** no customer user can see or attach it

#### Scenario: Duties follow the financial-year basis
- **WHEN** the SEBI pack's period basis is financial year April–March
- **THEN** its quarterly duty periods end 30 Jun, 30 Sep, 31 Dec and 31 Mar, and its yearly duty period ends 31 Mar

#### Scenario: Duties follow the calendar-quarter basis
- **WHEN** an entity pack's period basis is calendar quarters
- **THEN** its yearly duty period ends 31 Dec

#### Scenario: Pack without classifications refused
- **WHEN** a pack is saved with no classifications
- **THEN** the save is refused with "Add at least one classification"

### Requirement: Check definition
Each check SHALL have a name, the classifications it applies to (at least one of the pack's classifications, or all), a kind (Automatic or Manual), a severity (Breach, Warning or Needs review), a tested setting (continuously, or when a record is made; default continuously) and a time to fix in whole days from 0 to 365 (default 30). A check in a CapHive pack MUST have a citation; in an entity pack the citation is optional.

#### Scenario: CapHive check without citation refused
- **WHEN** a content admin saves a check in a CapHive pack with no citation
- **THEN** the save is refused with "Citation is required"

#### Scenario: Entity check without citation allowed
- **WHEN** a compliance editor saves a check in an entity pack with no citation
- **THEN** the check is saved

#### Scenario: Applicable classification outside the pack refused
- **WHEN** a check names a classification that is not in its pack's list
- **THEN** the save is refused naming the unknown classification

#### Scenario: Time to fix out of range refused
- **WHEN** a check is saved with a time to fix of 366 days or a negative number
- **THEN** the save is refused with "Time to fix must be 0–365 days"

### Requirement: Measures built from data CapHive holds
An automatic limit check SHALL compare a measure with a limit. A measure SHALL be a total, count, distinct count, largest or smallest of a field over commitments, contributions, distributions, portfolio investments, valuations, investors, KYC, documents (with their signature status) or the fund, including their custom fields, with filters and an optional per-investee or per-investor grouping; or arithmetic (add, subtract, multiply, divide, lower of, higher of) over other measures and limits. Saving a measure that names a field or record type CapHive does not hold MUST be refused, naming the unknown field. Measures MUST NOT contain formula code.

#### Scenario: Valid grouped measure saved
- **WHEN** an author defines "largest investment cost per investee" over portfolio investments
- **THEN** the measure is saved and offered to checks

#### Scenario: Unknown field refused
- **WHEN** an author defines a measure over the field "commited_amount" that does not exist
- **THEN** the save is refused with "Unknown field: commited_amount"

#### Scenario: Arithmetic measure saved
- **WHEN** an author defines "lower of 2.5% × corpus and ₹5 crore"
- **THEN** the measure is saved and its plain-words form reads "lower of 2.5% of corpus and ₹5.00 cr"

### Requirement: Amount limits carry a currency
An amount limit SHALL carry a currency, defaulting to the pack's currency.

#### Scenario: Amount limit defaults to pack currency
- **WHEN** an author enters a limit of 50,000,000 on an amount measure in an INR pack without choosing a currency
- **THEN** the limit is saved as ₹5.00 cr (INR)

#### Scenario: Limit currency must be a code on an amount limit
- **WHEN** an author enters an amount limit in "US$", or gives a currency to a percentage limit
- **THEN** the draft is refused with "Unknown currency: US$" or "A currency applies only to a fixed amount limit"

### Requirement: Record-level document check definition
A check of the "every record has a required document" shape SHALL name the record type, the same filters as a measure (the sample IC note check defaults to buy transactions only), the required document input, whether the document must be signed (default yes), whether its signed date must be on or before the record's date (default yes), and a "checks from" date; the record type, document input and "checks from" date MUST be present.

#### Scenario: Sell transactions not checked for an IC note
- **WHEN** the IC note check (buys only) runs and a fund has a sale of Acme Foods shares with no IC note
- **THEN** the sale is not listed

#### Scenario: Document check without checks-from date refused
- **WHEN** an author saves "IC note for every investment" without a "checks from" date
- **THEN** the save is refused with "Checks from date is required"

### Requirement: Manual duty definition
A manual duty SHALL have a trigger — a schedule (quarterly, half-yearly, yearly), on demand, or an event ("for each new <record type>", "when a <document input> is uploaded or replaced"; an event duty MUST have a "from" date like record checks) — a due rule in calendar days (required unless on demand), whether evidence is required, and a reminder window.

#### Scenario: Scheduled duty without due rule refused
- **WHEN** an author saves a quarterly duty with no due rule
- **THEN** the save is refused with "Due rule is required"

#### Scenario: Event duty without from date refused
- **WHEN** an author saves "for each new investor: due diligence" without a from date
- **THEN** the save is refused with "From date is required"

#### Scenario: Due rule counts calendar days
- **WHEN** a duty is due 15 days after an event on Friday 06 Nov 2026
- **THEN** it is due Saturday 21 Nov 2026

#### Scenario: On-demand duty without due rule allowed
- **WHEN** an author saves an on-demand duty "Key-person event notified" with no due rule
- **THEN** the duty is saved

### Requirement: Test run before publishing a CapHive pack
A CapHive pack SHALL be published only when the draft has been tested since the last edit and a counsel review (reviewer name and review date) is recorded. A test run is a preview: it MUST be read-only and MUST NOT create results, register items, run records or notifications for any customer; only who tested it and when are kept. Test runs SHALL use the CapHive demo entity, or a customer entity only while that customer has granted CapHive support access.

#### Scenario: Publish refused without test run
- **WHEN** a content admin publishes a pack whose draft has not been tested since the last edit
- **THEN** publishing is refused with "Run a test first"

#### Scenario: Publish refused without counsel review
- **WHEN** a content admin publishes a tested pack with no counsel reviewer or review date
- **THEN** publishing is refused with "Record the counsel review"

#### Scenario: Test run leaves no trace for the customer
- **WHEN** a content admin test-runs a draft pack on the demo entity
- **THEN** results with figures are shown to the admin and nothing is stored in any customer register

#### Scenario: Test run on a customer without support access refused
- **WHEN** a content admin picks a customer entity that has not granted CapHive support access for a test run
- **THEN** the entity is not offered and a direct request is refused

### Requirement: Every publish creates a version with its applicability
Every publish SHALL create a new version of the pack. Effective, applicability and transition dates SHALL be dates in the pack's regime time zone (IST for SEBI and IFSCA). When publishing a CapHive pack version the content admin SHALL set an effective date (after the previous version's, except a correction version, which takes the same effective date as the version it corrects), an applicability — A "All funds", B "New funds only" (with an applicability date, defaulting to the effective date) or C "All funds with a transition period" (with a transition end date after the effective date) — and whether early adoption is allowed. Each run's results SHALL record the version used for that fund. A version published after its effective date SHALL apply from the next run, flagged "Published late", with no retroactive runs. When a correction version takes effect, results computed under the faulty version SHALL be marked "Superseded — pack correction", and register items opened only because of the fault SHALL close as "Pack corrected".

#### Scenario: Effective date not after current version refused
- **WHEN** v2 is published with an effective date on or before v1's
- **THEN** publishing is refused with "Effective date must be after v1's"

#### Scenario: Correction version on the same effective date
- **WHEN** v2 (effective 01 Jan 2027) had a wrong limit and v2.1 is published as its correction with effective date 01 Jan 2027
- **THEN** v2.1 is accepted, results computed under v2 are marked "Superseded — pack correction", and items opened only because of v2's fault close as "Pack corrected"

#### Scenario: Version published one day late
- **WHEN** v2 with effective date 01 Jan 2027 is published on 02 Jan 2027 after the 02:00 run
- **THEN** funds move to v2 on the 03 Jan run, results are flagged "Published late", and no run is repeated for 01–02 Jan

#### Scenario: Regime time zone for effective dates
- **WHEN** SEBI v2 is effective 01 Jan 2027 (IST) and a US entity's funds run at 02:00 ET on 31 Dec and 01 Jan
- **THEN** the 31 Dec run (12:30 IST 31 Dec) records v1 and the 01 Jan run (12:30 IST 01 Jan) records v2

#### Scenario: Applicability required on publish
- **WHEN** a content admin publishes SEBI v2 without choosing an applicability
- **THEN** publishing is refused with "Choose who this version applies to"

#### Scenario: Transition end date not after effective date refused
- **WHEN** v2 has applicability C, effective 01 Jan 2027, and a transition end date of 01 Jan 2027
- **THEN** publishing is refused with "Transition must end after the effective date"

#### Scenario: Version switches on its effective date
- **WHEN** v2 is effective 01 Jan 2027 with applicability A and runs happen on 31 Dec 2026 and 01 Jan 2027
- **THEN** the 31 Dec results record v1 and the 01 Jan results record v2

### Requirement: Locked CapHive packs
CapHive regulator packs SHALL be locked: a customer user MAY attach them, map their inputs and enter reference lists, but MUST NOT edit their checks, measures, inputs or limits, through the screen or a direct request. Entity packs SHALL be unlocked and edited and versioned by their entity.

#### Scenario: Editing a locked pack refused
- **WHEN** Meera opens the SEBI pack's concentration check
- **THEN** it is read-only, marked "Locked — CapHive pack", with no edit controls

#### Scenario: Direct edit of a locked pack refused
- **WHEN** a company admin sends a direct request to change the SEBI concentration limit to 30%
- **THEN** the request is refused and the pack is unchanged

#### Scenario: Inputs and reference lists still editable on a locked pack
- **WHEN** Meera maps "Sponsor/manager" and enters IC members for funds carrying the SEBI pack
- **THEN** the mapping and list are saved

### Requirement: Override policy per check in a locked pack
Each check in a locked pack SHALL be marked "stricter only" or "not overridable". Looser limits for special fund types SHALL come only from a classification (e.g. Category II — Large Value Fund), never from an override.

#### Scenario: Check marked not overridable
- **WHEN** a content admin marks "Investors in scheme" as not overridable and publishes
- **THEN** funds carrying the pack are offered no override for that check

### Requirement: Entity packs
A compliance editor SHALL be able to build entity packs with the same classifications, measures, checks and duties as CapHive packs. Entity packs MUST be visible only to their entity, MUST be labelled "Entity pack", need no counsel review, and SHALL be versioned: edits stay a draft until published. A new entity pack version SHALL apply to all funds carrying it from publish, or from a date the entity sets; entity packs have no grandfathering, transition or early-adoption options.

#### Scenario: Entity pack invisible to another firm
- **WHEN** a user of another firm lists packs or requests Horizon's entity pack directly
- **THEN** the pack is not listed and the direct request is refused

#### Scenario: Entity pack edit is a draft until published
- **WHEN** Meera edits a limit in the published v1 of "Horizon — fund agreement limits"
- **THEN** runs keep using v1 until she publishes v2

#### Scenario: Entity pack version applies from publish
- **WHEN** Meera publishes v2 of the fund-agreement pack on 10 Nov without a date
- **THEN** the 11 Nov run of every fund carrying it records v2

#### Scenario: Entity pack version applies from a set date
- **WHEN** Meera publishes v2 on 10 Nov with "applies from 01 Dec 2026"
- **THEN** runs up to 30 Nov record v1 and the 01 Dec run records v2

#### Scenario: Entity pack offers no grandfathering
- **WHEN** Meera publishes an entity pack version
- **THEN** no applicability B or C, transition or early-adoption option is offered

### Requirement: Only CapHive content admins author CapHive packs
Only CapHive content admins SHALL create, edit, test, publish or retire CapHive packs.

#### Scenario: Customer user cannot edit a CapHive pack
- **WHEN** a company admin requests an edit of the SEBI pack directly
- **THEN** the request is refused

### Requirement: Retiring a pack
A retired pack SHALL NOT be attachable, including by a direct request; funds already carrying it SHALL stop being checked against it from the retirement date (the run of that date) and keep their history.

#### Scenario: Retired pack not attachable
- **WHEN** a pack is retired
- **THEN** it is not offered in Setup › Funds › Attach pack and existing results remain viewable

#### Scenario: Retired pack stops checks from the retirement date
- **WHEN** the SEBI pack is retired on 01 Mar 2027
- **THEN** the 28 Feb run still checks it, the 01 Mar run does not, and its history stays viewable

#### Scenario: Direct attach of a retired pack refused
- **WHEN** a direct request attaches a retired pack to a fund
- **THEN** the request is refused
