# forms/custom-field-steps Specification

## Purpose
Decides which of a form type's custom fields a form renders, based on the wizard step each field
is tagged with in the form builder.

## Requirements

### Requirement: Single-page forms render custom fields from every step
A form rendered on a single page SHALL show every visible, non-regulatory custom field of its
form type, whatever step the field is tagged with. Changing a field's step SHALL NOT remove it
from a single-page form.

#### Scenario: Fields on Step 1, Step 2 and the default step
- **WHEN** a Capital Commitment form type has "Source of Funds" on Step 1, "Risk Notes" on Step 2 and "Internal Notes" on the default step
- **THEN** the capital commitment edit form shows all three fields

#### Scenario: Value entered in a non-default step field is saved
- **WHEN** a user fills in "Source of Funds" (a Step 1 field) on the capital commitment edit form and saves
- **THEN** the capital commitment keeps that value
- **AND** the field shows the value when the edit form is opened again

### Requirement: Wizard forms render one step at a time
A multi-step wizard form SHALL pass the step it is rendering. It SHALL show only the custom
fields tagged with that step. The step may be given as an enum name (e.g. "one") or as its
integer value.

#### Scenario: KYC wizard
- **WHEN** an Investor KYC form type has one custom field on each step from one to nine
- **THEN** the KYC wizard shows nine steps
- **AND** values entered on every step are saved (see `features/core/dynamic_kyc_steps.feature`)

### Requirement: Each custom field renders on only one wizard panel
A wizard form that renders custom fields on more than one panel SHALL pass `step:` on every
such panel, so that each custom field appears on exactly one panel. A wizard with a single
custom-fields panel, such as the secondary sale wizard, MAY omit `step:` and show every field.
On the Investor KYC wizard, the step 3 panel SHALL show only fields on the default step (`end`).
It SHALL NOT repeat fields from step 1 or step 2. A field that appeared on two panels would be
submitted twice under the same name, and the later, unedited copy would overwrite the value the
user entered.

#### Scenario: Step 1 edit on the KYC wizard is not overwritten by step 3
- **WHEN** an Investor KYC form type has a custom field on step 1 and a custom field on the default step
- **AND** a user fills in the step 1 field, moves through the wizard and saves
- **THEN** the step 3 panel does not show the step 1 field
- **AND** the investor KYC keeps the value entered on step 1 (see `features/core/dynamic_kyc_steps.feature`)
