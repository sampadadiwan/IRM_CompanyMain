## Purpose

Lets support generate a fund's pre-run and post-run check formulas from its existing formulas and
data. Each suggestion is tested against a real run before support adds it, or exports it for import.

## ADDED Requirements

### Requirement: Rule-based suggestions
When support asks for run check suggestions for a fund, the system SHALL build suggestions from
fixed rules. The rules read the fund's formulas, the entity's custom field forms, and the fund's
past uploaded account entries. The same fund data SHALL always produce the same suggestions. The
rules SHALL cover at least:

| Rule | Suggested check |
| --- | --- |
| Allowed entry names per entry type | From names totalled by the fund's formulas, grouped by the entry type those names were uploaded with |
| Required custom fields | Uploaded fund-level entries and portfolio investments, for the fields the allocation formulas read |
| Deal entry types mapped to a portfolio investment | Entry types whose past uploads were mapped to one |
| Folio percentage fields | Where allocation formulas read a folio's percentage field, the percentages add up to 100 |
| Unit settings | Every unit type in use has the settings the formulas read |
| FX rates | Present when the fund has a tracking currency or foreign currency instruments |
| Valuations | Present, as a warning, when the fund holds portfolio investments |
| Uploaded entries allocated and tied to folios | When the fund has entry allocation formulas |
| Portfolio amounts tied to folios | For portfolio allocation formulas that allocate an investment amount column without changing its sign |
| Since Inception totals match history | When the fund has formulas that store a "Since Inception <name>" total, so it can guard the switch to incremental allocation before and after |

#### Scenario: Suggestions for fund 342's formulas
- **WHEN** support asks for suggestions on a fund whose "Non Deal Expense" allocation formula reads the fund level UDR code from the uploaded entry
- **THEN** the suggestions include a pre-run check requiring the "Fund Level Udr Code" custom field on fund-level uploads

#### Scenario: Same data, same suggestions
- **WHEN** support asks for suggestions twice without the fund's formulas or data changing
- **THEN** both lists contain the same checks with the same formula text

#### Scenario: A rule that does not apply
- **WHEN** the fund has no tracking currency and no foreign currency instruments
- **THEN** no FX rate check is suggested

### Requirement: Evidence for every suggestion
Every suggestion SHALL show:
- where it came from: a rule, or AI
- the evidence behind it: the formulas (sequence and name) and data that triggered it
- a suggested name, description, rule type (pre-run or post-run) and formula text

#### Scenario: Evidence shown
- **WHEN** a "Unit settings for every unit type" suggestion is shown
- **THEN** it lists the formulas that read the unit setting and the unit types in use

### Requirement: Existing checks are not duplicated
A suggestion that makes the same helper call as a check the fund already has (same helper and the same values, in any list order, at either severity) SHALL be marked "already
present" and SHALL NOT be selectable.

#### Scenario: Check already exists
- **WHEN** the fund already has a pre-run check with the same formula text as a suggestion
- **THEN** that suggestion is marked "already present" and cannot be added again

### Requirement: Optional AI suggestions
Support SHALL be able to request additional suggestions from AI for the fund. AI suggestions SHALL:
- only be generated when support requests them
- be labelled as AI suggestions
- go through the same validation as rule-based suggestions
- be test-run only when the formula is a single helper call with literal arguments; any other AI
  formula text SHALL be shown as "not tested" and SHALL NOT be evaluated until support adds it
- never be added without support selecting them

A generated check whose formula fails formula validation (unsafe expression, syntax error, missing
required fields) SHALL be dropped and listed with the reason.

#### Scenario: AI suggestion added to the list
- **WHEN** support requests AI suggestions and the AI proposes a valid check
- **THEN** it appears in the list labelled as AI, with its evidence and test result, unselected

#### Scenario: AI suggestion that is not a plain helper call
- **WHEN** the AI proposes a valid check written as free Ruby (for example `check!(...)`)
- **THEN** it appears labelled as AI and "not tested", saying it is evaluated only once a person adds it

#### Scenario: AI suggestion with an unsafe formula
- **WHEN** the AI proposes a check whose formula text contains a blocked word such as "delete"
- **THEN** that check is not offered and is listed as rejected with the reason

#### Scenario: AI unavailable
- **WHEN** the AI service returns an error
- **THEN** the rule-based suggestions are still shown and the page says AI suggestions could not be generated

### Requirement: Test run against the last successful run
Every rule suggestion, and every AI suggestion that is a single helper call with literal arguments,
SHALL be evaluated against the fund's most recent successful allocation run before it is shown. Its
result (pass, warn, fail or skipped), summary and up to the report's row limit of offending rows
SHALL be displayed. Evaluation SHALL NOT change any data. With no successful run, suggestions SHALL
be shown as "not tested".

#### Scenario: Suggestion that fails today
- **WHEN** a suggested FX rate check is evaluated and the fund's INR to USD rate is older than the window
- **THEN** the suggestion shows "fail" with the missing currency pair and its latest rate date

#### Scenario: Fund with no successful run
- **WHEN** the fund has no allocation run with status Success
- **THEN** every suggestion is shown as "not tested" and can still be selected

### Requirement: Adjust severity before adding
Before adding, support SHALL be able to change a suggestion's severity from fail to warning where its
check supports a severity.

#### Scenario: Add a failing check as a warning
- **WHEN** support switches a failing FX rate suggestion to warning and adds it
- **THEN** the added formula uses warning severity, so it does not stop allocation runs

### Requirement: Add selected suggestions
Support SHALL be able to add the selected suggestions to the fund as enabled check formulas. Each
SHALL get:
- the suggestion's name, description, rule type and formula
- rule-for "accounting"
- a sequence after the fund's existing formulas

Each addition SHALL be recorded in the formula's audit trail. A suggestion that fails formula
validation when saved SHALL NOT be added, and the page SHALL report why.

#### Scenario: Add three suggestions
- **WHEN** support selects three suggestions and chooses "Add selected"
- **THEN** three enabled check formulas are created on the fund with the suggested names, descriptions and formulas, and the page confirms the count

### Requirement: Download suggestions as an importable file
Support SHALL be able to download the selected suggestions as an xlsx in the fund formula import
format. Uploading that file unchanged through the existing fund formula import for the same fund
SHALL create the same formulas as "Add selected".

#### Scenario: Round trip through import
- **WHEN** support downloads selected suggestions and uploads the file unchanged as a fund formula import for that fund
- **THEN** the import succeeds for every row and creates formulas identical in name, description, rule type, rule-for, formula and enabled flag to those "Add selected" would create

### Requirement: Suggestions are generated in the background and kept
Generating and test-running suggestions SHALL run in the background, with the page showing progress
until it finishes. The finished set SHALL be kept with the fund, with who requested it and when, so
support can come back to it, add from it or download it without regenerating it. The page SHALL open
the fund's most recent set.

#### Scenario: Returning to suggestions
- **WHEN** support generates suggestions, leaves the page, and later opens "Suggest run checks" for the same fund
- **THEN** the page shows the same suggestion set with its test results and when it was generated, and offers "Generate again"

### Requirement: Support-only access
Generating, test-running, adding and downloading suggestions SHALL require the support role.

#### Scenario: Non-support user requests suggestions
- **WHEN** a user without the support role requests the suggestions URL for a fund
- **THEN** the request is refused as unauthorized and no suggestions are generated
