# funds/portfolio-report-category-gross-irr Specification

## Purpose
Defines two fields a portfolio report template can read: the category of each KPI row in the per-company report, and the fund's Gross Portfolio IRR in the consolidated report's fund totals.

## Requirements

### Requirement: Each KPI row exposes its category
In the per-company report, every KPI row SHALL expose `category`, the category of the KPI mapping behind the row, as saved and without a change of case. A mapping with no category SHALL give a blank `category`. The row SHALL carry the same `category` in the all-KPIs list and in the list of its own category. All other fields of the row, including `data_type`, SHALL be unchanged.

#### Scenario: Row carries its mapping's category
- **WHEN** the report is built for a company whose "Revenue" KPI mapping has the category "Financial"
- **THEN** the "Revenue" row shows the category "Financial"

#### Scenario: Category keeps its case
- **WHEN** a mapping has the category "Customer Metrics"
- **THEN** its row shows "Customer Metrics", not "customer metrics"

#### Scenario: Same category in the category's own list
- **WHEN** the report is built and the "Revenue" row is read from the "Financial" list as well as from the all-KPIs list
- **THEN** both rows show the category "Financial"

#### Scenario: Mapping without a category
- **WHEN** a "Headcount" KPI mapping has no category
- **THEN** its row shows a blank category and the report is built

#### Scenario: Existing row fields are unchanged
- **WHEN** the report is built for a mapping with data type "percentage"
- **THEN** the row still shows the data type "percentage" and the same period values as before

### Requirement: The fund total exposes the fund's Gross Portfolio IRR
In the consolidated report, each fund total SHALL expose `gross_portfolio_irr`, the fund's own stored Gross Portfolio IRR: the latest run dated on or before the end date, in the Default scenario. A fund with no such run SHALL show "N/A". All other fields of the fund total, including `irr`, SHALL be unchanged.

#### Scenario: Latest run on or before the end date
- **WHEN** a fund has Gross Portfolio IRR runs of 16.0 on 30 Jun 2026 and 18.0 on 30 Sep 2026 and the end date is 30 Sep 2026
- **THEN** the fund total's `gross_portfolio_irr` is 18.0

#### Scenario: A run after the end date is ignored
- **WHEN** the fund also has a run of 19.5 dated 15 Oct 2026 and the end date is 30 Sep 2026
- **THEN** the fund total's `gross_portfolio_irr` is still 18.0

#### Scenario: A run in another scenario is ignored
- **WHEN** the only run on or before the end date is in a scenario other than Default
- **THEN** the fund total's `gross_portfolio_irr` is "N/A"

#### Scenario: No run
- **WHEN** the fund has never had a Gross Portfolio IRR run
- **THEN** the fund total's `gross_portfolio_irr` is "N/A" and the report is built

#### Scenario: Shown beside the fund's IRR
- **WHEN** a fund has an XIRR of 14.2 and a Gross Portfolio IRR of 18.0 on the end date
- **THEN** the fund total shows `irr` 14.2 and `gross_portfolio_irr` 18.0

#### Scenario: Each fund has its own value
- **WHEN** two funds have Gross Portfolio IRRs of 18.0 and 11.5
- **THEN** each fund total shows its own value

### Requirement: Company fund lines and fund data show the fund's Gross Portfolio IRR
The consolidated report's per-company fund lines and the per-company report's fund data (`<fund>_data`) SHALL each carry `gross_portfolio_irr`: the fund's own Gross Portfolio IRR, worked out as for the fund total, and the same for every company in the fund. Their `irr` SHALL stay the company's own IRR in the fund.

#### Scenario: Company fund line shows both
- **WHEN** a company has an IRR of 22.0 in a fund whose Gross Portfolio IRR is 18.0
- **THEN** the company's fund line shows `irr` 22.0 and `gross_portfolio_irr` 18.0

#### Scenario: Company report fund data shows both
- **WHEN** the same company's report is generated
- **THEN** the fund's data shows `irr` 22.0 and `gross_portfolio_irr` 18.0

#### Scenario: Every company in the fund shows the fund's value
- **WHEN** two companies invested in a fund whose Gross Portfolio IRR is 18.0
- **THEN** both companies' fund lines show 18.0, and the fund total shows 18.0 once

#### Scenario: No run on the lines and the fund data
- **WHEN** the fund has no Gross Portfolio IRR run on or before the end date, or only one in another scenario
- **THEN** the company's fund line and fund data show "N/A"

#### Scenario: Run after the end date on the lines and the fund data
- **WHEN** a Gross Portfolio IRR run is dated after the end date
- **THEN** the fund line and the fund data use the latest run on or before it
