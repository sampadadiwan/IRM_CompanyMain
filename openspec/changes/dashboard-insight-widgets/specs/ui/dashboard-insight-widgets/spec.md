# Spec Delta

## Purpose

Seventeen read-only dashboard widgets. Each answers one recurring question for fund-manager staff: what changed, what is stale, what is overdue, what is stuck. They are spread across the Portfolio Company, Portfolio, Aggregated Portfolio, Fund, Investor, Ops and FM Landing dashboards. None of them is ever shown to LPs.

## ADDED Requirements

### Requirement: New widgets are offered on their dashboards
The widget-type list on the New Widget form SHALL offer each new widget on the dashboards below and on no others:
- Portfolio Company Dashboard: KPI Movers, KPI Threshold Watch, Monitoring Status, Investment Timeline, Ownership Trend.
- Portfolio Dashboard: Valuation Freshness, Winners & Losers, Sector Exposure.
- Aggregated Portfolio Dashboard: Valuation Freshness, Peer KPI Comparison.
- Fund Dashboard: Remittance Ageing, NAV per Unit Trend, Hedge Expiries.
- Investor Dashboard: Investor Pending Actions, Side-letter Obligations.
- Ops Dashboard: Needs Attention, Overdue Tasks by Assignee, Stuck Workflows, Side-letter Obligations.
- FM Landing Page: Needs Attention.

#### Scenario: New widgets are offered on their dashboards
- **WHEN** a fund manager opens the New Widget form and picks a dashboard
- **THEN** the widget-type list includes exactly that dashboard's new widgets from the list above

### Requirement: Every setting is labelled and explained
Each setting of a new widget SHALL show a human label and a one-line help text on the widget's setup form.

#### Scenario: Every setting is labelled and explained
- **WHEN** a fund manager opens the edit page of a new widget that has settings
- **THEN** each setting shows its label and its help text

### Requirement: Invalid settings fall back to defaults
A setting that is missing, zero or below zero, or not a number where a number is expected SHALL be replaced by that setting's default when the widget renders. The page SHALL NOT error.

#### Scenario: Invalid settings fall back to defaults
- **WHEN** a widget is saved with `top_n: 0` or `current_days: 'abc'`
- **THEN** the widget renders using the default for that setting

### Requirement: New widgets are never shown to LPs
None of the new widgets SHALL be placeable in an LP layout. None of them SHALL render its content for a user acting in the investor role, whichever dashboard URL that user requests.

#### Scenario: New widgets are never shown to LPs
- **WHEN** a fund manager adds a new widget to an LP layout, or an investor-role user opens a dashboard holding a new widget
- **THEN** the LP layout save is refused with the LP-safety message, and the widget body is not rendered for the investor-role user

### Requirement: Counts respect the viewer's access
Every count, list and total in a new widget SHALL include only records of the viewer's firm that the viewer is allowed to open on the matching index screen.

#### Scenario: Counts respect the viewer's access
- **WHEN** another firm or an inaccessible fund has matching records
- **THEN** those records are not counted, listed or totalled

### Requirement: Empty widgets explain why
When a new widget has nothing to show, it SHALL show one sentence saying why, instead of an empty chart or table.

#### Scenario: Empty widgets explain why
- **WHEN** a widget's query returns no rows
- **THEN** the widget shows its empty-state sentence

### Requirement: KPI widgets need the KPI module
KPI Movers, KPI Threshold Watch and Peer KPI Comparison SHALL render only when the viewer can open KPI reports.

#### Scenario: KPI widgets need the KPI module
- **WHEN** the firm does not have the KPI module
- **THEN** these widgets are not rendered

### Requirement: KPI Movers lists the biggest changes
KPI Movers SHALL list the KPIs of the company's latest KPI report that has the configured period (default Quarter) and tag (default Actual). It SHALL include only KPIs with a stored change, ordered by size of change, largest first, ties by KPI name. It SHALL show at most `top_n` rows (default 5), each with the KPI's value, its change coloured against the KPI mapping's thresholds, and the report date.

#### Scenario: KPI Movers lists the biggest changes
- **WHEN** the latest Actual Quarter report has changes Revenue +12.50, EBITDA −30.00, Churn +8.00, Headcount +2.00
- **THEN** the rows are EBITDA, Revenue, Churn, Headcount

### Requirement: KPI Threshold Watch flags KPIs outside their limits
KPI Threshold Watch SHALL list the KPIs of the same latest report that meet any of these conditions:
- Their RAG status is red or amber.
- Their change is below the mapping's lower threshold.
- Their change is above the mapping's upper threshold.

