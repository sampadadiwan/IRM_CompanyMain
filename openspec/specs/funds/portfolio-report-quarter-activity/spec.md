# funds/portfolio-report-quarter-activity Specification

## Purpose
Defines the quarter activity the company portfolio report offers for each fund: whether the company was bought or sold in the quarter and the cost of each, so a Word template can describe what the fund did in the period.

## Requirements

### Requirement: Purchases in the quarter
For each fund the company has investments in, the fund's data in the company portfolio report SHALL carry `buy_pis_present` (true when the company has at least one purchase in that fund dated from the report's start date to its end date, both included) and `cost_of_investment_between` (the cost of those purchases, in the fund's currency, zero when there are none). Purchases of other funds and other companies SHALL NOT be counted, nor purchases dated before the start date or after the end date.

#### Scenario: Purchase in the quarter
- **WHEN** the company bought 500 shares for 10 Cr on 15 Aug and the report runs 1 Jul to 30 Sep
- **THEN** `buy_pis_present` is true and `cost_of_investment_between` is 10 Cr

#### Scenario: Several purchases in the quarter
- **WHEN** the company bought for 10 Cr on 15 Aug and for 4 Cr on 20 Sep
- **THEN** `cost_of_investment_between` is 14 Cr

#### Scenario: Only an earlier purchase
- **WHEN** the company's only purchase is dated before the start date
- **THEN** `buy_pis_present` is false and `cost_of_investment_between` is zero

#### Scenario: Purchase on the start date or the end date
- **WHEN** a purchase is dated 1 Jul, or 30 Sep, for a report from 1 Jul to 30 Sep
- **THEN** it is counted

#### Scenario: Dates given as text
- **WHEN** the report's start and end dates reach the report as text, such as "2026-07-01"
- **THEN** the same purchases and sales are counted as when they are dates

#### Scenario: Purchase outside the period
- **WHEN** a purchase is dated 30 Jun or 1 Oct for a report from 1 Jul to 30 Sep
- **THEN** it is not counted

#### Scenario: Fully exited before the quarter
- **WHEN** the company bought and sold everything before the start date
- **THEN** the fund's data is still present with both flags false and both amounts zero

#### Scenario: Funds and companies are kept apart
- **WHEN** the company bought in two funds, or another company bought in the same fund, in the quarter
- **THEN** each fund's data counts only this company's purchases in that fund

### Requirement: Sales in the quarter
For each fund the company has investments in, the fund's data SHALL carry `sell_pis_present` (true when the company has at least one sale in that fund dated from the start date to the end date, both included) and `cost_of_sold_between` (the cost of the shares sold in those sales, as a positive amount in the fund's currency, zero when there are none). `cost_of_sold_between` SHALL be the cost of what was sold, not the money received.

#### Scenario: Sale in the quarter
- **WHEN** the company sold 500 shares, received 7 Cr, at a cost of 5 Cr on 10 Sep
- **THEN** `sell_pis_present` is true and `cost_of_sold_between` is 5 Cr

#### Scenario: Sale on the start date or the end date
- **WHEN** a sale is dated 1 Jul, or 30 Sep, for a report from 1 Jul to 30 Sep
- **THEN** it is counted

#### Scenario: Sale before the quarter
- **WHEN** the company's only sale is dated before the start date
- **THEN** `sell_pis_present` is false and `cost_of_sold_between` is zero

#### Scenario: Buy and sale in the same quarter
- **WHEN** the company bought and sold in the quarter
- **THEN** both flags are true and both amounts are shown

#### Scenario: Sale only
- **WHEN** the company sold in the quarter and did not buy
- **THEN** `buy_pis_present` is false, `cost_of_investment_between` is zero and the sale fields are shown

### Requirement: Existing fund data is unchanged
The fund's data SHALL keep every existing field with the same values. A fund the company has no investment in SHALL still have no fund data, and a template that does not use the new fields SHALL render as before.

#### Scenario: Existing fund data fields
- **WHEN** the report is generated
- **THEN** the cost of investment up to the end date, the cost of what is still held, the sold amount, the fair market value, the IRR and the MOIC are the same as before
