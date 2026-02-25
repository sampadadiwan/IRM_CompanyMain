# Cash Flow Assistant - End-to-End Walkthrough

A concrete walkthrough of how the Cash Flow Assistant works, using a fictional company example traced through the actual codebase.

---

## 1. Fictional Setup: "Acme Capital"

### Company

| Field | Value |
|-------|-------|
| Company | Acme Capital |
| Entity ID | 100 |
| Role | Fund Management Company |

### Funds (5 total, only 2 in scope)

| Fund | ID | In Scope? | Entities |
|------|----|-----------|----------|
| Acme Growth Fund I | 201 | Yes | "Acme Growth I" (entity 301) + SPV "Acme Growth I - Singapore" (entity 302) |
| Acme Growth Fund II | 202 | Yes | "Acme Growth II" (entity 303), no SPVs |
| Acme Infra Fund | 203 | No | - |
| Acme Real Estate Fund | 204 | No | - |
| Acme Debt Fund | 205 | No | - |

Funds 203, 204, 205 are **not configured** in the agent -- they are completely ignored.

### People

| Person | Email | Role |
|--------|-------|------|
| Rajesh (CFO) | cfo@acmecapital.com | Receives final report |
| Priya (Ops Head) | ops@acmecapital.com | Receives final report |
| Meena (Accountant) | accountant@acmecapital.com | Receives staleness reminders |

---

## 2. Agent Configuration

A `SupportAgent` record is created via the UI at `/support_agents/new`:

```
SupportAgent:
  id: 10
  name: "Acme Cash Flow Monitor"
  agent_type: "CashFlowAssistantAgent"
  entity_id: 100
  enabled: true
```

The `json_fields` stores all cash flow-specific config:

```json
{
  "funds": [
    {
      "fund_id": "201",
      "name": "Acme Growth Fund I",
      "staleness_thresholds": {
        "cash_accounts_max_days": 30,
        "proforma_max_days": 90
      }
    },
    {
      "fund_id": "202",
      "name": "Acme Growth Fund II",
      "staleness_thresholds": {
        "cash_accounts_max_days": 30,
        "proforma_max_days": 90
      }
    }
  ],
  "cash_tags": "Bank Balance, FD",
  "expense_tags": "Management Fee, Operating Expense",
  "buffer_tags": "Reserve",
  "report_recipients": "cfo@acmecapital.com, ops@acmecapital.com",
  "reminder_recipients": "accountant@acmecapital.com",
  "reminder_days_before_run": 7
}
```

### What each config field means

| Field | Purpose | Example |
|-------|---------|---------|
| `funds` | Which funds to analyze, with per-fund staleness thresholds | Fund I: cash max 30 days, proforma max 90 days |
| `cash_tags` | AccountEntry `entry_type` values that represent cash | "Bank Balance", "FD" |
| `expense_tags` | AccountEntry `entry_type` values for expenses | "Management Fee", "Operating Expense" |
| `buffer_tags` | AccountEntry `entry_type` values for reserves | "Reserve" |
| `report_recipients` | Emails that receive the final consolidated report | CFO, Ops Head |
| `reminder_recipients` | Emails that receive pre-run staleness warnings | Accountant |
| `reminder_days_before_run` | How many days before scheduled run to start sending reminders | 7 days |

---

## 3. Schedule Configuration

On the agent's **Schedule tab** (`/support_agents/10?tab=schedule`), a schedule is configured:

```
AgentSchedule:
  support_agent_id: 10
  entity_id: 100
  frequency: "weekly"
  run_on_day: 1          # Monday
  run_at_time: "09:00"
  timezone: "Asia/Kolkata"
  enabled: true
  notify_on_success: true
  notify_on_failure: true
  failure_notification_user_ids: [user_id_of_rajesh]
```

This means: **Run every Monday at 9:00 AM IST**.

---

## 4. Two Ways to Trigger

### Path A: Manual Run (from UI)

```
User clicks "Run" on /support_agents/10
    |
    v
SupportAgentsController#run_with_steps
    |
    v
SupportAgentJob.perform_later(support_agent_id: 10, target_id: 100,
                               target_type: "Entity", user_id: 55,
                               with_steps: true)
    |
    v
CashFlowAssistantAgent.call(...)   <-- runs in background (ActiveJob)
    |
    v
6-step Trailblazer Operation executes
    |
    v
Real-time Turbo Stream updates to UI (progress circles)
```

