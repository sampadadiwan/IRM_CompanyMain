# Portfolio Report Fund Metrics — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X), so a failure
> maps straight to the automated test that should have caught it.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey
step · **R** = Role sweep · **C** = Cross-cutting check

---

## Contents

- [Test Setup](#test-setup)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [UI Journeys](#ui-journeys)
- [Role Sweep](#role-sweep)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

---

## Test Setup

| Item | Detail |
|---|---|
| Environment | Staging, with the updated Summary, Disclaimer and LP Word templates uploaded |
| Accounts | One fund admin (company admin) of the test entity |
| Second entity | A user of a different entity, for the isolation check |
| Seed data | Fund "Inflexor Technology Discovery Fund 1" (INR, committed 502 Cr, collected 125.5 Cr, no financial-year setting, default April). Company A: buys 40 Cr (2026-02-10) and 10 Cr (2026-08-15), a sell on 2026-09-10 (sale price 7 Cr, cost 5 Cr), valuations 45 Cr at 31-Mar, 50 Cr at 30-Jun, 60 Cr at 30-Sep. Company B: buy 30 Cr (2026-01-20), valuations 28 / 24 / 21 Cr at the same dates. Later records: a commitment of 20 Cr dated 2026-10-10 and a verified payment of 5 Cr received 2026-10-05. Fund ratios: TVPI 1.1 (30-Jun) and 1.2 (30-Sep), XIRR 18.5, MOIC 1.4, no DPI. Revenue KPI: YTD 30-Jun Actual 92 and Budget 100; Quarter Actual 75 and Budget 60 |
| Run A | Portfolio reports › Bulk generate: select Company A and Company B, start 2026-07-01, end 2026-09-30, add the Summary report (consolidated) and the Disclaimer report, Generate. Open the downloaded document |
| Run B | Generate the LP report for Company A alone with the same dates |
| Background work | Generation runs in the background; wait for the "completed" toast |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Prior value | Seed data | 1. Run A 2. Disclaimer table, Company A row | FMV Jun-26 = 50.0 | | |
| ☐ | H2 | April financial year | Seed data | 1. Run A 2. Disclaimer table, Company A row | FMV 31-Mar-26 = 45.0 | | |
| ☐ | H3 | Fund money | Seed data | 1. Run A 2. Fund snapshot | Commitments 502.0, Capital drawn 125.5 | | |
| ☐ | H4 | Purchases around the start | Seed data | 1. Run A 2. Roll-forward, Company A | Jun-26 cost 40.0, Invested in qtr 10.0 | | |
| ☐ | H5 | Exits positive | Seed data | 1. Run A 2. Roll-forward, Company A | Exits in qtr = 5.0 (not negative) | | |
| ☐ | H6 | Roll-forward adds up | Seed data | 1. Run A 2. Roll-forward, Company A | Sep-26 cost = 45.0 and 40.0 + 10.0 − 5.0 = 45.0 | | |
| ☐ | H7 | Value rises | Seed data | 1. Run A 2. Roll-forward, Company A | FMV 50.0 → 60.0, Change % 20.0 | | |
| ☐ | H8 | Change since FY start | Seed data | 1. Run A 2. Disclaimer table, Company A | FYTD chg 33.3% | | |
| ☐ | H9 | Collection percentages | Seed data | 1. Run A 2. Fund snapshot | Capital drawn 25.0% of commitments; Uncalled 376.5, 75.0% | | |
| ☐ | H10 | Totals add up | Seed data | 1. Run A 2. Roll-forward Total row | FMV Jun-26 74.0, Sep-26 81.0, Change % 9.5 | | |
| ☐ | H11 | Roll-forward total adds up | Seed data | 1. Run A 2. Total row cost | 70.0, 10.0, 5.0, 75.0 (70 + 10 − 5 = 75) | | |
| ☐ | H12 | Latest fund ratio | Seed data | 1. Run A 2. Fund returns | TVPI 1.2x | | |
| ☐ | H13 | IRR from XIRR | Seed data | 1. Run A 2. Fund returns | Gross IRR 18.5% | | |
| ☐ | H14 | Sold amount | Seed data | 1. Run B 2. Company box | Realised 7.0 | | |
| ☐ | H15 | Cost of remaining on the company page | Seed data and a template showing cost of remaining | 1. Run B | Cost of remaining 45.0; Invested still 50.0 | | |
| ☐ | H16 | Actual below Budget | Seed data | 1. Run B 2. Key metrics, Revenue, YTD | vs Budget −8.0% | | |
| ☐ | H17 | Actual above Budget | Seed data | 1. Run B 2. Key metrics, Revenue, Quarter | vs Budget 25.0% | | |
| ☐ | H18 | As-of figures match the fund today | A fund with commitments, payments, distributions and units | 1. Run A with the end date set to today 2. Fund snapshot | Commitments raised and Capital drawn equal the fund page's committed and collected amounts | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Buy on the start date | Add a buy of 3 Cr dated 2026-07-01 to Company B | 1. Run A | Counted in Invested in qtr, not in Jun-26 cost | | |
| ☐ | E2 | Buy on the end date | Add a buy of 2 Cr dated 2026-09-30 | 1. Run A | Counted in Invested in qtr | | |
| ☐ | E3 | January year on the fund | Set the fund's financial year to start in January | 1. Run A 2. Disclaimer table | FMV start-of-year column is as of 31-Dec-2025 | | |
| ☐ | E4 | Entity setting used | Fund has no setting; entity year starts in January | 1. Run A | Same as E3 | | |
| ☐ | E5 | Quarter starts at FY start | Run with start 2026-04-01 and end 2026-06-30 | 1. Run A with those dates | FMV 31-Mar-26 equals the prior-quarter FMV | | |
| ☐ | E6 | Money as of a past end date | Collected has increased after 30-Sep | 1. Run A for end 2026-09-30 | Capital drawn shows the amount as of 30-Sep, not today's | | |
| ☐ | E7 | No exits | Remove the sell | 1. Run A | Exits in qtr 0.0; Sep-26 = Jun-26 + Invested | | |
| ☐ | E8 | Gross cost unchanged by exits | Seed data | 1. Run A 2. Fund snapshot | Invested in portfolio = 80.0 (all purchases), while Sep-26 cost total is 75.0 | | |
| ☐ | E9 | No holding before start | A company whose first buy is in the quarter | 1. Run A | Jun-26 cost 0.0 | | |
| ☐ | E10 | Value falls | Seed data | 1. Run A 2. Company B | Change % −12.5 | | |
| ☐ | E11 | Purchase raises the change | Company with 10 Cr FMV at Jun-26, buy another 10 Cr in the quarter, no revaluation | 1. Run A | Change % 100.0 | | |
| ☐ | E12 | No prior value | Company with no valuation before 2026-07-01 | 1. Run A | Change % shows N/A | | |
| ☐ | E13 | No value at FY start | Company with no valuation before 2026-03-31 | 1. Run A | FYTD chg shows N/A | | |
| ☐ | E14 | Existing template unchanged | A template that uses only name, FMV, cost, IRR, MOIC | 1. Run A with it | Output same as before this release | | |
| ☐ | E15 | Money not multiplied | Seed data (two companies in the fund) | 1. Run A | Commitments 502.0, not 1,004.0 | | |
| ☐ | E16 | Zero commitment | A test fund with committed 0 | 1. Run A | Percentages show N/A | | |
| ☐ | E17 | Company count | Select a third company with no investment in the fund | 1. Run A | Portfolio companies (nos.) = 2 | | |
| ☐ | E18 | Investment after the end date | A company whose only PI is dated 2026-10-05 | 1. Run A | Not counted in totals or count | | |
| ☐ | E19 | Total with no prior value | Both companies with no prior valuation | 1. Run A | Total Change % N/A | | |
| ☐ | E20 | Run after the end date | Add a TVPI run dated 2026-10-15 of 1.5 | 1. Run A | TVPI still 1.2x | | |
| ☐ | E21 | Ratio never run | Seed data (no DPI) | 1. Run A | DPI shows N/A | | |
| ☐ | E22 | Other scenarios | A TVPI exists only in a non-Default scenario | 1. Run A | TVPI shows N/A | | |
| ☐ | E23 | Sale after the end date | Add a sale dated 2026-10-05 | 1. Run B | Realised unchanged (7.0) | | |
| ☐ | E24 | No sales | Company B | 1. Run B for Company B | Realised 0.0 | | |
| ☐ | E25 | No Budget | Remove the Budget KPI | 1. Run B | vs Budget shows N/A | | |
| ☐ | E26 | Zero Budget | Set the Budget to 0 | 1. Run B | vs Budget shows N/A | | |
| ☐ | E27 | Commitment after the date | A commitment of 20 Cr dated 2026-10-10 | 1. Run A for end 2026-09-30 | Commitments raised does not include it (502.0) | | |
| ☐ | E28 | Collection after the date | A verified payment of 5 Cr received 2026-10-05 | 1. Run A for end 2026-09-30 | Capital drawn does not include it (125.5) | | |
| ☐ | E29 | Unverified collection | A payment of 3 Cr received 2026-09-15 on a remittance that is not verified | 1. Run A for end 2026-09-30 | Capital drawn does not include it | | |
| ☐ | E30 | Distribution after the date | A distribution payment dated 2026-10-05 | 1. Ask a developer to read the fund's as-of distribution for 2026-09-30 | Does not include it (no template shows this figure) | | |
| ☐ | E31 | Units premium by issue date | Units issued 2026-09-01 (2 Cr) and 2026-11-01 (1 Cr) | 1. Ask a developer to read the fund's as-of units premium for 2026-09-30 | 2.0 (no template shows this figure) | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Three different dates in one run | Seed data (prior day and FY day differ) | 1. Run A | Generation completes; no error toast or error email | | |
| ☐ | X2 | Dates picked on the form | Seed data | 1. Pick the dates on the options page 2. Run A | Generation completes; the prior-quarter figures are as of 30-Jun | | |
| ☐ | X3 | Already-loaded records refused | Automated only | — | Covered by the automated feature; nothing to check by hand | N/A | N/A |

---

## UI Journeys

N/A — no screen changes. The figures appear only in the generated documents.

---

## Role Sweep

| ID | Screen / action | Fund admin | Investor | Other-entity user |
|---|---|---|---|---|
| R1 | Generate a report that uses the new fields (Bulk generate) | ✓ | ✗ (cannot reach) | ✗ (cannot reach) |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts | None are sent by this change; the completion toast is unchanged | | |
| ☐ | C2 | Dates in the documents | Unchanged format | | |
| ☐ | C3 | Narrow / mobile width | N/A — no screen | | N/A |
| ☐ | C4 | Tenant isolation | A user of another entity cannot generate or see these reports | | |
| ☐ | C5 | Regression on the existing reports | A normal report and a consolidated report using only old fields look as before | | |
| ☐ | C6 | Empty states | A company with no investments still generates a document | | |
| ☐ | C7 | Run time | A run for 10 companies finishes in a similar time to before, not several times longer | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
