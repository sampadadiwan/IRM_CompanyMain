# Cash Flow Assistant - Technical Design Document

## 1. Overview

### Purpose
An intelligent agent that provides Fund Managers with a consolidated view of cash flow across their funds, enabling informed capital call decisions.

### Design Principles

| Principle | Implementation |
|-----------|----------------|
| Data Quality First | Hard stop - no report generated on stale data |
| Analysis Only | Agent provides analysis and recommendations, does not execute capital calls |
| Configurable | Thresholds, recipients, and scope configurable per agent |
| Separation of Concerns | Agent-specific config separate from scheduling framework |

---

## 2. Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────────────┐
│                      AGENT SCHEDULER FRAMEWORK                       │
│                          (Generic/Existing)                          │
├─────────────────────────────────────────────────────────────────────┤
│  • Manages schedule (frequency, day, time)                          │
│  • Triggers agent execution                                          │
│  • Handles AgentSchedule records                                     │
│  • Manages retries, logging                                          │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ triggers
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    CASH FLOW ASSISTANT AGENT                         │
│                       (Agent-Specific)                               │
├─────────────────────────────────────────────────────────────────────┤
│  • Fund scope and per-fund thresholds                               │
│  • Reminder configuration                                            │
│  • Report recipients                                                 │
│  • Account tags                                                      │
│  • Staleness checking logic                                          │
│  • Cash flow calculation logic                                       │
│  • Report generation                                                 │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ uses
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    DAILY STALENESS REMINDER JOB                      │
│                       (Background Job)                               │
├─────────────────────────────────────────────────────────────────────┤
│  • Runs daily (e.g., 8:00 AM)                                       │
│  • Checks agents within reminder window                              │
│  • Sends notifications to reminder recipients                        │
└─────────────────────────────────────────────────────────────────────┘
```

### Entity Hierarchy

```
Fund Management Company (Organization)
│
├── Apex Growth Fund I (Entity: Fund)
│   ├── Fund I - Main Vehicle
│   ├── SPV Alpha Pvt Ltd (Entity: SPV, parent: Fund I)
│   └── SPV Beta Pvt Ltd (Entity: SPV, parent: Fund I)
│
├── Apex Growth Fund II (Entity: Fund)
│   ├── Fund II - Main Vehicle
│   └── SPV Gamma Pvt Ltd (Entity: SPV, parent: Fund II)
│
└── Apex Opportunities Fund III (Entity: Fund)
    └── Fund III - Main Vehicle (no SPVs)
