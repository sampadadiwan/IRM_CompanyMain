# Portfolio Report Quarter Activity and KPI Change Direction — Manual QA Checklist

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
| Environment | Staging, with a test company template uploaded (see below) |
| Accounts | One fund admin (company admin) of the test entity; a user of a second entity for the isolation check |
| Test company template | A copy of the company template where, inside each fund's block, the sentence "The fund invested a further [currency] [cost_of_investment_between] Cr during the quarter" is shown only when `buy_pis_present` is true, and "The fund sold [currency] [cost_of_sold_between] Cr of investments (at cost) during the quarter" only when `sell_pis_present` is true |
| Seed data: investments | Fund "Inflexor Technology Discovery Fund 1" (INR). Company A: bought 4,000 shares for 40 Cr on 10-Feb-2026, 500 for 10 Cr on 15-Aug-2026, sold 500 for 7 Cr (cost 5 Cr) on 10-Sep-2026. Company B: bought 1,000 shares for 30 Cr on 20-Jan-2026 |
| Seed data: consolidated | An INR fund with a company holding 10 units at 100 on 30-Jun-2026, 5 more bought in the quarter and 110 on 30-Sep-2026; a second instrument and a second company for H21 and H22; Run B: Portfolio reports › Bulk generate, consolidated, 1-Jul to 30-Sep-2026 |
| Seed data: KPIs | A company with approved monthly KPI figures, Revenue 100 then 120 (positive); EBITDA -100 then -80 (loss shrinks) and -100 then -125 (loss grows); a percentage KPI "EBITDA %" -0.632 then -0.557; a Revenue Actual 92 against Budget 100; the KPI mapping of EBITDA has lower threshold 10 |
| Run A | Portfolio company › generate the company report, test template, 1-Jul-2026 to 30-Sep-2026 |
| Recompute | KPI report › Recompute percentage change, for the test company, after the code is deployed |
| Background work | Generation and the recompute run in the background; wait for the toast |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Purchase in the quarter | Run A done | 1. Read Company A's fund block | "The fund invested a further INR 10.0 Cr during the quarter" | | |
| ☐ | H2 | Several purchases | Add a 4 Cr buy on 20-Sep-2026, Run A again | 1. Read Company A's block | 14.0 Cr | | |
| ☐ | H3 | Sale in the quarter | Run A done | 1. Read Company A's block | "The fund sold INR 5.0 Cr of investments (at cost) during the quarter" (not 7.0) | | |
| ☐ | H4 | Buy and sale together | Run A done | 1. Read Company A's block | Both sentences | | |
| ☐ | H5 | Each fund has its own | Company A also bought 3 Cr in a second fund on 1-Sep | 1. Read both fund blocks | Inflexor 10.0 Cr; second fund 3.0 Cr | | |
| ☐ | H6 | Existing fund data unchanged | A report from before the change | 1. Compare cost of investment, cost of remaining, sold amount, IRR and MOIC | Same as before | | |
| ☐ | H7 | Positive prior unchanged | Recompute done | 1. Read the Revenue 100 → 120 change | +20 | | |
| ☐ | H8 | Loss shrinks | Recompute done | 1. Read EBITDA -100 → -80 | +20 | | |
| ☐ | H9 | Loss grows | Recompute done | 1. Read EBITDA -100 → -125 | -25 | | |
| ☐ | H10 | Negative to positive | An EBITDA of -50 then 25 | 1. Read the change | +150 | | |
| ☐ | H11 | Positive to negative | An EBITDA of 50 then -25 | 1. Read the change | -150 | | |
| ☐ | H12 | YTD against a negative year earlier | YTD -3.154 (Jun 2025), -3.8 (Jun 2026) | 1. Read the Jun 2026 YTD change | -20.48 | | |
| ☐ | H13 | Percentage KPI margin improves | EBITDA % -0.632 then -0.557 | 1. Read the change | +11.87, never a negative number | | |
| ☐ | H14 | Recompute corrects | A figure with the old sign stored | 1. Run the recompute. 2. Read the change | The corrected sign | | |
| ☐ | H15 | Budget difference, smaller loss | Actual -80, Budget -100, Run A with the Actual in the template | 1. Read the difference field | +20 | | |
| ☐ | H16 | Budget difference, larger loss | Actual -125, Budget -100 | 1. Read it | -25 | | |
| ☐ | H17 | Fair market value change, negative base | Needs a fund with a negative valuation; if not available, mark N/A and rely on the automated test | 1. Generate the consolidated report | Follows the movement | | |
| ☐ | H18 | Percentage KPI against budget | EBITDA % Actual 0.15, Budget 0.20 | 1. Read the difference field | -25 | | |
| ☐ | H19 | Price rises and units are bought | A fund with 10 units at 100 on 30-Jun, 5 bought in the quarter, 110 on 30-Sep. Run B (consolidated) | 1. Read the company's fund line | `fmv_change_percent` 10, `fmv_prior` 1,000, `fmv` 1,650 | | |
| ☐ | H20 | Price rises and units are sold | 10 units, 4 sold in the quarter, 110 on 30-Sep | 1. Read the line | 10 | | |
| ☐ | H21 | Several instruments weighted | A 10 units 100→110; B 30 units 100→80 | 1. Read the line | -12.5 | | |
| ☐ | H22 | Fund total from the sums | Two companies as in H21 | 1. Read the lines and the fund total | Lines 10 and -20; total -12.5 | | |
| ☐ | H23 | Financial year start | 8 units at 90 before the financial year, 100 on 30-Jun, 108 on 30-Sep | 1. Read the line | FY change 20; quarter change 8 | | |
| ☐ | H24 | Amounts unchanged | H19 and H20 data | 1. Compare `fmv`, `fmv_prior`, `fmv_fy_start` with the report before the change | The same amounts | | |
| ☐ | H25 | Performance table, loss grows | The test company's EBITDA -100 then -125 | 1. Open KPI report › Performance as of the later month. 2. Read the month's growth | -25%, red | | |
| ☐ | H26 | Performance table, loss shrinks | EBITDA -100 then -80 | 1. Read the month's growth | +20%, green | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | No trades in the quarter | Company B | 1. Read Company B's block | No sentences | | |
| ☐ | E2 | Only earlier trades | Report 11-Sep to 30-Sep for Company A | 1. Read the block | No sentences | | |
| ☐ | E3 | Buy on the start date | Report 15-Aug to 30-Sep | 1. Read the block | The 15-Aug buy is counted | | |
| ☐ | E4 | Buy on the end date | Report 1-Jul to 15-Aug | 1. Read the block | The 15-Aug buy is counted | | |
| ☐ | E5 | Day before the start | Report 16-Aug to 30-Sep | 1. Read the block | The buy is not counted | | |
| ☐ | E6 | Day after the end | Report 1-Jul to 14-Aug | 1. Read the block | Neither the buy nor the sale | | |
| ☐ | E7 | Sale only | Report 1-Sep to 30-Sep | 1. Read the block | Only the sale sentence, 5.0 Cr | | |
| ☐ | E8 | Sale on the end date | Report 1-Jul to 10-Sep | 1. Read the block | The 10-Sep sale is counted | | |
| ☐ | E9 | Another company's buy | Company B bought 3 Cr on 1-Sep | 1. Read Company A's block | Still 10.0 Cr | | |
| ☐ | E10 | Exited before the quarter | A company that sold everything before 1-Jul | 1. Read its block | Block present, no sentences | | |
| ☐ | E11 | Equal negative figures | -100 then -100 | 1. Read the change | 0 | | |
| ☐ | E12 | Prior zero | 0 then -5 | 1. Read the change | "-" | | |
| ☐ | E13 | Quarter series | Quarter figures -100 then -80 | 1. Read the change | +20 | | |
| ☐ | E14 | Too large to store | -0.01 then 100 | 1. Read the change | "-" | | |
| ☐ | E15 | Growing loss is red | EBITDA -100 → -125, lower threshold 10 | 1. Open the KPI grid | The change shows in red | | |
| ☐ | E16 | Not recomputed yet | A change stored before the deploy, recompute not run | 1. Open the grid | The old stored value | | |
| ☐ | E17 | Ratio unchanged | Actual -80, Budget -100 | 1. Read "vs budget" | 80 | | |
| ☐ | E18 | Positive budget | Actual 92, Budget 100 | 1. Read the difference | -8 | | |
| ☐ | E19 | Comparator missing or zero | No Budget, or Budget 0 | 1. Read the difference | "N/A" | | |
| ☐ | E20 | FMV positive base | A normal fund | 1. Read the fair market value change | Same as before | | |
| ☐ | E21 | FMV base zero | A fund with no value at the start | 1. Read it | "N/A" | | |
| ☐ | E22 | Percentage KPI against zero | EBITDA % 0 then 0.05 | 1. Read the change | Empty | | |
| ☐ | E23 | Percentage KPI falls | EBITDA % 0.20 then 0.15 | 1. Read the change | -25 | | |
| ☐ | E24 | Same figures on a numeric KPI | A numeric KPI -0.632 then -0.557 | 1. Read the change | +11.87 (relative) | | |
| ☐ | E25 | Price unchanged | 10 units at 100, still 100 | 1. Read the line | 0 | | |
| ☐ | E26 | Price falls | 10 units, 100 → 90 | 1. Read the line | -10 | | |
| ☐ | E27 | Holding sold entirely in the period | 10 units at 100, all sold, 110 | 1. Read the line | 10, not -100 | | |
| ☐ | E28 | Older valuation used | Only valuation before the start dated 20-Jun | 1. Read the line | That valuation is the value per unit at the start | | |
| ☐ | E29 | Fund currency | A USD instrument in an INR fund, flat USD value, rate up 5% | 1. Read the line | 5 | | |
| ☐ | E30 | Purchase price before any valuation | 10 units bought at 100 each before the start, no valuation until 110 at the end | 1. Read the line | +10; `fmv_prior` 1,000 | | |
| ☐ | E31 | Nothing held at the start | Only buy dated in the quarter | 1. Read the line | "N/A" | | |
| ☐ | E32 | New instrument beside an old one | A held since before (+10%), B bought in the quarter | 1. Read the line | 10 | | |
| ☐ | E33 | Percentage KPI year over year | EBITDA % YTD Jun 2025 -0.632, Jun 2026 -0.557 | 1. Read the Jun 2026 YTD change | +11.87 | | |
| ☐ | E34 | Performance table, positive earlier figure | Revenue 100 then 120 | 1. Read the month's growth | +20%, as before | | |
| ☐ | E35 | Performance table, earlier figure zero | An EBITDA of 0 then -5 | 1. Read the month's growth | Blank | | |
| ☐ | E36 | Performance table, YTD against a negative year earlier | June 2025 -3.154, June 2026 -3.8 | 1. Read the YTD growth against a year earlier | -20.48% | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Dates arrive as text | Generate from Portfolio company › Generate report as usual | 1. Generate a company report | The report generates and the quarter sentences are right (the job hands over text dates) | | |