**Code path**: `SupportAgentsController#run_with_steps` (line 107)
1. Finds `SupportAgent#10`
2. Target = `Entity.find(100)` (Acme Capital itself)
3. Checks no existing running report
4. Enqueues `SupportAgentJob`
5. Creates `SupportAgentReport` with 6 pending steps
6. Returns Turbo Stream -- progress panel appears: `o o o o o o`

### Path B: Scheduled Run (automatic)

```
DailyMorningJob (runs at 01:30 AM daily via Sidekiq cron)
    |
    v
AgentDailySchedulerService.new.call
    |
    v
Finds AgentSchedule for SupportAgent#10
    |-- Is today Monday? Yes
    |-- Is 9:00 AM IST still in the future? Yes
    |-- Already running? No
    |
    v
Creates AgentExecutionLog (status: "queued")
    |
    v
AgentRunnerJob.perform_at(9:00 AM IST, execution_log.id)
    |
    v
At 9:00 AM: AgentRunnerJob fires
    |
    v
CashFlowAssistantAgent.call(...)   <-- runs via Sidekiq
```

**Code path**: `AgentDailySchedulerService` -> `AgentRunnerJob` -> `CashFlowAssistantAgent`

---

## 5. The SupportAgentJob (Bridge Layer)

When the job fires (either path), it:

1. Finds `SupportAgent#10` from DB
2. Calls `support_agent.agent` which does `"CashFlowAssistantAgent".constantize` -- returns the class
3. Gets targets: `CashFlowAssistantAgent.new.targets(100)` returns `Entity.where(id: 100)` -- just the org entity (Acme Capital)
4. For manual run (`with_steps: true`):
   - Initializes a `SupportAgentReport` with step tracking
   - Calls `CashFlowAssistantAgent.call(support_agent_id: 10, target: entity, ...)`
5. For scheduled run:
   - Calls `CashFlowAssistantAgent.call(...)` without step tracking

---

## 6. CashFlowAssistantAgent - The 6 Steps

This is a `Trailblazer::Operation` (inherits from `SupportAgentService`) with 6 sequential steps. Each step broadcasts real-time progress via Turbo Streams.

### Step 1: `initialize_agent`

**What it does**: Reads configuration from the database.

```ruby
@config            = @support_agent.json_fields
@funds_config      = [Fund 201 config, Fund 202 config]
@report_recipients = ["cfo@acmecapital.com", "ops@acmecapital.com"]
@cash_tags         = ["Bank Balance", "FD"]
@expense_tags      = ["Management Fee", "Operating Expense"]
@buffer_tags       = ["Reserve"]

ctx[:fund_results] = []
ctx[:issues]       = { staleness_issues: [], calculation_issues: [] }
```

**UI progress**: `[*] o o o o o` -> `[v] o o o o o` ("Loaded config for 2 fund(s)")

---

### Step 2: `check_data_staleness`

**What it does**: Uses `CashFlowStalenessChecker` to verify data freshness for each configured fund. This is the **gate** -- stale funds are blocked from calculation.

**For Fund I (201)** -- checks 2 entities (main + SPV):

```sql
-- Entity 301 (Acme Growth I): Find latest cash entry
SELECT MAX(reporting_date) FROM account_entries
WHERE fund_id = 201 AND entity_id = 301
  AND entry_type IN ('Bank Balance', 'FD')
-- Result: 2026-01-25 (17 days ago) --> within 30-day threshold

-- Entity 302 (Singapore SPV): Same query
-- Result: 2026-02-01 (10 days ago) --> within threshold

-- Check proforma investments for staleness
SELECT * FROM portfolio_investments
WHERE fund_id = 201 AND status = 'proforma'
  AND amount_cents > 0 AND created_at < 90.days.ago
-- Result: none
```

**Fund I verdict: `"ready"`**

**For Fund II (202)** -- checks 1 entity (no SPVs):

```sql
SELECT MAX(reporting_date) FROM account_entries
WHERE fund_id = 202 AND entity_id = 303
  AND entry_type IN ('Bank Balance', 'FD')
-- Result: 2025-12-15 (58 days ago) --> EXCEEDS 30-day threshold!
```

**Fund II verdict: `"blocked"`** -- reason: "Acme Growth II: Cash 58d old (max 30d)"

**Result stored in context**:

```ruby
ctx[:fund_results] = [
  { fund_id: 201, name: "Acme Growth Fund I",  status: "ready",   block_reasons: [] },
  { fund_id: 202, name: "Acme Growth Fund II", status: "blocked", block_reasons: ["Acme Growth II: Cash 58d old (max 30d)"] }
]
```