```

---

## 3. Data Model

### Agent Configuration (stored in SupportAgent.agent_config)

```json
{
  "funds": [
    {
      "fund_id": "uuid-fund-1",
      "name": "Apex Growth Fund I",
      "staleness_thresholds": {
        "cash_accounts_max_days": 30,
        "proforma_max_days": 90
      }
    },
    {
      "fund_id": "uuid-fund-2",
      "name": "Apex Growth Fund II",
      "staleness_thresholds": {
        "cash_accounts_max_days": 15,
        "proforma_max_days": 60
      }
    },
    {
      "fund_id": "uuid-fund-3",
      "name": "Apex Opportunities Fund III",
      "staleness_thresholds": {
        "cash_accounts_max_days": 30,
        "proforma_max_days": 90
      }
    }
  ],

  "reminder_config": {
    "days_before_run": 7,
    "recipients": [
      { "email": "ops@apexcapital.com", "name": "Operations Team" },
      { "email": "accounts@apexcapital.com", "name": "Accounts Team" }
    ]
  },

  "report_recipients": [
    { "email": "fm@apexcapital.com", "name": "Fund Manager" },
    { "email": "cfo@apexcapital.com", "name": "CFO" }
  ],

  "account_tags": {
    "cash": ["Cash", "Bank", "Fixed Deposit", "Liquid MF"],
    "expenses": ["Mgmt Fees", "Legal", "Audit", "Admin"],
    "buffer": ["Buffer Cash"]
  }
}
```

### AgentSchedule (Existing Framework)

| Field | Type | Description |
|-------|------|-------------|
| schedule_id | UUID | Primary key |
| agent_type | String | "CashFlowAssistant" |
| support_agent_id | UUID | Reference to SupportAgent |
| frequency | Enum | weekly, biweekly, monthly |
| day_of_week / day_of_month | Integer | When to run |
| time | Time | Time of day to run |
| next_run_at | DateTime | Next scheduled execution |
| status | Enum | active, paused |

### AgentExecutionLog

| Field | Type | Description |
|-------|------|-------------|
| execution_id | UUID | Primary key |
| support_agent_id | UUID | Reference to SupportAgent |
| executed_at | DateTime | Execution timestamp |
| status | Enum | success, partial_success, blocked |
| funds_processed | JSON | List of funds with their status |
| error_details | JSON | Any errors encountered |

---

## 4. Configuration UI

### Main Configuration Screen

```
┌─────────────────────────────────────────────────────────────┐
│  CASH FLOW ASSISTANT - Configuration                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  FUNDS & STALENESS THRESHOLDS                                │
│  ─────────────────────────────────────────────────────────   │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Fund                    │ Cash (days) │ Proforma (days)│ │
│  ├─────────────────────────┼─────────────┼────────────────┤ │
│  │ Apex Growth Fund I      │ [ 30 ]      │ [ 90 ]         │ │
│  │ Apex Growth Fund II     │ [ 15 ]      │ [ 60 ]         │ │
│  │ Apex Opportunities III  │ [ 30 ]      │ [ 90 ]         │ │
│  └───────────────────────────────────────────────────────┘  │
│  [+ Add Fund]                                                │
│                                                              │
│  REMINDER SETTINGS                                           │
│  ─────────────────────────────────────────────────────────   │
│  Start reminders:  [ 7 ] days before scheduled run          │
│                                                              │
│  Reminder Recipients:                                        │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ ops@apexcapital.com                    [×]          │    │
│  │ accounts@apexcapital.com               [×]          │    │
│  │ [+ Add Recipient]                                    │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  REPORT RECIPIENTS                                           │
│  ─────────────────────────────────────────────────────────   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ fm@apexcapital.com                     [×]          │    │
│  │ cfo@apexcapital.com                    [×]          │    │
│  │ [+ Add Recipient]                                    │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  ACCOUNT TAGS                                                │
│  ─────────────────────────────────────────────────────────   │
│  Cash Accounts:    [ Cash, Bank, Fixed Deposit, Liquid MF ] │
│  Expense Accounts: [ Mgmt Fees, Legal, Audit, Admin ]       │
│  Buffer Account:   [ Buffer Cash ]                           │
│                                                              │
│                                    [Save Configuration]      │
└─────────────────────────────────────────────────────────────┘
```

### Add Fund Modal

```
┌─────────────────────────────────────────────────┐
│  Add Fund                                       │
├─────────────────────────────────────────────────┤
│                                                 │
│  Fund:              [ Select Fund        ▼]    │
│                                                 │
│  Staleness Thresholds:                          │
│  Cash Accounts:     [ 30 ] days                 │
│  Proforma:          [ 90 ] days                 │
│                                                 │
│              [Cancel]  [Add]                    │
└─────────────────────────────────────────────────┘
```

---

## 5. Workflow

### Complete Monthly Cycle

```
TIMELINE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Day 1-23        Day 24 (T-7)      Day 24-30        Day 31
    │                │                 │               │
    ▼                ▼                 ▼               ▼
Normal           Reminder         Daily            Agent
Operations       Window           Staleness        Executes
                 Opens            Checks
```

### Phase A: Normal Operations (Day 1-23)

No agent activity. Business as usual.

### Phase B: Reminder Window (T-7 to T-1)

#### Daily Staleness Reminder Job

**Runs**: Every day at 8:00 AM

**Logic**:

```
1. Query AgentSchedule WHERE:
   - agent_type = 'CashFlowAssistant'
   - status = 'active'
   - next_run_at BETWEEN now AND now + 7 days (max reminder window)

2. For each schedule found:
   a. Load SupportAgent and agent_config
   b. Calculate: days_until_run = next_run_at - today
   c. Check: Is days_until_run <= reminder_config.days_before_run?
   d. If NO: Skip this agent
   e. If YES: Continue to staleness check

