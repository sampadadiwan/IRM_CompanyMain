# workflows/auto-assignment-rule-conditions Specification

## Purpose
Defines which fields, operators and values a workflow auto-assignment rule's conditions may use,
how those conditions are validated when a rule is saved, how they are matched against a new
record, and how they are presented to admins.

## Requirements

### Requirement: Rule fields come from the record type's search fields, rule-only fields and custom fields
A rule's conditions SHALL be limited to: the fields the record type exposes to search; the
rule-only fields declared for that record type (Form type on KYCs; Imported on capital calls and
capital distributions); and the custom fields defined on the company's forms for that record type,
excluding File, Header, GridColumns and Calculation fields. Amounts the system rolls up from other
records after the record is created (a capital call's call amount, fees and collected amount; a KYC's
committed, called, collected and distributed amounts; a commitment's called, collected, distributed
and units amounts; a distribution's distribution and gross amounts) SHALL NOT be offered, because they
are always zero when a rule is checked. Fields SHALL be offered per company: a
custom field or form type of another company SHALL never be offered. Rule-only fields SHALL NOT
become available to list-page search.

#### Scenario: KYC rule offers search fields, form type and custom fields
- **WHEN** an admin of a company with a KYC custom field "Nationality" opens a new rule for a KYC template
- **THEN** the field list includes "Form type", "Verified" and "Expiry date" under the KYC fields heading
- **AND** includes "Nationality" under the Custom fields heading

#### Scenario: Another company's custom fields are not offered
- **WHEN** another company has a KYC custom field "Tax residency" and this company does not
- **THEN** "Tax residency" is not in this company's KYC rule field list

#### Scenario: Excluded custom field types are not offered
- **WHEN** the company's KYC form has a File field "Passport copy" and a Calculation field "Age"
- **THEN** neither appears in the rule field list

#### Scenario: Rolled-up totals are not offered
- **WHEN** an admin opens a new rule for a capital call template or a KYC template
- **THEN** "Call amount" is not offered for calls, and "Committed amount" is not offered for KYCs
- **AND** "Committed amount" is offered on a commitment rule, where it is entered when the commitment is created

#### Scenario: Rule-only fields stay out of list search
- **WHEN** a user searches the KYC list with a Form type condition through the search parameters
- **THEN** the search does not filter on form type, exactly as before this change

### Requirement: Operators and values fit the field
Each field SHALL allow only the operators of its kind: text — is, is not, contains, is one of,
is blank, is present; number, amount and date — is, is not, greater than, at least, less than,
at most; yes/no — is; record and option lists — is, is not, is one of, is not one of. Values for
form type, fund and investor fields SHALL be chosen from the company's own records; values for
Select and Radio custom fields from their option list; amounts SHALL be entered in currency units.

#### Scenario: Form type values are the company's KYC form types
- **WHEN** the admin picks "Form type" on a KYC rule
- **THEN** the value list is exactly the company's KYC form types, labelled like "Individual — Fund IV"

#### Scenario: Option custom field offers its options
- **WHEN** the admin picks the Select custom field "Nationality" with options India, USA, UK
- **THEN** the value list is India, USA, UK

#### Scenario: Blank and present need no value
- **WHEN** the admin picks the operator "is blank"
- **THEN** no value input is shown and the condition saves without a value

### Requirement: Conditions are validated on save
Saving a rule SHALL fail, with a message naming the condition's position and the problem, when a
condition names a field not offered for the record type and company, uses an operator the field
does not allow, references a form type, fund or investor of another company, gives a non-number
for a number or amount field, a non-date for a date field, or no value for an operator that needs
one. The same checks SHALL apply to conditions entered through "View as JSON" and to rules created
outside the form. A JSON entry that is not a list of attribute/operator/value objects SHALL be
rejected with "The JSON is not a valid list of conditions."

#### Scenario: Unknown field is rejected
- **WHEN** the admin saves a KYC rule whose JSON names the field "nationalty"
- **THEN** the form shows "Condition 1: Unknown field \"nationalty\"." and the rule is not saved

#### Scenario: Wrong operator for the field is rejected
- **WHEN** the admin saves a condition "Form type greater than …"
- **THEN** the form shows "Condition 1: \"greater than\" can't be used with Form type." and the rule is not saved

#### Scenario: Another company's form type is rejected
- **WHEN** the admin saves "Form type is 999" where 999 belongs to another company
- **THEN** the form shows "Condition 1: Form type 999 is not one of this company's form types." and the rule is not saved

#### Scenario: Non-number amount is rejected
- **WHEN** the admin saves "Ticket size at least abc" on the number custom field Ticket size
- **THEN** the form shows "Condition 1: Ticket size needs a number." and the rule is not saved

#### Scenario: Missing value is rejected
- **WHEN** the admin saves "Nationality is" with no value
- **THEN** the form shows "Condition 1: Nationality needs a value." and the rule is not saved

#### Scenario: Malformed JSON is rejected
- **WHEN** the admin submits `{"attribute":"verified"}` (an object, not a list) through View as JSON
- **THEN** the form shows "The JSON is not a valid list of conditions." and the rule is not saved

### Requirement: A rule matches a record only when every condition holds for that record
When a record is created, or saved while it has no workflow template, a rule SHALL match only if
every one of its conditions holds for that record's saved data. A rule with no conditions SHALL
match every record of its type. Amount conditions SHALL compare in currency units. A custom-field
condition SHALL compare the record's custom-field value, and SHALL NOT match a record that has no
value for that field (except under "is blank"). A KYC SHALL be matched against rules for KYC
templates whether it is an individual or non-individual KYC. If any condition of a rule cannot be
applied, the rule SHALL NOT match; it SHALL never match more records than its conditions describe.

#### Scenario: Form type rule routes only that form type
- **WHEN** a rule "Form type is Individual — Fund IV" at priority 0 and a catch-all at priority 100 exist, and KYCs are created with form types Individual — Fund IV and Individual — Default
- **THEN** the Fund IV KYC gets the form-type rule's template and the Default KYC gets the catch-all's template

#### Scenario: Custom field rule routes by value
- **WHEN** a rule "Nationality is India" exists and KYCs are created with Nationality India, USA and no nationality
- **THEN** only the India KYC gets the rule's template

#### Scenario: Amount compared in currency units
- **WHEN** a commitment rule "Committed amount at least 5000000" exists and commitments of 6,000,000 and 2,000,000 are created
- **THEN** only the 6,000,000 commitment gets the rule's template

#### Scenario: Seeded imported rule still routes imported calls
- **WHEN** capital call journeys are set up and an imported capital call is created
- **THEN** it gets the Light journey, and a non-imported call gets the Full journey

#### Scenario: Unappliable condition never widens the match
- **WHEN** a rule's stored condition names a custom field that has since been deleted
- **THEN** the rule matches no record, and the skip is logged

### Requirement: Rule form edits conditions as rows
The rule form SHALL present conditions as rows of field, operator and value joined by AND, with
"+ Add condition" and a remove control per row, and SHALL load a saved rule's conditions into rows
with their values selected. A saved condition whose field is no longer offered SHALL show as
"Unknown field: <name>" and block saving until changed or removed. A "View as JSON" toggle SHALL
show and accept the same conditions as JSON. The KYC-only "KYC form type" control SHALL no longer
exist.

#### Scenario: Saved rule loads as rows
- **WHEN** the admin edits a rule with conditions "Form type is Individual — Fund IV" and "Nationality is India"
- **THEN** two rows show with those fields, operators and values selected

#### Scenario: Round trip through View as JSON
- **WHEN** the admin adds a row, switches to View as JSON, changes the value in the JSON and switches back
- **THEN** the row shows the changed value

#### Scenario: Deleted custom field shows as unknown
- **WHEN** the admin edits a rule whose condition names a deleted custom field "Region"
- **THEN** a row reads "Unknown field: Region" and saving is refused until it is removed

#### Scenario: No KYC form type control
- **WHEN** the admin opens a rule for a KYC template
- **THEN** there is no separate "KYC form type" control; Form type is a field in the builder

### Requirement: Rules table describes conditions in words
The workflow template page's rules table SHALL describe each condition as the field's label, the
operator's words and the value's label (for example "Form type is Individual — Fund IV"), join
conditions with "and", and show "Always (catch-all)" for a rule with no conditions.

#### Scenario: Conditions read as words
- **WHEN** a template has a rule "Form type is Individual — Fund IV" and "Nationality is India"
- **THEN** the rules table shows "Form type is Individual — Fund IV and Nationality is India"

#### Scenario: Catch-all reads as always
- **WHEN** a template has a rule with no conditions
- **THEN** the rules table shows "Always (catch-all)"
