# startups/investment-subgroups Specification

## Purpose
Lets an investment carry a subgroup and instrument details, and makes the funding round and
horizontal cap tables group investments by subgroup, category and instrument. Investment-based
cap tables then read the same way as ones built from Shareholder Position uploads.

## Requirements

### Requirement: Investment subgroup
An investment SHALL have an optional subgroup of at most 100 characters. The subgroup SHALL be:
- entered on the investment form
- shown on the investment page
- searchable through the investments filter

#### Scenario: Subgroup saved from the form
- **WHEN** a user creates a Convertible investment through the form with subgroup "Institutional", instrument name "CCPS Series A" and instrument quantity 15
- **THEN** the investment is saved with that subgroup and instrument
- **AND** its page shows the subgroup

#### Scenario: Subgroup too long
- **WHEN** a user submits an investment whose subgroup is 101 characters long
- **THEN** a "too long" error is shown and no investment is created

#### Scenario: Filter by subgroup
- **WHEN** a user filters investments by subgroup "Institutional"
- **THEN** only investments with that subgroup are listed

### Requirement: Instrument details only for Convertibles
The investment form SHALL label the investment type "Instrument Type". It SHALL only show the
instrument name and instrument quantity fields for a Convertible. An Equity investment SHALL
never keep an instrument name or instrument quantity: both SHALL be cleared when it is saved.

#### Scenario: Instrument fields follow the instrument type
- **WHEN** a user picks "Equity" on the investment form
- **THEN** the instrument name and quantity fields are hidden
- **WHEN** they pick "Convertible"
- **THEN** the instrument name and quantity fields are shown

#### Scenario: Equity instrument details cleared
- **WHEN** an Equity investment is saved with instrument name "CCPS" and instrument quantity 10
- **THEN** it is stored with no instrument name and no instrument quantity

### Requirement: Subgroup nesting in the horizontal cap table
The horizontal cap table SHALL nest an investor under a subgroup row within their category.
The investor SHALL be nested under the first non-blank subgroup across their investments in
that category and instrument. An investor with no subgroup SHALL sit directly under the
category. An investor SHALL appear only once, even when only some of their rounds carry a
subgroup.

#### Scenario: Investors nested by subgroup
- **WHEN** a company has a Founder with no subgroup, an Other investor in subgroup "Angel" and an Other investor in subgroup "Institutional"
- **THEN** the Founder is listed directly under "Founders"
- **AND** the other two are listed under their subgroup rows within "Others"

#### Scenario: Subgroup on only one round
- **WHEN** an investor has a Seed investment with no subgroup and a Series A investment in subgroup "Institutional"
- **THEN** the horizontal cap table lists them once, under "Institutional"

### Requirement: One row per instrument and per category
The funding round cap table SHALL show a separate row for each investor and instrument. The
horizontal cap table SHALL show a separate row for each investor, category and instrument. Each
row SHALL have its own quantity and fully diluted percentage. The instrument column SHALL show:
- "Equity" for Equity investments
- the instrument name for Convertibles

#### Scenario: Equity and a Convertible held by the same investor
- **WHEN** a Founder holds 1,000 Equity shares and a Convertible of 10 CCPS converting into 1,000 shares in Seed
- **THEN** both cap tables show one "Equity" row and one "CCPS" row for that investor
- **AND** each row is 50% fully diluted

#### Scenario: The same investor under two categories
- **WHEN** an investor holds Equity as a Founder and a CCPS Convertible as Other
- **THEN** the horizontal cap table lists them once under "Founders" and once under "Others"

### Requirement: Convertible quantity split
A Convertible's instrument quantity SHALL count towards Quantity actual. The rest of its
quantity SHALL count towards the fully diluted quantity only. Quantity actual plus the dilution
SHALL add up to the Convertible's quantity.

#### Scenario: CCPS converting into shares
- **WHEN** Seed has 985 Equity shares and a Convertible of 15 "CCPS Series A" converting into 1,500 shares
- **THEN** the Convertible row shows quantity 15 (1.5%) and fully diluted 1,500 (60.36%)
- **AND** the total row shows quantity 1,000 and fully diluted 2,485

### Requirement: Investment import of subgroup and instrument
The investment import SHALL read these columns, on both created and update-only rows:
- `Subgroup`, also accepted as `SubGroup` or `Sub Group`
- `Instrument Name`
- `Instrument Quantity`

These columns SHALL NOT be stored as custom fields.

#### Scenario: Subgroup header spellings
- **WHEN** an investments file with a "Subgroup", "SubGroup" or "Sub Group" column is uploaded
- **THEN** the investment is created with that subgroup

#### Scenario: Update-only row
- **WHEN** an update-only row for an existing investment gives a new subgroup, instrument name and instrument quantity
- **THEN** the investment is updated with those values