3. For each fund in agent_config.funds:
   a. Get all entities (fund + child SPVs)
   b. For each entity:
      - Query latest AccountEntry WHERE account.tag IN cash_tags
      - Calculate: cash_age = today - latest_entry_date
      - If cash_age > fund.staleness_thresholds.cash_accounts_max_days:
        Mark fund as STALE
      - Query Proforma WHERE entity_id = entity AND PI > 0
      - For each proforma, check age against proforma_max_days
   c. Determine fund status: FRESH or STALE

4. Send notification email to reminder_config.recipients:
   - List all funds with their status
   - Days remaining until report
   - Link to update data (Input Wizard)
```

#### Notification Examples

**Some Funds Stale**:

```
Subject: ⚠️ Cash Flow Report - Data Update Required (7 days to run)

DATA STATUS:
┌──────────────────────────┬─────────────┬─────────────────────────┐
│ Fund                     │ Status      │ Action                  │
├──────────────────────────┼─────────────┼─────────────────────────┤
│ Apex Growth Fund I       │ ✅ Fresh     │ No action needed        │
│ Apex Growth Fund II      │ ⚠️ STALE    │ Cash 21 days old (max 15)│
│ Apex Opportunities III   │ ✅ Fresh     │ No action needed        │
└──────────────────────────┴─────────────┴─────────────────────────┘

→ Please update Fund II data before report date.
→ [Update Data via Input Wizard]
```

**All Funds Fresh**:

```
Subject: ✅ Cash Flow Report - All Data Ready (3 days to run)

All fund data is current. Report will generate on schedule.

DATA STATUS:
┌──────────────────────────┬─────────────┬─────────────────────────┐
│ Fund                     │ Status      │ Last Updated            │
├──────────────────────────┼─────────────┼─────────────────────────┤
│ Apex Growth Fund I       │ ✅ Fresh     │ 5 days ago              │
│ Apex Growth Fund II      │ ✅ Fresh     │ 2 days ago              │
│ Apex Opportunities III   │ ✅ Fresh     │ 8 days ago              │
└──────────────────────────┴─────────────┴─────────────────────────┘

No action required.
```

### Phase C: Agent Execution

**Triggered by**: Agent Scheduler Framework on scheduled date/time

#### Step 1: Staleness Gate (Final Check)

```
For each fund in agent_config.funds:
    entities = [fund] + fund.child_spvs

    For each entity in entities:
        # Check cash staleness
        latest_cash_entry = AccountEntry
            .where(entity: entity)
            .where(account.tag IN cash_tags)
            .order(entry_date DESC)
            .first

        cash_age = today - latest_cash_entry.entry_date

        if cash_age > fund.staleness_thresholds.cash_accounts_max_days:
            fund.status = BLOCKED
            fund.block_reason = "Cash data #{cash_age} days old (max: #{threshold})"
            break

        # Check proforma staleness
        stale_proformas = Proforma
            .where(entity: entity)
            .where(PI > 0)
            .where(created_at < today - fund.staleness_thresholds.proforma_max_days)

        if stale_proformas.any?:
            fund.status = BLOCKED
            fund.block_reason = "Proforma #{proforma.name} is #{age} days old"
            break

    if fund.status != BLOCKED:
        fund.status = READY
```

#### Step 2: Calculation (For Each READY Fund)

```
For each fund WHERE status = READY:
    entities = [fund] + fund.child_spvs

    # Aggregate cash
    total_cash = 0
    cash_breakdown = []

    For each entity in entities:
        entity_cash = AccountEntry
            .where(entity: entity)
            .where(account.tag IN cash_tags)
            .latest_per_account
            .sum(:amount)

        total_cash += entity_cash
        cash_breakdown.append({
            entity: entity.name,
            amount: entity_cash,
            last_updated: latest_entry_date
        })

    # Aggregate upcoming investments
    total_investments = 0
    investment_list = []

    For each entity in entities:
        proformas = Proforma
            .where(entity: entity)
            .where(PI > 0)  # Positive = outflow

        For each proforma in proformas:
            total_investments += proforma.expected_amount
            investment_list.append({
                name: proforma.deal_name,
                entity: entity.name,
                amount: proforma.expected_amount,
                expected_date: proforma.expected_date
            })

    # Calculate expenses (average of tagged accounts)
    total_expenses = calculate_estimated_expenses(entities, expense_tags)

    # Get buffer requirement
    buffer = AccountEntry
        .where(entity: fund)
        .where(account.tag IN buffer_tags)
        .latest
        .amount || 0

    # Calculate net position
    net_position = total_cash - total_investments - total_expenses - buffer

    # Calculate runway
    daily_burn = (total_investments + total_expenses) / forecast_days
    runway_days = total_cash / daily_burn

    # Determine status
    if net_position < 0:
        status = SHORTFALL
        recommended_call = abs(net_position) + buffer
    elif runway_days < 30:
        status = WATCH
    elif runway_days < 90:
        status = WATCH
    else:
        status = SURPLUS

    # Store results
    fund.result = {
        cash_available: total_cash,
        cash_breakdown: cash_breakdown,
        upcoming_investments: total_investments,
        investment_list: investment_list,
        estimated_expenses: total_expenses,
        buffer_required: buffer,
        net_position: net_position,
        runway_days: runway_days,
        status: status,
        recommended_call: recommended_call
    }
