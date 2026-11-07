# Spec Delta

## Purpose

Lets a firm's company admin change a record type's custom fields from a record's page, in a side panel, saving
every change at once and refreshing the page in place.

## ADDED Requirements

### Requirement: Fields icon on record pages
A record page that lists the record's custom fields from its form type SHALL show a fields icon on the corner of
the card holding those fields when the user may change that form type: a company admin of the firm that owns it,
never a user acting as an investor. The record's form (new or edit) that shows those fields SHALL show the icon in the form's header too; saving from
a form SHALL warn first that the page refreshes and unsaved form entries are lost. A list of fields chosen
elsewhere (a reporting fields list) SHALL NOT show the icon.

#### Scenario: Company admin sees the icon
- **WHEN** a company admin opens an investor's page
- **THEN** the details card shows the fields icon on its corner

#### Scenario: Employee who is not a company admin
- **WHEN** an employee without the company admin role opens an investor's page
- **THEN** the details card shows no fields icon

#### Scenario: Icon on the record's form
- **WHEN** a company admin opens an investor's edit form
- **THEN** the form's header shows the fields icon, and the panel warns that saving refreshes the page

#### Scenario: Reporting fields list
- **WHEN** a page shows a reporting fields list for a record
- **THEN** that list shows no fields icon

### Requirement: Panel lists the form type's fields
Clicking the icon SHALL open a side panel, without leaving the page, listing the fields of the record's form type
in form order, each with its label, name, type, Required, Read only and Internal settings and help text, and
naming the form type and who shares it. Regulatory fields SHALL NOT be listed. Calculation fields SHALL be listed
locked for users who are not CapHive support. When the record has no form type, the panel SHALL list the firm's
form type for that record type, the one new records of that type use, or none when the firm has none.

#### Scenario: Fields listed in order
- **WHEN** the investor's form type has Risk rating, Relationship manager, KYC due and the admin opens the panel
- **THEN** the panel lists them in that order with their types and settings, under "Investor fields · Default"

#### Scenario: Calculation field locked
- **WHEN** the form type has a calculation field and a company admin who is not support opens the panel
- **THEN** the calculation field is listed and cannot be changed or removed

#### Scenario: Regulatory field not listed
- **WHEN** the KYC form type has regulatory fields
- **THEN** the panel does not list them

#### Scenario: Record without a form type
- **WHEN** the record has no form type and the firm has an Investor form type
- **THEN** the panel lists that form type's fields

### Requirement: Edit fields without saving
In the panel the user SHALL be able to reorder fields by dragging, rename a field's label, switch Required, Read
only and Internal, edit help text, mark a field for removal (and undo that before saving), and add a field with a
label and a type of Text, Number, Date, Text area, Check box, Select (with options) or Money. Nothing SHALL be
saved until Save; Cancel, the close button and Escape SHALL close the panel without saving.

#### Scenario: Add a select field
- **WHEN** the admin adds "Source of funds" as a Select with options Salary, Business, Inheritance
- **THEN** the field is added at the end of the list

#### Scenario: Cancel discards
- **WHEN** the admin renames a field and presses Escape
- **THEN** the panel closes and the form type is unchanged

### Requirement: Save stores every change and refreshes the page
Save SHALL apply every change in one step to the form type: order, labels, Required, Read only, Internal, help
text, removals and additions. A new field's name SHALL be made from its label; a Money field SHALL use the firm's
currency. After a successful save the panel SHALL close and the page SHALL refresh in place, keeping the scroll
position, followed by a confirmation message. The change SHALL apply to every record on that form type.

#### Scenario: Reorder, rename, flags, help text, add
- **WHEN** the admin moves KYC due first, renames Relationship manager to RM, marks Risk rating required, sets its help text, adds Source of funds and saves
- **THEN** the page refreshes in place showing the fields in the new order and labels, and the investor form has the new field and settings

#### Scenario: Shared by the form type
- **WHEN** the admin adds a field from one investor's page
- **THEN** another investor on the same form type shows the field on its form

#### Scenario: Form type created and linked
- **WHEN** the record has no form type, the firm has none for its record type, and the admin adds a field and saves
- **THEN** a form type is created for the firm with the field and the record is linked to it

### Requirement: Existing field settings the panel does not edit stay unchanged
A save from the panel SHALL NOT change an existing field's name, type, options, conditions, validation rules or
step, nor any regulatory or (for non-support users) calculation field.

#### Scenario: Rename keeps the field's data
- **WHEN** the admin renames the label of "KYC due" to "KYC review date" and saves
- **THEN** the field keeps its name, type and stored values

#### Scenario: Calculation guarded on save
- **WHEN** a save from a non-support user tries to change a calculation field
- **THEN** the calculation field is unchanged

### Requirement: Removing a field
Removing a field and saving SHALL delete the field's definition from the form type; values already stored on
records SHALL be kept. The panel SHALL say so before saving.

#### Scenario: Remove a field
- **WHEN** the admin removes "KYC due" and saves
- **THEN** investor pages and forms no longer show KYC due and the stored values remain on the records

### Requirement: Fields save validation
A save SHALL be refused, with the message on the panel and nothing changed, when a new field has no label, when
two fields would have the same name, when a Select field has no options, or when a label is longer than 254
characters. Changes to a field another user removed while the panel was open SHALL be skipped.

#### Scenario: Duplicate name
- **WHEN** the admin adds a field labelled "Risk rating" while Risk rating exists
- **THEN** the panel shows "A field named Risk rating already exists" and nothing is saved

#### Scenario: New field without a label
- **WHEN** the admin adds a field with an empty label
- **THEN** the field is not added and nothing is saved

#### Scenario: Select without options
- **WHEN** the admin adds a Select field with no options and saves
- **THEN** the save is refused with a message on that field

#### Scenario: Field removed meanwhile
- **WHEN** another admin removes KYC due while the panel is open and the admin then renames KYC due and saves
- **THEN** the save succeeds and KYC due stays removed

### Requirement: Access to the fields panel
Opening or saving the fields panel SHALL be refused, with nothing changed, for a user who is not a company admin
of the firm that owns the form type, for a user acting as an investor, for another firm's form type or record,
for a record the user may not view, and for a record type that has no custom fields. A save SHALL change only the form type's fields: any other field sent
SHALL be ignored.

#### Scenario: Direct request by a non-admin
- **WHEN** an employee who is not a company admin requests the fields panel or saves directly
- **THEN** the request is refused and nothing changes

#### Scenario: Direct request acting as investor
- **WHEN** a user acting as an investor requests the fields panel directly
- **THEN** the request is refused

#### Scenario: Another firm's record
- **WHEN** an admin requests the fields panel for another firm's record
- **THEN** the request is refused and that firm's form type is unchanged

#### Scenario: Unknown record type
- **WHEN** the fields panel is requested for a record type that has no custom fields
- **THEN** the request is refused as not found

#### Scenario: Extra fields ignored
- **WHEN** a save also sends a firm, a form type name or a field's conditions
- **THEN** only the panel's field settings change