---

## UI Journeys

| ☐ | ID | Step | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | J1 | KPI report › Recompute percentage change | "Computation started", then the changes update | | |
| ☐ | J2 | KPI grid, KPI page and KPI list for EBITDA | All three show the same corrected change with the same colour | | |

---

## Role Sweep

| ID | Screen / action | Fund admin | Employee | Investor | Other-entity user |
|---|---|---|---|---|---|
| R1 | Generate the company report and recompute the changes (unchanged by this change) | ✓ | As today | ✗ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts | None added; the recompute shows its usual toasts to the user who starts it | | |
| ☐ | C2 | Dates on changed screens | N/A — no screen dates change | | |
| ☐ | C3 | Narrow / mobile width | The KPI grid still reads at narrow width with the corrected sign | | |
| ☐ | C4 | Tenant isolation | A user of the second entity cannot generate these reports or recompute the test company | | |
| ☐ | C5 | Regression: templates that do not use the new fields | The standard company and consolidated templates render as before, except corrected changes | | |
| ☐ | C6 | Empty states | A company with no investment in a fund has no fund block; a KPI with no comparison figure shows "-" | | |
| ☐ | C7 | AI portfolio assistant | After the recompute, the assistant quotes the corrected change | | |
| ☐ | C8 | Thresholds on a percentage KPI | EBITDA % with an upper threshold of 5: a change of +11.87 shows green | | |
| ☐ | C9 | Fair market value amounts roll forward | Cost, fmv_prior and fmv still foot with the previous report for the same dates | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