```

#### Step 3: Generate Outputs

**A. Save In-App Report**

For each fund, save to `CashFlowReport` table or fund's dedicated page:

```
CashFlowReport.create(
    fund_id: fund.id,
    report_date: today,
    data: fund.result.to_json,
    status: fund.status
)
```

**B. Send Email Summary**

Compile results from all funds and send to `report_recipients`.

**C. Log Execution**

```
AgentExecutionLog.create(
    support_agent_id: agent.id,
    executed_at: now,
    status: determine_overall_status(funds),
    funds_processed: funds.map { |f| { id: f.id, status: f.status } }
)
```

---

## 6. Output Formats

### Email Summary

```
Subject: [Status Icon] Cash Flow Update - March 2026 - [Action Required?]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MONTHLY CASH FLOW UPDATE - March 2026
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️ ACTION REQUIRED:
• Apex Growth Fund II: Capital call of ₹8.00 Cr recommended

PORTFOLIO SUMMARY:
┌────────────────────────┬────────────┬─────────────┬──────────┬───────────┐
│ Fund                   │ Status     │ Net Position│ Runway   │ Action    │
├────────────────────────┼────────────┼─────────────┼──────────┼───────────┤
│ Apex Growth Fund I     │ 🟡 Watch    │ +₹0.50 Cr   │ 45 days  │ Monitor   │
│ Apex Growth Fund II    │ 🔴 Shortfall│ -₹7.00 Cr   │ 18 days  │ Call ₹8Cr │
│ Apex Opportunities III │ 🟢 Surplus  │ +₹4.00 Cr   │ 180+ days│ None      │
│ Apex Early Stage IV    │ ⚠️ BLOCKED │ --          │ --       │ Update    │
└────────────────────────┴────────────┴─────────────┴──────────┴───────────┘

[View Fund I Details]  [View Fund II Details]  [View Fund III Details]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Report generated: 01-Mar-2026, 09:00 AM
Data freshness: 3 of 4 funds current
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### In-App Report (Per Fund)

**Location**: Fund → Cash Flow Analysis tab

