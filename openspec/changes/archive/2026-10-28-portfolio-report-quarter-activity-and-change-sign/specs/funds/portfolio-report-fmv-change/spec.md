# Spec Delta

## Purpose

Defines the change in fair market value the consolidated portfolio report shows for each company's line in a fund and for each fund total: the weighted average change in the instruments' value per unit, so buying or selling units in the period does not read as a gain or a loss.

## ADDED Requirements

### Requirement: Fair market value change is the change in value per unit
The consolidated report's `fmv_change_percent` (against the day before the start date, on each company's fund line and each fund total) and `fmv_fy_start_change_percent` (against the day before the financial year start, on each company's fund line) SHALL be the weighted average, over the instruments the company held at that earlier date, of each instrument's change in value per unit from that date to the end date, each instrument weighted by its value at the earlier date. The value per unit of an instrument at a date SHALL be its latest valuation on or before that date, in the fund's currency. Units bought after the earlier date SHALL NOT affect the change, and units sold after it SHALL NOT make the holding read as a loss. The change SHALL be "N/A" when the value at the earlier date is zero. The amounts `fmv`, `fmv_prior` and `fmv_fy_start` SHALL stay as they are: the units held at each date at that date's value per unit.

#### Scenario: Price rises and units are bought
- **WHEN** the company held 10 units valued at 100 each on the day before the start, bought 5 more in the period, and the value per unit is 110 at the end date
- **THEN** `fmv_change_percent` is 10, `fmv_prior` is 1,000 and `fmv` is 1,650

#### Scenario: Price rises and units are sold
- **WHEN** the company held 10 units valued at 100 each on the day before the start, sold 4 in the period, and the value per unit is 110 at the end date
- **THEN** `fmv_change_percent` is 10

#### Scenario: Holding sold entirely in the period
- **WHEN** the company held 10 units valued at 100 each on the day before the start, sold all 10 in the period, and the value per unit was 110 at the end date
- **THEN** `fmv_change_percent` is 10, not -100

#### Scenario: Several instruments are weighted by prior value
- **WHEN** one instrument was worth 1,000 at the earlier date and its value per unit rose 10%, and another was worth 3,000 and its value per unit fell 20%
- **THEN** `fmv_change_percent` is -12.5

#### Scenario: Price unchanged or falling
- **WHEN** the value per unit is the same at the end date, or lower
- **THEN** the change is 0, or negative by the percentage fall

#### Scenario: Financial year start
- **WHEN** the company held 8 units valued at 90 each on the day before the financial year start and the value per unit is 108 at the end date
- **THEN** `fmv_fy_start_change_percent` is 20 whatever it held at the day before the start

#### Scenario: Fund total from the companies' figures
- **WHEN** two companies hold instruments in one fund with prior values 1,000 and 3,000 and the units they held then are worth 1,100 and 2,400 at the end date's value per unit
- **THEN** the fund total's `fmv_change_percent` is -12.5, worked out from the two sums and not by averaging the two companies' percentages

#### Scenario: Older valuation is used
- **WHEN** the latest valuation on or before the earlier date is dated before it
- **THEN** that valuation's value per unit is used for the earlier date

#### Scenario: Fund currency
- **WHEN** the instrument is valued in a currency other than the fund's
- **THEN** the change is measured in the fund's currency, as the amounts shown are

#### Scenario: Purchase price before any valuation
- **WHEN** the company bought 10 units at 100 each before the start, no valuation is stored before the start, and the value per unit is 110 at the end date
- **THEN** the purchase price is the value per unit at the earlier date and `fmv_change_percent` is 10

#### Scenario: Bought only in the period
- **WHEN** the company bought its only units in the period
- **THEN** `fmv_change_percent` is "N/A"

#### Scenario: Amounts unchanged
- **WHEN** units are bought or sold in the period
- **THEN** `fmv`, `fmv_prior` and `fmv_fy_start` are the same as before this requirement

### Requirement: Fair market value change follows the direction of the movement
The change SHALL be divided by the size of the value at the earlier date, so a negative value at the earlier date does not reverse its sign, and SHALL be "N/A" when that value is zero.

#### Scenario: Negative base value
- **WHEN** the value at the earlier date is -100 and the earlier holdings are worth -60 at the end date's value per unit
- **THEN** the change is 40

#### Scenario: Positive base value
- **WHEN** the value at the earlier date is 100 and the earlier holdings are worth 120 at the end date's value per unit
- **THEN** the change is 20

#### Scenario: Base value zero
- **WHEN** the value at the earlier date is zero
- **THEN** the change is "N/A"
