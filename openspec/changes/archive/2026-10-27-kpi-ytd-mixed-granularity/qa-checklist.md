# KPI YTD, Quarter and Year from Mixed Monthly and Quarterly Data — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes.

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
| Environment | Staging, with the build under test |
| Accounts | Fund admin of a test investor entity (India, April fiscal year); a company user of the portfolio company |
| Second entity | A user in a different investor entity |
| Seed data | Portfolio company "Ayati Devices"; KPI mapping Revenue = Cumulate, Cash = Forward fill (Actual); Revenue shown in the report; a portfolio report template that prints the `_vs_budget_percent` fields |
| Background work | After approving, wait for the "cumulative values are computed" notice, then refresh; or use Actions › Recompute Auto-Fill, or ask a developer to run the job. For the YTD change checks, run Recompute Percentage Change on the report |
| Report | Portfolio reports › Generate for Ayati Devices with an end date covering the data, then open the Word file |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Quarter then months | Revenue Q1 (30 Jun 2026) 8,588,635.53; Jul 4,682,642.64; Aug 3,021,951.86 approved | 1. Approve 2. Refresh the KPI grid | Jun YTD 8,588,635.53; Jul YTD 13,271,278.17; Aug YTD 16,293,230.03; Sep Quarter and Sep YTD N/A | | |
| ☐ | H2 | Complete quarter | Jul, Aug, Sep approved | Approve; refresh | Sep Quarter equals the sum; Sep YTD equals Q1 + Jul + Aug + Sep | | |
| ☐ | H3 | Quarters only | Q1 and Q2 uploaded as quarters, no months | Approve; refresh | Jun YTD = Q1; Sep YTD = Q1 + Q2 | | |
| ☐ | H4 | Year from months | All 12 months of one fiscal year approved | Approve; refresh | Year figure equals the sum | | |
| ☐ | H5 | Year from mixed | Q1, Q2 uploaded; Q3, Q4 as months | Approve; refresh | Year equals the sum of four quarters | | |
| ☐ | H6 | Forward fill | Cash Q1 uploaded; Jul balance | Approve; refresh | Jun YTD = Q1 balance; Jul YTD = Jul balance | | |
| ☐ | H7 | Budget future quarter | Budget Jan to Mar of next year | Approve; refresh the Budget view | Budget Quarter shown | | |
| ☐ | H8 | Approval triggers | Revenue figures awaiting approval | Click Approve | Notice about cumulative values being computed; YTD updates after refresh | | |
| ☐ | H9 | YTD change against a year earlier | Jun-25 YTD 7,000,000 and Jun-26 YTD 8,588,636 approved (Actual) | Recompute Percentage Change; read the Jun-26 YTD cell | Change shows 22.69 % (not a figure against May-26) | | |
| ☐ | H10 | YTD Actual against YTD Budget | Jun-26 YTD Actual 92, YTD Budget 100 approved | Generate the report; open the Word file | The Jun-26 YTD "against Budget" field shows 92 | | |
| ☐ | H11 | Quarter Actual against Quarter Budget | Jun-26 Quarter Actual 45, Quarter Budget 60 approved | Generate the report | The Jun-26 Quarter field shows 75 | | |
| ☐ | H12 | Existing report fields unchanged for approved figures | A report template that does not use the new fields; all KPIs approved | Generate the report | Same output as before this change | | |
| ☐ | H13 | Stake and first investment date across funds | The company has buys in two funds: 15 Mar 2024 (stake 8), 10 Jan 2025 (stake 10), 1 Sep 2025 (stake 12.5) | Generate the report with a template that shows the latest investment's stake and the earliest investment's date | Stake 12.5; date 15 Mar 2024 | | |
| ☐ | H14 | IRR and MOIC in each fund | Fund ratios run for the company in two funds | Generate the report with a template that shows each fund's irr and moic | Each fund shows its own IRR (XIRR) and MOIC, matching the Ratios tab | | |
| ☐ | H15 | Row data type | A KPI whose mapping has data type percentage | Generate the report with a template that tests the data type | The template sees "percentage" for that row (value as a fraction, 0.12 for 12%) | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Incomplete quarter | Jul, Aug approved only | Approve; refresh | No Sep Quarter | | |
| ☐ | E2 | Gap stops YTD | Q1, Jul, Sep approved; Aug missing | Approve; refresh | Jun, Jul YTD only; no Aug or Sep YTD | | |
| ☐ | E3 | No double count | Q1 100, Jul 10, uploaded Q2 40 | Approve; refresh | Jul YTD 110; Sep YTD 140 | | |
| ☐ | E4 | Months win | Q1 100; Jul+Aug+Sep total 45; uploaded Q2 40 | Approve; refresh | Sep YTD 145; Q2 column still 40 | | |
| ☐ | E5 | Uploaded authoritative | Uploaded Q2 40; months total 45 | Recompute | Q2 stays 40 | | |
| ☐ | E6 | Fiscal year independence | Gap in one year, full next year | Recompute | Next year's YTD starts from its own first period | | |
| ☐ | E7 | Three quarters | Q1 to Q3 only | Recompute | No Year figure | | |
| ☐ | E8 | Forward fill incomplete | Cash Jul, Aug | Recompute | No Quarter; YTD equals each month's balance | | |
| ☐ | E9 | Actual future | Actual months of a future quarter | Recompute | No Quarter | | |
| ☐ | E10 | Company override | Set the company's fiscal start to January | Recompute | Quarters are Jan to Mar etc. | | |
| ☐ | E11 | India default | No overrides | Recompute | Q1 is Apr to Jun | | |
| ☐ | E12 | Month un-approved | Calculated Q2 exists | Un-approve Aug; Recompute | Q2 and dependent YTD disappear | | |
| ☐ | E13 | Legacy partial quarter | An old Sep Quarter figure built from 2 months | Recompute | The Sep Quarter figure is removed | | |
| ☐ | E14 | Uploaded survives | An uploaded Quarter where none would be calculated | Recompute | Uploaded figure still there | | |
| ☐ | E15 | No YTD a year earlier | Jun-26 and Jul-26 YTD; no Jul-25 YTD | Recompute Percentage Change | Jul-26 YTD change shows "-"; it is not against Jun-26 | | |
| ☐ | E16 | Year-earlier figure removed | A calculated YTD a year earlier that the cleanup then removes | Recompute; Recompute Percentage Change | The later YTD change becomes "-" | | |
| ☐ | E17 | Year-earlier YTD is zero | Jun-25 YTD is 0 | Recompute Percentage Change | Jun-26 YTD change shows "-" | | |
| ☐ | E18 | Month-end differs (leap year) | 29 Feb 2024 and 28 Feb 2025 YTD figures | Recompute Percentage Change | The Feb-25 change is against Feb-24 | | |
| ☐ | E19 | Tags separate | Actual and Budget YTD for two years | Recompute Percentage Change | Each tag's change is against its own tag a year earlier | | |
| ☐ | E20 | Other periods unchanged | Consecutive Month, Quarter and Year figures | Recompute Percentage Change | Each against the previous figure of its own period | | |
| ☐ | E21 | Budget missing | An Actual column with no Budget figure | Generate the report | The field shows N/A | | |
| ☐ | E22 | Budget approved later | Report generated first without Budget | Approve Budget; generate again | The field now shows the ratio | | |
| ☐ | E23 | Budget zero | Budget value 0 | Generate the report | The field shows N/A | | |
| ☐ | E24 | Different period not compared | A Month Actual and only a Quarter Budget at the same date | Generate the report | The Month field shows N/A | | |
| ☐ | E25 | Only Actual columns | A Budget and an IC column | Generate the report | Neither has an "against Budget" field | | |
| ☐ | E26 | Recompute corrects old values | A YTD cell still shows the old change against the previous month | Recompute Percentage Change | It now shows the year-over-year change | | |
| ☐ | E27 | Change too large to store | Year-earlier YTD 1; current YTD 1,000,000 | Recompute Percentage Change | That YTD change shows "-"; other YTD cells still update | | |
| ☐ | E28 | Unapproved figure | Budget (or Actual) figure left unapproved | Generate the report | The field shows N/A | | |
| ☐ | E29 | Report shows approved KPIs only | A Revenue figure left unapproved in a report column | Generate the report | That column shows N/A (value and change); the KPI grid on screen still shows the figure | | |
| ☐ | E30 | Uploaded figure over a calculated one | A calculated Sep Quarter exists | Upload a Sep Quarter figure, approve it, then use Recompute Auto-Fill | The uploaded value stays and the figure is not removed; its source reads "upload" on the KPI page | | |
| ☐ | E31 | Empty change with thresholds | A mapping with a lower threshold; a YTD figure with no YTD a year earlier | Open the KPI grid | The YTD cell shows "-" with no colour; no error page | | |
| ☐ | E32 | Recompute Auto-Fill refreshes YTD changes | A YTD figure whose change is out of date | Use Actions › Recompute Auto-Fill; wait for the notice; refresh | The YTD change is the year-over-year one without pressing Recompute Percentages | | |
| ☐ | E33 | Owners separate | YTD figures from two owners for the same KPI (the app does not allow two figures of one KPI in a report, so this is covered by the automated scenario only: mark N/A) | Recompute Percentage Change | Each owner's change is against that owner's own figure a year earlier | | |
| ☐ | E34 | Two runs at once | Two files for one company ready to approve | Approve both within a few seconds; wait; refresh | The YTD figures match all the approved data; none is missing or removed | | |
| ☐ | E35 | Entity setting | The entity's fiscal start set to January; the company has no override | Recompute | Quarters are Jan to Mar etc. (the old cumulation ignored this setting) | | |
| ☐ | E36 | Forward fill gap | Cash balances for Apr, May, Jun, Aug, Sep; July missing | Recompute | Each of those months' YTD equals its own balance; Q1 Quarter = June balance; no Q2 Quarter | | |
| ☐ | E37 | Status judged against a removed figure | A calculated Budget YTD that an Actual YTD is judged against (RAG set on the mapping) | Un-approve a Budget month so the Budget YTD is removed; Recompute | The Actual YTD's red/amber/green status is re-evaluated | | |
| ☐ | E38 | Quarter figure bridges a missing month | Q1, Q2 and Q3 (31 Dec) uploaded as quarters; October and December approved; November missing | Recompute | October YTD = Q1 + Q2 + October; no November YTD; December YTD = Q1 + Q2 + Q3 | | |
| ☐ | E39 | Later quarter balance, no month | Cash Q1 balance 40 and Q2 balance 50 uploaded as quarters; no months | Recompute | June YTD = 40; September YTD = 50, not 90 | | |
| ☐ | E40 | Tag case ignored | The Budget report is tagged "budget" in lower case | Generate the report | The Actual column still shows the ratio against it | | |
| ☐ | E41 | Ratio not run | A fund where the company's ratios were never run | Generate the report | That fund's irr and moic show N/A | | |
| ☐ | E42 | Ratio as of the end date | The company's IRR stored for 31 Dec 2025, 30 Jun 2026 and 30 Sep 2026 | Generate the report ending 30 Jun 2026 | The 30 Jun 2026 IRR | | |
| ☐ | E43 | Other scenarios ignored | A Bull Case run exists for the same date | Generate the report | The Default-scenario figure | | |
| ☐ | E44 | A later sale | The company's last transaction before the end date is a sale | Generate the report | The latest investment is that sale (its stake is blank); the first investment date is still the first buy's | | |
| ☐ | E45 | Investments after the end date | A buy dated after the report's end date | Generate the report | It is not used | | |
| ☐ | E46 | No investment | A company with no buy yet | Generate the report | Stake and date are blank; the report is generated | | |
| ☐ | E47 | Stake not recorded | The latest investment has no stake | Generate the report | Stake blank; the first investment date is still shown | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | A calculated row cannot be saved | Ask a developer to make a save fail (e.g. remove the KPI mapping) | Recompute | Error toast and email list the period; other rows still update | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | KPIs › grid | Open the grid for Ayati Devices | Jun Quarter, Jul and Aug Month and YTD columns, Sep Quarter column | | |
| ☐ | J1.2 | KPIs › grid | Read the Revenue row | Values as in H1; N/A where nothing qualifies | | |
| ☐ | J1.3 | KPIs › Upload | Upload September, approve | Sep Quarter and Sep YTD appear | | |
| ☐ | J1.4 | KPIs › grid | Read the change figure next to a YTD value | Year-over-year change; "-" when nothing a year earlier; colours follow the mapping thresholds | | |
| ☐ | J1.5 | Portfolio reports › Generate | Generate the report and open the Word file | "Against Budget" fields filled or N/A as in H10, H11, E21 | | |

---

## Role Sweep

| ID | Screen / action | Fund admin | Company user | Investor | Other-entity user |
|---|---|---|---|---|---|
| R1 | View the KPI grid | ✓ | ✓ (own company) | per existing access | ✗ |
| R2 | Approve and Recompute | ✓ | ✗ | ✗ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails and alerts from cumulation errors | Correct recipient and links | | |
| ☐ | C2 | Dates on the grid | Follow the user's locale format | | |
| ☐ | C3 | Narrow or mobile width | No horizontal page scroll beyond the grid's own | | |
| ☐ | C4 | Tenant isolation | A second entity's user cannot see Ayati's figures | | |
| ☐ | C5 | Regression: KPI grid, KPI upload, approval | Work as before | | |
| ☐ | C6 | Report generation time for a company with many KPI mappings | Not slower than before this change | | |
| ☐ | C7 | Regression: report fields `<label>` and `<label>_percent` | Same values as before, except the YTD `_percent` which is now year over year | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
