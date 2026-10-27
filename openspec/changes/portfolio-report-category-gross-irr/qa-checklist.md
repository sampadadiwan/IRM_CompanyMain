# Portfolio Report Category and Gross Portfolio IRR — Manual QA Checklist

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
| Environment | Staging, with a test company template and a test consolidated template uploaded (see below) |
| Accounts | One fund admin (company admin) of the test entity |
| Second entity | A user of a different entity, for the isolation check |
| Test company template | A copy of the company report template where, inside the KPI loop (`kpis:each(kpi)`), each row also has a mail merge field `=kpi.category` next to `=kpi.header` |
| Test consolidated template | A copy of the consolidated template with a fund totals loop (`fund_totals:each(total)` ... `fund_totals:endEach`) holding mail merge fields `=total.irr` and `=total.gross_portfolio_irr`. For H7 also keep the company loop (`portfolio_companies:each(company)`) with the fund loop inside it (`company.funds:each(fund)`, `=fund.irr`) |
| Seed data | Portfolio company "MyFavStartup" with KPI mappings shown in the report: Revenue (category "Financial", money), Churn (category "Customer Metrics", percentage), Headcount (no category). Fund "Inflexor Technology Discovery Fund 1" with two companies invested. Fund ratios: Gross Portfolio IRR 16.0 on 30-Jun-2026 and 18.0 on 30-Sep-2026; XIRR 14.2 on 30-Sep-2026. A second fund with Gross Portfolio IRR 11.5 on 30-Sep-2026 and a third fund with no Gross Portfolio IRR run |
| Run A | Portfolio company › generate the company report with the test company template, end date 30-Sep-2026 |
| Run B | Portfolio reports › Bulk generate, consolidated report with the test consolidated template, start 1-Jul-2026, end 30-Sep-2026 |
| Background work | Generation runs in the background; wait for the "completed" toast |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Row shows its category | Run A done | 1. Open the company report. 2. Find the Revenue row | Category is "Financial" | | |
| ☐ | H2 | Same category in the category's own list | Template also prints the Financial list | 1. Find Revenue in the all-KPIs table. 2. Find Revenue in the Financial table | Both show "Financial" | | |
| ☐ | H3 | Existing row fields unchanged | A report from before the change for the same dates | 1. Compare the Churn row with the earlier report | Data type "percentage" and all period values are the same | | |
| ☐ | H4 | Latest Gross Portfolio IRR on or before the end date | Run B done | 1. Open the consolidated report. 2. Read the Inflexor fund total | Gross Portfolio IRR is 18.0 | | |
| ☐ | H5 | Shown beside the fund's IRR | Run B done | 1. Read the Inflexor fund total | IRR 14.2 and Gross Portfolio IRR 18.0 | | |
| ☐ | H6 | Each fund has its own value | Run B done, second fund present | 1. Read the second fund's total | Gross Portfolio IRR is 11.5, not 18.0 | | |
| ☐ | H7 | Company fund line keeps the company's IRR | Template prints the company fund lines | 1. Read a company's line in the Inflexor fund | IRR is the company's own, and no Gross Portfolio IRR appears on the line | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Category keeps its case | Run A done | 1. Find the Churn row | Category is "Customer Metrics" exactly | | |
| ☐ | E2 | Mapping without a category | Run A done | 1. Find the Headcount row | Category is blank and the report generated | | |
| ☐ | E3 | Run after the end date ignored | A Gross Portfolio IRR run of 19.5 dated 15-Oct-2026 | 1. Run B again with end date 30-Sep-2026 | Still 18.0 | | |
| ☐ | E4 | Run in another scenario ignored | The only run on or before the end date is in a scenario other than Default | 1. Run B | "N/A" | | |
| ☐ | E5 | No run | The third fund, no run | 1. Read the third fund's total | "N/A" and the report generated | | |
| ☐ | E6 | Run exactly on the end date | A run dated 30-Sep-2026 | 1. Run B with end date 30-Sep-2026 | That run's value is shown | | |
| ☐ | E7 | Two runs on the same date | Two runs dated 30-Sep-2026 (17.0 first, 18.0 second) | 1. Run B | 18.0, the later one | | |
| ☐ | E8 | Zero is a value | A run of 0.0 dated 30-Sep-2026 | 1. Run B | 0.0, not "N/A" | | |
| ☐ | E9 | Negative return | A run of -3.2 dated 30-Sep-2026 | 1. Run B | -3.2 | | |
| ☐ | E10 | Labelled run not matched | The fund has only a run named "Gross Portfolio IRR (USD)" | 1. Run B | "N/A" | | |
| ☐ | E11 | Two companies in one fund | Both companies invested in the Inflexor fund | 1. Read the Inflexor total | One value, 18.0, not 36.0 | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X0 | None defined | Neither field can fail the build; a missing value is "N/A" (E4, E5, E10) or blank (E2) | n/a | n/a | | |

---

## UI Journeys

N/A — no screen changes. The only output is the generated document, checked in the Happy Path and Edge Cases.

---

## Role Sweep

| ID | Screen / action | Fund admin | Employee | Investor | Other-entity user |
|---|---|---|---|---|---|
| R1 | Generate the company and consolidated reports (unchanged by this change) | ✓ | As today | ✗ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts | N/A — none sent or changed | | |
| ☐ | C2 | Dates on changed screens | N/A — no screen dates change | | |
| ☐ | C3 | Narrow / mobile width | N/A — no screen changes | | |
| ☐ | C4 | Tenant isolation | A user of the second entity cannot generate or see these reports, and the report for the test entity shows no other entity's Gross Portfolio IRR | | |
| ☐ | C5 | Regression: templates that do not use the new fields | The standard company and consolidated templates render exactly as before | | |
| ☐ | C6 | Empty states | A fund with no Gross Portfolio IRR shows "N/A"; a mapping with no category shows blank | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