A threshold SHALL count only when it is above zero, and a change equal to a threshold SHALL NOT be a breach. Rows SHALL be ordered red, amber, below threshold, above threshold.

#### Scenario: KPI Threshold Watch flags KPIs outside their limits
- **WHEN** EBITDA is RAG red, Revenue's change 5.00 is below its lower threshold 10, and Churn's change 30.00 is above its upper threshold 25
- **THEN** the rows are EBITDA "Red", Revenue "Below 10 % threshold", Churn "Above 25 % threshold"

### Requirement: Monitoring Status shows the agent's latest check
Monitoring Status SHALL show the latest portfolio company agent report for the company: KPI, document and valuation results, plus the date it was checked. It SHALL render nothing when the firm has no portfolio company agent, or when the viewer may not see that agent.

#### Scenario: Monitoring Status shows the agent's latest check
- **WHEN** the latest report says Q2 KPIs are missing and the valuation is current
- **THEN** the KPI card shows one issue and the Valuations card shows compliant

### Requirement: Investment Timeline shows buys and sells per period
Investment Timeline SHALL show, for each quarter (or year, by setting), the amounts the firm's funds bought and sold in the company. Amounts SHALL be in the firm's currency, sells shown as negative, and only funds the viewer can access counted.

#### Scenario: Investment Timeline shows buys and sells per period
- **WHEN** a fund bought ₹1,00,00,000 in Q1 2025 and sold ₹30,00,000 in Q3 2026
- **THEN** the chart shows Q1 2025 Bought 1,00,00,000 and Q3 2026 Sold −30,00,000

### Requirement: Ownership Trend shows fully diluted % over time
Ownership Trend SHALL plot, per holder group, the total fully diluted percentage of the company's cap-table positions on each position date. Positions without a date or a percentage SHALL be skipped.

#### Scenario: Ownership Trend shows fully diluted % over time
- **WHEN** Self holds 12.00 % on 31 Mar 2025 and 10.50 % on 30 Sep 2025
- **THEN** the Self line shows those two points

### Requirement: Valuation Freshness shows how old each holding's valuation is
On the Portfolio Dashboard, Valuation Freshness SHALL list the companies the fund still holds. On the Aggregated Portfolio Dashboard it SHALL list the companies on that page. Each row SHALL show the company's last valuation date, the days since, and a status:
- **Current** if 0 to `current_days` days (default 90). A future date counts as Current.
- **Due** if up to `due_days` days (default 180).
- **Stale** if older than that.
- **Never** if the company has no valuation.

The widget SHALL show the count per status above the rows. It SHALL list the stalest first, with at most `limit` rows (default 15), and say how many of the total are shown.

#### Scenario: Valuation Freshness shows how old each holding's valuation is
- **WHEN** today is 30 Sep 2026 and the last valuations are 92 days ago, 273 days ago and none
- **THEN** the rows are Never, Stale 273, Due 92, and the counts are Current 0, Due 1, Stale 1, Never 1

### Requirement: Winners & Losers ranks unrealised gains and losses
Winners & Losers SHALL total each company's unrealised gain across the fund's holdings. It SHALL then list the `top_n` largest gains (default 5) and the `top_n` largest losses, in the fund's currency. Zero totals SHALL be left out.

#### Scenario: Winners & Losers ranks unrealised gains and losses
- **WHEN** unrealised gains are Zeta +40 L, Kite +5 L and Orbit −15 L
- **THEN** gains list Zeta then Kite and losses list Orbit

### Requirement: Sector Exposure splits FMV by sector
Sector Exposure SHALL split the fund's current FMV (or cost of remaining holdings, by setting) by the portfolio company's sector, as amounts and percentages. A blank sector SHALL be shown as "Unassigned".

#### Scenario: Sector Exposure splits FMV by sector
- **WHEN** FMV is ₹6 Cr Consumer, ₹3 Cr Fintech and ₹1 Cr with no sector
- **THEN** the split is Consumer 60.00 %, Fintech 30.00 %, Unassigned 10.00 %

### Requirement: Peer KPI Comparison compares one KPI across companies
Peer KPI Comparison SHALL show, for each company on the Aggregated Portfolio Dashboard, the value and change of the configured KPI from that company's latest report with the configured period and tag. The KPI matches by its reported name or its mapped standard name, ignoring case. Companies without the KPI SHALL be left out. A blank KPI name SHALL show a prompt to set it.

