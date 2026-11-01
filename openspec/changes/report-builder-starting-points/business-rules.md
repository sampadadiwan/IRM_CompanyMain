# Report Builder starting points — Business rules and worked examples

> **Companion to:** [Design](design.md) · [Proposal](proposal.md) · [Spec](specs/)
> Each row is exactly one Cucumber scenario, tagged `# <ID> — <Happy path|Edge case|Error case>: …`. Feature paths are under `features/core/report_builder/`.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error (exception) case.

## Shared setup

The Phase 1 "Acme" fixture (`features/step_definitions/report_builder_trust_steps.rb`), plus extras named per row.

| Record | Name | Key data |
|---|---|---|
| Entity, users | Acme Capital (Funds and Deals features on); Meera (edit); Omar (Beta Partners) | As Phase 1 |
| Funds | Growth Fund II (INR), Global Fund (USD); Beta Fund (Beta Partners, USD) | Beta Fund only where named |
| Investors | Aditi Rao (LP), Kiran Mehta (LP), Zeta Holdings (Co-Investor), Nova LP (LP) | Nova has no commitments |
| Commitments (crore) | C1 Aditi GF2 5 / called 2 / collected 1.8 (KYC K1) · C2 Kiran GF2 2.5 / 1 / 1 (K2) · C3 Zeta GF2 1 / 0.4 / 0 · C4 Aditi Global 0.1 / 0.04 / 0.04 | As Phase 1 |
| KYCs | K1 Aditi Rao Family Trust (verified), K2 Mehta HUF (not verified) | As Phase 1 |
| Report "LPs" | Investor; Stakeholder, Category; capital commitments filtered to GF2 | As Phase 1 |

## Happy path

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| H1 | One New report | Meera on the Reports page | Look at the page | One **New report** menu with **From a template** and **Guided setup** (and **Describe it**, added by report-builder-assistant); no "New Custom Report" or "Builder Report" | One New report menu | starting_points |
| H2 | Template page | Acme (Funds and Deals on) | New report › From a template | All 10 templates, grouped Investors · Capital calls · Distributions · Fund overview · Portfolio · Compliance | Templates grouped by area | templates |
| H3 | A template card | Template page | Read *LP Capital Account Summary* | Its question, "Starts from Investors", **Needs a fund**, "Includes: 3 formulas · sorted by Unpaid" | Card says what the template answers | templates |
| H4 | Create with a fund | Template page | *LP Capital Account Summary* › Use this › Growth Fund II › Create | New report "LP Capital Account Summary — Growth Fund II": 9 columns + 3 formulas in order; Category is LP; capital commitments limited to GF2; sorted by Unpaid, highest first; builder opens with "Created from LP Capital Account Summary"; report check **All good**; rows Aditi Rao (Unpaid 20,00,000.00, Called % 40.00), Kiran Mehta (0.00, 40.00), Nova LP (0.00, 0.00) | Create from a template with a fund | templates |
| H5 | No fund needed | Template page | *Fund Scorecard* › Use this | Popup has no Fund field; Create makes "Fund Scorecard" with one row per fund, most committed first (Growth Fund II, Global Fund) | Template without a fund | templates |
| H6 | Fund optional, All funds | Template page | *Unverified KYC: Money at Stake* › All funds › Create | No fund filter; KYC Verified is No; rows Mehta HUF (Committed 2,50,00,000.00); report check **All good** (K2's commitments are all INR) | Optional fund | templates |
| H7 | Pivot template | Template page | *Capital Call Collection Tracker* › Growth Fund II › Create | Calls of GF2 only; one pivot column per remittance status present on those calls; report check All good | Template with a pivot | templates |
| H8 | Own name kept | Popup of *LP Capital Account Summary* | Name "Q3 LP accounts", Growth Fund II, Create | Report named exactly "Q3 LP accounts" (no fund added) | Name typed by the user | templates |
| H9 | Duplicate | Report "LPs" with Committed (Sum), a formula Called % at position 3, sort by Committed desc, Excel grouping by Category | Card menu › Duplicate | "Copy of LPs" opens in the builder with "Copied from LPs"; same columns, labels, totals, order (formula position included), related data, filters, formulas, sort and grouping | Duplicate copies the set-up | duplicate |
| H10 | Copy, then change the fund | H9 | In the copy, change the commitments' Fund to Global Fund | Copy shows Aditi's Global Fund commitment only; "LPs" still filtered to GF2 | The original is unchanged | duplicate |
| H11 | One name | Meera | Open a report card menu, Guided setup and the builder | Card menu says **Guided setup** and **Duplicate**; Guided setup pages are titled "Guided setup"; no "Guided Wizard", "Advanced builder" or "Custom report" text | One name everywhere | starting_points |
| H12 | Template check passes | The shipped templates | Run the template check | Every template validates and runs on Acme without error | Templates are checked | templates_check |

## Edge cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E1 | Fund required | Popup of *LP Capital Account Summary* | Create with no fund | "Choose a fund — this template adds up amounts"; no "All funds" choice; no report created | Required fund | templates |
| E2 | Company without Funds | Acme with Funds off, Deals on | Template page | Only *Portfolio KPI Matrix*; posting *LP Capital Account Summary* directly says "That template isn't available" and creates nothing | Templates follow the company's features | templates |
| E3 | Optional fund, two currencies | C4 also on K2 (Global Fund, USD) | *Unverified KYC* › All funds › Create | Created; report check warns "Committed adds amounts in INR and USD — pick a fund or split by fund" | Optional fund warns on mixed currencies | templates |
| E4 | Name already taken | "Copy of LPs" exists | Duplicate "LPs" | New report "Copy of LPs (2)" | Copy name is unique | duplicate |
| E5 | Schedule and undo not copied | "LPs" scheduled weekly to 2 people, a column just removed (Undo pending) | Duplicate | Copy has no schedule and no Undo; "LPs" keeps both | What isn't copied | duplicate |
| E6 | Blank name | Popup of *LP Capital Account Summary* | Clear the name, Growth Fund II, Create | Named "LP Capital Account Summary — Growth Fund II" | Blank name | templates |
| E7 | Templates button gone | Report "LPs" | Open the builder; request the old apply-template address | No Templates button; the old address answers Not found; "LPs" unchanged | Templates never change an existing report | starting_points |
| E8 | Own funds only | Beta Fund exists at Beta Partners | Popup of *LP Capital Account Summary* | Fund list is Global Fund, Growth Fund II | Fund list | templates |
| E9 | Rows that are funds | *Fund Scorecard* (Growth Fund II INR, Global Fund USD) | Open the report check | Note, not a warning: "The totals row adds funds in INR and USD" — each row is one fund, so only the totals row mixes | Fund rows | templates |

## Error cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| X1 | Check names the problem | A template using `capital_commitments.no_such` | Run the template check | Fails with "LP Capital Account Summary: capital_commitments.no_such isn't a column of capital commitments" | Check names template and column | templates_check |
| X2 | Another company's fund | Beta Fund's id | Create *LP Capital Account Summary* with it | Refused with the app's usual Access denied (as for any record of another company); no report created | Fund of another company | templates |
| X3 | Unknown template | — | Create with template "no_such" | "That template isn't available"; no report created | Unknown template | templates |
| X4 | Duplicate another company's report | Omar signed in | Duplicate "LPs" | Refused; no report created | Duplicate across companies | duplicate |
| X5 | Template broken at create time | A template whose column no longer exists (check bypassed) | Create from it | "That template can't be used right now"; no report, no columns left behind | Broken template creates nothing | templates |