**UI progress**: `[v] [v] o o o o` ("1 ready, 1 blocked")

---

### Step 3: `calculate_cash_positions`

**What it does**: Calculates cash flow for **ready funds only**. Blocked funds are skipped entirely.

**Only processes Fund I (201)**. Fund II is skipped.

For Fund I, aggregates across both entities (main entity 301 + SPV 302):

#### Cash Available (`aggregate_cash`)

```sql
-- Entity 301: Latest AccountEntry with entry_type IN ('Bank Balance', 'FD')
-- Bank Balance: Rs 5,00,00,000
-- FD:           Rs 2,00,00,000
-- Subtotal:     Rs 7,00,00,000

-- Entity 302 (SPV): Same query
-- Bank Balance: Rs 1,00,00,000
-- Subtotal:     Rs 1,00,00,000

-- Total cash: Rs 8,00,00,000
```

#### Upcoming Investments (`aggregate_investments`)

```sql
-- PortfolioInvestment.proforma WHERE fund_id = 201 AND amount_cents > 0
-- "TechStartup A": Rs 3,00,00,000 (expected March 2026)
-- "HealthCo B":    Rs 1,50,00,000 (expected April 2026)
-- Total upcoming:  Rs 4,50,00,000
```

#### Estimated Expenses (`aggregate_expenses`)

```sql
-- AccountEntry WHERE entry_type IN ('Management Fee', 'Operating Expense')
-- Total: Rs 50,00,000
```

#### Buffer Required (`fetch_buffer`)

```sql
-- AccountEntry WHERE entry_type = 'Reserve'
-- Total: Rs 1,00,00,000
```

#### Final Calculations

```
net_position  = 8,00,00,000 - 4,50,00,000 - 50,00,000 - 1,00,00,000
              = Rs 2,00,00,000  (POSITIVE)

daily_outflow = (4,50,00,000 + 50,00,000) / 90
              = Rs 5,55,556/day

runway_days   = 8,00,00,000 / 5,55,556
              = 144 days

fund_status   = "surplus"   (net positive AND runway > 90 days)

recommended_call = 0        (no shortfall, no call needed)
```

**Fund I result now includes**:

```ruby
{
  fund_id: 201,
  name: "Acme Growth Fund I",
  status: "ready",
  cash_available: 80000000,
  cash_breakdown: [
    { entity_name: "Acme Growth I", amount_cents: 70000000, last_updated: "2026-01-25" },
    { entity_name: "Acme Growth I - Singapore", amount_cents: 10000000, last_updated: "2026-02-01" }
  ],
  upcoming_investments: 45000000,
  investment_list: [
    { name: "TechStartup A", entity_name: "Acme Growth I", amount_cents: 30000000, expected_date: "2026-03-15" },
    { name: "HealthCo B", entity_name: "Acme Growth I - Singapore", amount_cents: 15000000, expected_date: "2026-04-01" }
  ],
  estimated_expenses: 5000000,
  buffer_required: 10000000,
  net_position: 20000000,
  runway_days: 144,
  fund_status: "surplus",
  recommended_call: 0,
  currency: "INR"
}
```

**UI progress**: `[v] [v] [v] o o o` ("Calculated for 1 fund(s)")

---

### Step 4: `generate_fund_reports`

**What it does**: Creates/updates a `SupportAgentReport` record for **each fund** (including blocked ones).

```ruby
# Fund I --> completed report with all calculation data
SupportAgentReport.find_or_create_by(owner: Fund#201, support_agent: #10)
  status: :completed
  json_fields: { fund_status: "surplus", cash_available: 80000000, ... }

# Fund II --> failed report (blocked due to stale data)
SupportAgentReport.find_or_create_by(owner: Fund#202, support_agent: #10)
  status: :failed
  json_fields: { status: "blocked", block_reasons: ["Cash 58d old (max 30d)"] }
```

**UI progress**: `[v] [v] [v] [v] o o` ("Saved 2 fund report(s)")

---

### Step 5: `send_report_email`

**What it does**: Sends a consolidated email to configured report recipients via `CashFlowReportMailer`.

```ruby
CashFlowReportMailer.with(
  support_agent_id: 10,
  fund_results: ctx[:fund_results],     # both funds (ready + blocked)
  recipients: ["cfo@acmecapital.com", "ops@acmecapital.com"],
  currency: "INR"
).send_report.deliver_later
```

**Email sent to Rajesh (CFO) and Priya (Ops Head)**:

