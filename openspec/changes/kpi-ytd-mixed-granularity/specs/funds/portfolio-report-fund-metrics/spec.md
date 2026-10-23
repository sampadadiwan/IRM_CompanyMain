# Spec Delta

## Purpose

Defines the company-level investment fields and the per-fund return ratios the Word portfolio report offers: the stake
and first investment date of the portfolio company across all its funds, and the company's IRR (XIRR) and MOIC in each fund.

## ADDED Requirements

### Requirement: Latest and earliest investment across all funds
The portfolio report SHALL offer `latest_pi` and `earliest_pi`: the portfolio
company's latest investment (a buy or a sale) and first buy across all its funds, dated on or before the report's end
date. The template reads the `stake` custom field off the latest one and the investment date off the earliest one. Ties
on date SHALL resolve to the later-created investment for the latest and the earlier-created for the earliest. When the
company has no such investment, both SHALL be blank, so a template that reads them still renders.

#### Scenario: Latest and earliest across funds
- **WHEN** the company has buys in two funds, dated 15 Mar 2024, 10 Jan 2025 and 1 Sep 2025 (the last with stake 12.5)
- **THEN** the latest investment's stake is 12.5 and the earliest investment's date is 15 Mar 2024

#### Scenario: A later sale is the latest investment
- **WHEN** the company's last transaction before the end date is a sale
- **THEN** the latest investment is that sale, and the earliest investment is still the first buy

#### Scenario: Investments after the end date
- **WHEN** a buy is dated after the report's end date
- **THEN** it is not used

#### Scenario: No investment
- **WHEN** the company has no investment on or before the end date
- **THEN** the latest investment's stake and the earliest investment's date are blank and the report is generated

#### Scenario: Stake not recorded
- **WHEN** the latest investment has no stake recorded
- **THEN** its stake is blank and the earliest investment's date is still shown

### Requirement: IRR and MOIC of the company in each fund
For each fund the company has investments in, the fund's data in the portfolio report (`<fund>_data`) SHALL carry
`irr` (XIRR, in percent) and `moic` (as a multiple), taken from the stored fund ratios of that company in that fund:
the ratio named IRR or MOIC, Default scenario, fund currency, whose end date is the latest on or before the report's end
date. A ratio that was never run SHALL be "N/A". Ratios are read, never recomputed, when the report is generated.

#### Scenario: IRR and MOIC for each fund
- **WHEN** the company has IRR 14.5 and MOIC 1.8 in Alpha Fund and IRR -3.2 and MOIC 0.9 in Beta Fund
- **THEN** each fund's data shows its own irr and moic

#### Scenario: Ratio not run
- **WHEN** a fund has no stored IRR or MOIC for the company
- **THEN** that field is "N/A"

#### Scenario: Ratio as of the end date
- **WHEN** the company's IRR was stored for 31 Dec 2025, 30 Jun 2026 and 30 Sep 2026 and the report ends 30 Jun 2026
- **THEN** the 30 Jun 2026 figure is shown

#### Scenario: Other scenarios and other owners are ignored
- **WHEN** a Bull Case ratio of the company, or the fund's own IRR, exists for a later date
- **THEN** neither is used; the company's Default-scenario ratio is