```
┌─────────────────────────────────────────────────────────────┐
│  CASH FLOW ANALYSIS - Apex Growth Fund II + SPVs            │
│  Report Date: 01-Mar-2026                    Status: 🔴      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  EXECUTIVE SUMMARY                                           │
│  ─────────────────────────────────────────────────────────   │
│  Total Cash Available     : ₹ 5.00 Cr                        │
│  Upcoming Investments     : ₹ 10.00 Cr                       │
│  Estimated Expenses       : ₹ 1.50 Cr                        │
│  Buffer Required          : ₹ 0.50 Cr                        │
│  ─────────────────────────────────────────────────────────   │
│  Net Position             : (₹ 7.00 Cr) SHORTFALL            │
│  Runway                   : 18 days                          │
│                                                              │
│  ⚠️ RECOMMENDATION                                           │
│  Capital Call of ₹ 8.00 Cr recommended                       │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│  CASH BY ENTITY                                              │
│  ─────────────────────────────────────────────────────────   │
│  Entity            │ Cash       │ Last Updated │ Status      │
│  Fund II (Main)    │ ₹ 4.20 Cr  │ 4 days ago   │ ✅ Fresh    │
│  SPV Gamma         │ ₹ 0.80 Cr  │ 4 days ago   │ ✅ Fresh    │
│  TOTAL             │ ₹ 5.00 Cr  │              │             │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│  UPCOMING INVESTMENTS                                        │
│  ─────────────────────────────────────────────────────────   │
│  Deal              │ Entity     │ Amount     │ Expected Date │
│  Deal Gamma T2     │ SPV Gamma  │ ₹ 6.00 Cr  │ 15-Mar-26     │
│  Deal Delta        │ Fund II    │ ₹ 4.00 Cr  │ 25-Mar-26     │
│  TOTAL             │            │ ₹ 10.00 Cr │               │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│  ESTIMATED EXPENSES (Next 90 days)                           │
│  ─────────────────────────────────────────────────────────   │
│  Category          │ Amount                                  │
│  Management Fees   │ ₹ 0.80 Cr                               │
│  Legal             │ ₹ 0.40 Cr                               │
│  Audit & Admin     │ ₹ 0.30 Cr                               │
│  TOTAL             │ ₹ 1.50 Cr                               │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│  UNDRAWN CAPITAL                                             │
│  ─────────────────────────────────────────────────────────   │
│  Total Commitment        : ₹ 50.00 Cr                        │
│  Drawn to Date           : ₹ 35.00 Cr                        │
│  Undrawn                 : ₹ 15.00 Cr                        │
│  Reserved for Follow-ons : ₹ 5.00 Cr                         │
│  Available to Call       : ₹ 10.00 Cr ✅                     │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│  DATA QUALITY                                                │
│  ─────────────────────────────────────────────────────────   │
│  All data sources current. Report confidence: HIGH           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 7. Status Definitions

| Status | Icon | Condition | Email Subject Prefix |
|--------|------|-----------|---------------------|
| Surplus | 🟢 | Net Position > 0, Runway > 90 days | ✅ |
| Watch | 🟡 | Net Position > 0, Runway 30-90 days | 🟡 |
| Shortfall | 🔴 | Net Position < 0 | 🔴 Action Required |
| Blocked | ⚠️ | Data is stale | ⚠️ |

---

## 8. Decision Summary

| # | Component | Decision |
|---|-----------|----------|
| 1 | Purpose | Analysis only - no capital call execution |
| 2 | Frequency | Biweekly / Monthly (via Agent Scheduler) |
| 3 | Fund Scope | Configurable: Select funds via multi-select |
| 4 | Staleness Thresholds | Per-fund configurable |
| 5 | Staleness Handling | Hard stop - no report for fund with stale data |
| 6 | SPV Handling | Automatically included with parent fund, inherits thresholds |
| 7 | Reminder Window | T-X days configurable per agent |
| 8 | Daily Staleness Check | Runs every day during reminder window |
| 9 | Notify Both States | Stale: "Update needed" / Fresh: "Ready" |
| 10 | Reminder Recipients | Configurable via UI (operations team) |
| 11 | Report Recipients | Configurable via UI (FM, CFO) |
| 12 | Email Output | Portfolio summary - all funds in one email |
| 13 | In-App Output | Detailed per-fund "Cash Flow Analysis" page (latest only) |
| 14 | Report History | Latest report only (no history) |

---

## 9. Implementation Checklist

### Backend

- [ ] Create `CashFlowAssistantAgent` service class
- [ ] Implement `StalenessChecker` service
- [ ] Create `DailyStalenessReminderJob` (daily cron)
- [ ] Implement cash flow calculation logic
- [ ] Create `CashFlowReport` model (or use existing report structure)
- [ ] Email templates for reminders and reports
- [ ] Agent configuration validation

### Frontend

- [ ] Agent configuration UI (funds, thresholds, recipients)
- [ ] Add Fund modal with threshold inputs
- [ ] Cash Flow Analysis page per fund
- [ ] Email template rendering

### Integration

- [ ] Register agent type with Agent Scheduler Framework
- [ ] Hook into existing AccountEntry and Proforma models
- [ ] Link to Input Wizard for data updates

---

## 10. Phase 2 Features (Future)

| Feature | Description |
|---------|-------------|
| Watch Status Suggestions | Detailed recommendations when runway is thin |
| Distribution Recommendations | Suggest distributions when excess cash |
| Stress Testing | Expense surge and realization delay scenarios |
| Input Wizard Enhancements | Excel upload with auto-mapping |
| Historical Trending | Compare forecasts vs actuals over time |