```
Subject: Cash Flow Update - February 2026

PORTFOLIO SUMMARY:
+------------------------+----------+---------------+---------+------------+
| Fund                   | Status   | Net Position  | Runway  | Action     |
+------------------------+----------+---------------+---------+------------+
| Acme Growth Fund I     | Surplus  | +Rs 2.00 Cr   | 144 days| None       |
| Acme Growth Fund II    | BLOCKED  | --            | --      | Update data|
+------------------------+----------+---------------+---------+------------+
```

If no recipients are configured, this step is **skipped** (not failed).

**UI progress**: `[v] [v] [v] [v] [v] o` ("Queued for 2 recipient(s)")

---

### Step 6: `generate_progress_reports`

**What it does**: Finalizes the overall execution report.

```ruby
# Check if any steps had "failed" status
has_failures = report.steps.any? { |s| s["status"] == "failed" }

# In our case: Step 2 detected blocked fund, but the STEP itself succeeded
# (it successfully detected the staleness). So:
final_status = "ready"
report.status = :completed
```

Broadcasts final Turbo Stream update -- progress panel shows completed state.

**UI progress**: `[v] [v] [v] [v] [v] [v]` -- Done!

---

## 7. Real-time UI Updates (Turbo Streams)

During execution, each step broadcasts updates via `Turbo::StreamsChannel`:

1. **Step circle update**: Each step's circle icon changes (pending -> running -> success/failed/skipped)
2. **Progress bar update**: Overall progress bar advances

The stream channel is `"support_agent_report_#{report.id}"`. The UI subscribes to this channel when the run starts.

Updates are sent from `SupportAgentService#broadcast_step` which:
- Sets `started_at` when step starts running
- Sets `completed_at` and `duration_ms` when step finishes
- Replaces the step circle partial and progress bar partial via Turbo

---

## 8. The Reminder System (Pre-Run Warning)

Separate from the actual run, a daily reminder system warns about stale data **before** the scheduled run.

### How it works

`DailyMorningJob` (runs at 01:30 AM) calls `CashFlowStalenessReminderService.new.call`:

1. Finds all enabled `SupportAgent` records with `agent_type: "CashFlowAssistantAgent"`
2. For each agent, checks if the next scheduled run is within `reminder_days_before_run` window
3. If yes, runs `CashFlowStalenessChecker` (same shared logic as Step 2)
4. Sends email to `reminder_recipients` via `CashFlowReminderMailer`

### Example timeline (schedule: Monday 9 AM, reminder window: 7 days)

| Day | Days Until Run | Action |
|-----|----------------|--------|
| Previous Tuesday | 6 | Reminder sent: "Fund II has stale data. 6 days until report." |
| Wednesday | 5 | Reminder sent: "Fund II still stale. 5 days left." |
| Thursday | 4 | Accountant updates Fund II bank data |
| Friday | 3 | Reminder sent: "All data current. Report ready." |
| Saturday | 2 | Reminder sent: "All data current." |
| Sunday | 1 | Reminder sent: "Report generates tomorrow." |
| **Monday 9 AM** | **0** | **Agent runs. Both funds ready. Full report generated.** |

**Email to Meena (Accountant)**:

```
Subject: Cash Flow Report - Data Update Required (6 days to run)

DATA STATUS:
+------------------------+---------+---------------------------+
| Fund                   | Status  | Action                    |
+------------------------+---------+---------------------------+
| Acme Growth Fund I     | Fresh   | No action needed          |
| Acme Growth Fund II    | STALE   | Cash 58 days old (max 30) |
+------------------------+---------+---------------------------+

Please update Fund II data before Monday.
```

---

## 9. Scheduled Run via AgentDailySchedulerService

### What happens at 01:30 AM Monday

`DailyMorningJob` calls `AgentDailySchedulerService.new.call`:

1. **Find due schedules**: Queries `AgentSchedule.enabled` and filters by `should_run_today?`
   - Schedule for SupportAgent#10: frequency = "weekly", run_on_day = 1 (Monday)
   - Today is Monday? **Yes** -> due today

2. **Calculate run time**: Converts `09:00` in `Asia/Kolkata` timezone to UTC
   - 09:00 IST = 03:30 UTC