#### Scenario: Peer KPI Comparison compares one KPI across companies
- **WHEN** the KPI name is Revenue and Zeta's change is +12.5 and Orbit's is −4.0
- **THEN** the chart shows Zeta 12.50 % and Orbit −4.00 %

### Requirement: Remittance Ageing groups unpaid amounts by days overdue
Remittance Ageing SHALL take the fund's remittances whose status is Pending or Overdue. It SHALL group each one's due amount (call amount + other fees − collected) by days since its capital call's due date: Not yet due (due date after today), 0–30, 31–60, 61–90 and Over 90 days. It SHALL show the count and amount per group, and a link to the fund's remittances list filtered to the same statuses.

#### Scenario: Remittance Ageing groups unpaid amounts by days overdue
- **WHEN** open remittances are due in the future, 15, 60 and 107 days ago
- **THEN** they fall in Not yet due, 0–30, 31–60 and Over 90 respectively

### Requirement: NAV per Unit Trend charts approved NAV per unit by class
NAV per Unit Trend SHALL plot the fund's approved NAV per unit for each unit class, over the `months` (default 12) up to the latest approved NAV.

#### Scenario: NAV per Unit Trend charts approved NAV per unit by class
- **WHEN** classes A and B have approved NAVs for Jul–Sep 2026
- **THEN** the chart has a line for A and a line for B with those points

### Requirement: Hedge Expiries lists open contracts nearing expiry
Hedge Expiries SHALL list the fund's open derivative contracts that expire within `days` (default 90) or have already expired. Rows SHALL be in expiry order, with notional, expiry date and days left (or days since expiry).

#### Scenario: Hedge Expiries lists open contracts nearing expiry
- **WHEN** an open forward expires in 15 days and a closed one in 10 days
- **THEN** only the open forward is listed, showing 15 days

### Requirement: Investor Pending Actions lists what is outstanding with an LP
Investor Pending Actions SHALL show, for the LP, four sections:
- Their Pending or Overdue remittances.
- Their KYCs that are not verified, or that expire within `kyc_expiry_days` (default 60) or have expired.
- Their approval responses still Pending, on approvals that are published and not past due.
- Documents still awaiting e-signature that belong to their commitments or KYCs.

Each section SHALL show a count and up to 5 rows. It SHALL include only records the viewer can open.

#### Scenario: Investor Pending Actions lists what is outstanding with an LP
- **WHEN** the LP has one of each
- **THEN** the four sections each show a count of 1 and the row

### Requirement: Side-letter Obligations lists obligations falling due
Side-letter Obligations SHALL list active obligations whose next due date is within `days` (default 30), or past, overdue ones first. On the Investor Dashboard it SHALL list only that LP's obligations. On the Ops Dashboard it SHALL list all the viewer can see.

#### Scenario: Side-letter Obligations lists obligations falling due
- **WHEN** an active obligation is due in 15 days and a fulfilled one is due tomorrow
- **THEN** only the active one is listed

### Requirement: Needs Attention counts stuck work with links
Needs Attention SHALL show four counts, each linking to the list it counts:
- Overdue tasks: open, due date before today.
- KYCs to verify: submitted and not verified.
- Overdue remittances: status Overdue.
- Open e-sign requests: requested, sent or in progress.

Each count SHALL equal the number of rows its link shows.

#### Scenario: Needs Attention counts stuck work with links
- **WHEN** there are 3 overdue tasks and the user clicks that card
- **THEN** the card shows 3 and the task list shows the same 3 tasks

### Requirement: Overdue Tasks by Assignee shows who is behind
Overdue Tasks by Assignee SHALL chart the number of open overdue tasks per assignee. Tasks with no assignee SHALL be grouped as "Unassigned". It SHALL show the `top_n` largest (default 10) and group the rest as "Others".

#### Scenario: Overdue Tasks by Assignee shows who is behind
- **WHEN** Meera has 3, unassigned 2 and Ravi 1
- **THEN** the bars are Meera 3, Unassigned 2, Ravi 1

### Requirement: Stuck Workflows lists journeys waiting too long on a step
Stuck Workflows SHALL list active journeys whose current step started `days` (default 7) or more days ago, oldest first. Each row SHALL show the record, the journey, the step and the days on the step. Complete, rejected and archived journeys SHALL be left out.

#### Scenario: Stuck Workflows lists journeys waiting too long on a step
- **WHEN** a capital call journey has been on "Approve notice" for 15 days
- **THEN** it is listed with 15 days
