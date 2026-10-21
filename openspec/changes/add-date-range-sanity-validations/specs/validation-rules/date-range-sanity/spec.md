# Spec Delta

## Purpose

Stops obviously wrong business dates, such as typo'd years, from entering valuations, portfolio investments, fund ratio runs, allocation runs and Investor Statements. The allowed window of ±N years around today can be configured per entity.

## ADDED Requirements

### Requirement: Allowed date window
The system SHALL treat a checked date as in range when it lies between (today − `past_years` years) and (today + `future_years` years), both bounds inclusive. `today` is the application's current date at the moment of the check. `past_years` and `future_years` SHALL each default to 20. A blank or non-integer configured value SHALL be treated as 20. No fixed calendar floor or ceiling SHALL apply beyond this window.

#### Scenario: Date inside the window is accepted
- **WHEN** a checked date is 5 years before today and the entity uses the defaults
- **THEN** the date-range check does not fire

#### Scenario: Date too far in the past is rejected
- **WHEN** a checked date is 21 years before today and the entity uses the defaults
- **THEN** the date-range check fires

#### Scenario: Date too far in the future is rejected
- **WHEN** a checked date is 21 years after today and the entity uses the defaults
- **THEN** the date-range check fires

#### Scenario: Boundary dates are accepted
- **WHEN** a checked date is exactly 20 years before today, or exactly 20 years after today, and the entity uses the defaults
- **THEN** the date-range check does not fire

#### Scenario: Blank date is not checked
- **WHEN** a checked date is blank
- **THEN** the date-range check does not fire

#### Scenario: Invalid configured value falls back to default
- **WHEN** an entity sets `past_years` to a non-numeric value and a checked date is 21 years before today
- **THEN** the date-range check fires, as if `past_years` were 20

### Requirement: Per-entity configuration
Each entity SHALL be able to change `past_years` and `future_years`, change the severity between blocker and warning, or disable the check. It SHALL do this independently for each covered input, on the existing validation rule override screen. One entity's settings SHALL NOT affect any other entity.

#### Scenario: Entity widens the past window
- **WHEN** an entity overrides `past_years` to 30 for valuations, and a valuation date is 25 years before today
- **THEN** the valuation date-range check does not fire for that entity
- **AND** it still fires for another entity that uses the defaults

#### Scenario: Entity disables the check
- **WHEN** an entity disables the portfolio investment date-range rule and the valuation date-range rule
- **THEN** that entity can save a portfolio investment dated 50 years ago

#### Scenario: Portfolio investment creates are also checked by the valuation rule
- **WHEN** an entity disables only the portfolio investment date-range rule, and a user saves a new buy portfolio investment dated 50 years ago
- **THEN** the save is rejected with the valuation date-range message, because creating a buy also creates a valuation on the investment date

#### Scenario: Entity downgrades to a warning
- **WHEN** an entity sets the valuation date-range rule's severity to warning, and a user submits the valuation form with an out-of-range date
- **THEN** the user sees a confirmable warning instead of a rejection

### Requirement: Blocking by default
The date-range checks SHALL be enabled for every entity by default, with blocker severity. An out-of-range date SHALL be rejected with a message that includes the offending date and the configured `past_years` and `future_years`.

#### Scenario: Default behaviour for an entity with no overrides
- **WHEN** an entity with no overrides submits an out-of-range date on any covered input
- **THEN** the submission is rejected
- **AND** the message includes the submitted date and the values 20 and 20

### Requirement: Only new or changed dates are checked
For saved records, the system SHALL check a date only when the record is being created or that date is being changed. Editing other fields of an existing record whose stored date is out of range SHALL NOT be rejected by this check. The only exception is the valuation edit form, which checks the full submitted valuation.

#### Scenario: Legacy portfolio investment remains editable
- **WHEN** an existing portfolio investment dated 25 years ago has another field changed, and its investment date is left unchanged
- **THEN** the save succeeds

#### Scenario: Changing a legacy date is checked
- **WHEN** an existing portfolio investment's date is changed to a date 25 years ago
- **THEN** the save is rejected

### Requirement: Covered inputs
The system SHALL apply the date-range check, as a separately configurable rule, to each of the following:
- Valuation date on valuations created or edited by form, API or import
- Investment date on portfolio investments created or edited by form, API or import
- End date for Generate Fund Ratios (fund, cross-fund and cross-portfolio) and for fund ratio records
- End date submitted when triggering fund ratio run templates (single or by tag)
- Start date and end date of allocation runs, whether started manually or from an allocation group run
- Start date and end date submitted for Investor Statement generation on a capital commitment

A rejected run or generation request SHALL NOT enqueue any background work.

#### Scenario: Valuation with an out-of-range date
- **WHEN** a user saves a valuation dated 0224-03-31
- **THEN** the valuation is not saved and the form shows the date-range message

#### Scenario: Valuation import row with an out-of-range date
- **WHEN** a valuation import file contains one row dated 2204-03-31 among valid rows
- **THEN** that row fails with the date-range message and the valid rows are imported

#### Scenario: Portfolio investment with an out-of-range date
- **WHEN** a user saves a new portfolio investment dated 21 years after today
- **THEN** the save is rejected and the form shows the date-range message

#### Scenario: Portfolio investment import row with an out-of-range date
- **WHEN** a portfolio investment import file contains a valid row followed by a row dated 0224-01-15
- **THEN** that row fails with the date-range message and the valid row before it is imported
- **AND** any rows after it are skipped, as portfolio investment imports already stop at the first failed row

#### Scenario: Generate fund ratios with an out-of-range end date
- **WHEN** a user submits Generate Fund Ratios with an end date 30 years before today
- **THEN** no ratio calculation is started and the user sees the date-range message

#### Scenario: Fund ratio run template triggered with an out-of-range end date
- **WHEN** a user triggers a single fund ratio run template with an end date 25 years after today
- **THEN** no ratio calculation is enqueued and the user sees the date-range message

#### Scenario: Fund ratio run templates triggered by tag with an out-of-range end date
- **WHEN** a user triggers all templates for a tag with an end date 25 years after today
- **THEN** every template is skipped and no ratio calculation is enqueued

#### Scenario: Manual allocation run with an out-of-range start date
- **WHEN** a user starts an allocation run whose start date is 0224-01-01
- **THEN** no allocation run is created or started and the user sees the date-range message

#### Scenario: Allocation group run with out-of-range dates
- **WHEN** an allocation group run is checked for a period whose end date is 25 years after today
- **THEN** the pre-run checks list the date-range message as a blocker

#### Scenario: Investor Statement with an out-of-range end date
- **WHEN** a user requests an Investor Statement on a capital commitment with an end date 25 years after today
- **THEN** no statement generation is started and the user sees the date-range message

#### Scenario: Investor Statement with in-range dates
- **WHEN** a user requests an Investor Statement with a start date 1 year ago and an end date of today
- **THEN** statement generation starts as it does today