3. **Check guards**:
   - Is 03:30 UTC in the future? **Yes** (it's 01:30 AM)
   - Already running? **No**

4. **Create execution log**:
   ```ruby
   AgentExecutionLog.create!(
     agent_schedule: schedule,
     support_agent: agent_10,
     entity: entity_100,
     trigger_type: 'scheduled',
     status: 'queued',
     attempt_number: 1
   )
   ```

5. **Schedule the job**:
   ```ruby
   AgentRunnerJob.perform_at(03:30_UTC, execution_log.id)
   ```

### What happens at 9:00 AM IST (03:30 UTC)

`AgentRunnerJob` fires:

1. Loads execution log, marks `status: 'running'`, sets `started_at`
2. Gets targets: `Entity.where(id: 100)`
3. Calls `CashFlowAssistantAgent.call(support_agent_id: 10, target: entity_100, entity_id: 100)`
4. The 6 steps execute (same as manual run, without step UI tracking)
5. On success:
   - Marks execution log `status: 'completed'`, sets `completed_at` and `result_summary`
   - Updates `schedule.last_run_at`
   - Sends success notification if `notify_on_success` is true
6. On failure:
   - Marks execution log `status: 'failed'`, records `error_message`
   - Checks retry config: if `retry_count > 0` and attempts remaining, schedules retry
   - If all retries exhausted, sends failure notification

---

## 10. Component Summary

| Component | File | Role |
|-----------|------|------|
| `SupportAgent` | `models/support_agent.rb` | Config record -- stores funds, tags, recipients in `json_fields` |
| `AgentSchedule` | `models/agent_schedule.rb` | Schedule config -- frequency, time, timezone, retry settings |
| `AgentExecutionLog` | `models/agent_execution_log.rb` | Audit trail -- tracks each execution attempt with timing and status |
| `SupportAgentReport` | `models/support_agent_report.rb` | Per-fund result storage and step progress tracking |
| `SupportAgentJob` | `jobs/support_agent_job.rb` | ActiveJob bridge -- called for manual runs from UI |
| `AgentRunnerJob` | `jobs/agent_scheduler/agent_runner_job.rb` | Sidekiq job -- called for scheduled runs |
| `AgentDailySchedulerService` | `services/agent_scheduler/agent_daily_scheduler_service.rb` | Finds schedules due today, queues AgentRunnerJob at configured time |
| `CashFlowAssistantAgent` | `services/cash_flow_assistant_agent.rb` | The 6-step Trailblazer operation -- the actual business logic |
| `CashFlowStalenessChecker` | `services/cash_flow_staleness_checker.rb` | Shared staleness logic -- used by both the agent and the reminder service |
| `CashFlowStalenessReminderService` | `services/agent_scheduler/cash_flow_staleness_reminder_service.rb` | Pre-run reminder orchestrator -- checks window, calls checker, sends email |
| `CashFlowReportMailer` | `mailers/cash_flow_report_mailer.rb` | Sends consolidated report email to CFO/FM |
| `CashFlowReminderMailer` | `mailers/cash_flow_reminder_mailer.rb` | Sends staleness warning email to operations |
| `DailyMorningJob` | `jobs/daily_morning_job.rb` | Master daily cron -- calls both scheduler service and reminder service |

---

## 11. Flow Diagram

```
                    DailyMorningJob (01:30 AM daily)
                           |
              +------------+-------------+
              |                          |
              v                          v
  AgentDailySchedulerService    CashFlowStalenessReminderService
              |                          |
              v                          v
  AgentRunnerJob (at 9 AM)      CashFlowStalenessChecker
              |                          |
              v                          v
  CashFlowAssistantAgent        CashFlowReminderMailer
       |                          (email to accountant)
       |-- Step 1: Initialize
       |-- Step 2: Staleness Check (uses CashFlowStalenessChecker)
       |-- Step 3: Calculate Cash Positions
       |-- Step 4: Generate Fund Reports (SupportAgentReport per fund)
       |-- Step 5: Send Email (CashFlowReportMailer to CFO/Ops)
       |-- Step 6: Finalize Report
```

```
  Manual Run (UI):

  User clicks "Run"
       |
       v
  SupportAgentsController#run_with_steps
       |
       v
  SupportAgentJob (ActiveJob)
       |
       v
  CashFlowAssistantAgent (same 6 steps)
       |
       v
  Turbo Stream updates (real-time progress in browser)
```

---

## 12. Status Definitions

| Status | Condition | Meaning | Recommended Action |
|--------|-----------|---------|-------------------|
| **Surplus** | Net Position > 0, Runway > 90 days | Healthy cash position | None |
| **Watch** | Net Position > 0, Runway < 90 days | Cash getting thin | Monitor closely |
| **Shortfall** | Net Position < 0 | Not enough cash for commitments | Capital call recommended |
| **Blocked** | Data is stale | Cannot generate reliable report | Update stale data first |
