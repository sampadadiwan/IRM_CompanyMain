# Spec Delta

## Purpose

Defines what a Report Builder report returns for each row: which columns can be picked, how related data of every kind is fetched and totalled, how formulas evaluate, the order of columns, and which rows are included.

## ADDED Requirements

### Requirement: Parent and one-per-row related data
The system SHALL return the related record's value on each row for related data that has at most one record per row (a parent such as a commitment's fund, a one-to-one record, or a record reached through another association). A row whose related record is missing SHALL show an empty value.

#### Scenario: Parent value shown
- **WHEN** a Capital Commitment report includes the fund's name as related data
- **THEN** each row shows the name of that commitment's fund

#### Scenario: One-to-one through another record
- **WHEN** a Capital Remittance Payment report includes the capital call's name
- **THEN** each row shows the name of the call its remittance belongs to

#### Scenario: Missing parent
- **WHEN** a row's parent record does not exist
- **THEN** that row shows an empty value and the report still renders

### Requirement: Related data two or more steps away
The system SHALL return values for related data reached through a chain of associations (for example an investor's funds through their commitments), alongside any first-level related data from the same chain.

#### Scenario: Two-step related data
- **WHEN** an Investor report includes the fund name through capital commitments with the List total
- **THEN** each investor shows the distinct names of the funds they have commitments in

#### Scenario: First-level and two-step together
- **WHEN** the same report also includes the committed amount from capital commitments
- **THEN** both the committed total and the fund names are correct for every investor

#### Scenario: Chain no longer resolves
- **WHEN** a saved related-data chain names an association that no longer exists
- **THEN** that column shows empty values and the rest of the report renders

### Requirement: Polymorphic related data is scoped to its owner type
The system SHALL count and total related records attached through an owner-type link (such as documents) only for records of the report's own type.

#### Scenario: Documents of another owner type excluded
- **WHEN** a Capital Commitment report counts documents and a document of another type has the same owner id
- **THEN** the count includes only the commitment's own documents

### Requirement: Display-layer columns are readable and filter-only fields are not offered as columns
The system SHALL show a value for every column it offers on the report's own rows, including values provided by the record's display layer. Fields that can be filtered on but have no readable value SHALL NOT be offered as columns, and SHALL remain available as filters. Related-data columns SHALL only offer fields that exist on the related records.

#### Scenario: Display-layer column has a value
- **WHEN** a Capital Remittance report includes Investing Entity
- **THEN** each row shows the investing entity's name

#### Scenario: Filter-only field not offered as a column
- **WHEN** a user opens the column list for Capital Distribution
- **THEN** Carry is not offered as a column but is offered as a filter

#### Scenario: Related column list offers only stored fields
- **WHEN** a user opens the column list for capital commitments added as related data
- **THEN** fields that only exist in the display layer, such as Investing Entity, are not offered

#### Scenario: Every offered column resolves
- **WHEN** the column list of any reportable table is checked against a record of that table
- **THEN** every offered column returns a value or an empty value without raising

### Requirement: Default totals for related columns
Every related column on many-per-row related data SHALL have a total. When a column is added without one, the system SHALL save a default chosen by the column's type: Sum for amounts and numbers, Latest date (maximum) for dates, Any yes for yes/no, Latest value for text. A column saved earlier without a total SHALL be shown with the same default. Only Sum, Count, Average, Minimum, Maximum, Latest and List SHALL be accepted as totals.

#### Scenario: Amount defaults to Sum and is saved
- **WHEN** a user adds Committed from capital commitments to an Investor report
- **THEN** the total saved for that column is Sum and the column shows each investor's summed commitments

#### Scenario: Date, yes/no and text defaults
- **WHEN** a user adds Commitment date, Onboarding completed and Unit type from capital commitments
- **THEN** their totals are Latest date, Any yes and Latest value respectively

#### Scenario: Legacy column without a total
- **WHEN** a report saved before this change has a related column with no total
- **THEN** the column shows values using its type's default total

#### Scenario: Unknown total refused
- **WHEN** a request sets a total that is not in the allowed list
- **THEN** the change is refused and the previous total is kept

### Requirement: Yes/no totals read as Yes or No
A yes/no related column totalled with Minimum, Maximum, Any yes or Latest SHALL show Yes or No. A Count of a yes/no column SHALL show a number.

#### Scenario: Minimum of yes/no
- **WHEN** an investor has one commitment with onboarding completed and one without, and the column uses Minimum
- **THEN** the investor's row shows No

#### Scenario: Count of yes/no
- **WHEN** the same column uses Count
- **THEN** the row shows 2

### Requirement: Formulas evaluate on plain numbers
Formulas SHALL treat amount values, whether from the report's own rows or from related totals, as plain numbers, so ratios, rounding and mixed inputs work. A formula that cannot be evaluated for a row (for example division by zero) SHALL produce an empty value for that row only.

#### Scenario: Ratio of two amounts
- **WHEN** a Capital Commitment report has `ROUND([committed_amount] / [call_amount], 2)` and the values are 5,00,00,000 and 2,00,00,000
- **THEN** the formula column shows 2.50 as a number

#### Scenario: Own amount minus related total
- **WHEN** a formula subtracts a related Collected total from the row's own Committed amount
- **THEN** the result is the difference as a number

#### Scenario: Division by zero
- **WHEN** the divisor is zero for a row
- **THEN** that row's formula value is empty and other rows are unaffected

### Requirement: Column order includes formulas and pivots
Formula columns and each pivot's block of columns SHALL take a position in the report's column order and keep it everywhere the report is shown or exported. A newly added formula or pivot SHALL go last. Reports saved before this change SHALL keep formulas and pivots after all other columns.

#### Scenario: Formula moved next to its input
- **WHEN** a user moves Called % to just after Called
- **THEN** preview, report page and Excel all show Called % immediately after Called

#### Scenario: Pivot block moves as one
- **WHEN** a user moves a pivot to the second position
- **THEN** all of that pivot's columns appear together from the second position

#### Scenario: Legacy order unchanged
- **WHEN** a report saved before this change is shown
- **THEN** its formulas and pivots appear after all other columns as before

#### Scenario: Removing a formula or pivot removes its position
- **WHEN** a formula is removed, a pivot is cleared or its related data is removed
- **THEN** no empty or orphaned column remains in the order

### Requirement: Pivot headers name their related data
Each pivot column header SHALL begin with the name of the related data it came from.

#### Scenario: Two pivots with the same values
- **WHEN** an Investor report pivots commitments by unit type and fund units by unit type
- **THEN** the headers read "Capital commitments · A (sum)" and "Fund units · A (sum)"

### Requirement: Only rows that have related data
For many-per-row related data the system SHALL offer a setting to include only report rows that have at least one matching related record, respecting that related data's own filters. It SHALL be off by default, and the row count and pages SHALL match the included rows.

#### Scenario: Investors without commitments left out
- **WHEN** the setting is on for capital commitments and one investor has no commitments
- **THEN** that investor is not in the report and the row count excludes them

#### Scenario: Respects the related data's filters
- **WHEN** the setting is on for capital remittances with the related filter Status = Overdue
- **THEN** only investors with at least one overdue remittance are included

#### Scenario: Off by default
- **WHEN** related data is added
- **THEN** every row of the report's own table is included, with zero totals where there is no related data

#### Scenario: Not offered on one-per-row related data
- **WHEN** a request turns the setting on for one-per-row related data such as a commitment's fund
- **THEN** the change is refused and the report is unchanged

#### Scenario: Only-rows setting changed by another entity's user is refused
- **WHEN** a user of another entity requests a change to the setting
- **THEN** access is refused and the report is unchanged
