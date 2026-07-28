# Portfolio Company Agent — Look-Back Window Redesign

## Technical Design Document

**Date:** 2026-07-21
**Status:** Implemented — consolidated reminders confirmed by product spec 2026-07-28
**Branch:** `feature/portco-standalone-dashboard`

---

## 1. Problem Statement

The Portfolio Company Agent monitors whether portfolio companies have submitted their KPIs, valuations, and documents on time. The current logic checks the **current period** window:

```ruby
due_date = Date.end_of_period("Quarter") - 15.days
# On July 10, 2026 → end_of_period returns September 30 (current quarter)
# due_date = September 15 — checks Jul–Sep data that doesn't exist yet
```

Companies submit data **after** a period ends (typically 15–45 days later). By the time Q2 data arrives in July, the agent has moved to checking Q3. Late submissions are never validated against the correct period.

### Current Behavior (Broken)

```
Today: July 10, 2026
Agent checks: Q3 (Jul 1 – Sep 15) ← current quarter, no data exists yet
Q2 data (Apr–Jun): arriving now but agent ignores it
```

### Desired Behavior (Look-Back Window)

```
Today: July 10, 2026
Last completed quarter: Q2, ended June 30
T = June 30
T+15 = July 15 (window opens)
T+60 = August 29 (window closes)
Agent checks: Q2 (Apr 1 – Jun 30) ← the period companies are actually submitting for
```

---

## 2. Look-Back Window — Concept

"T" = the end date of the most recently completed period (e.g., June 30 for Q2).

```
April 1          June 30         July 15                    August 29         Sept 30
  |---- Q2 2026 ----|              |---- ACTIVE WINDOW ----|                    |
  Data is for this                 Agent runs here,                          Next quarter
  period                           checking: "Did you                          ends
                                   submit Q2 data?"
```

- **Before T+15:** Agent skips — too early, companies need time to prepare
- **T+15 to T+60:** Agent runs on schedule, checks for data with `as_of` in the completed period, sends reminders for missing items
- **After T+60:** Scheduled runs stop. Adhoc runs remain available with manual date selection

---

## 3. Configuration Settings

All settings stored in `support_agents.json_fields` (existing JSON column).

### New Settings

| Key | Type | Options | Default | Purpose |
|-----|------|---------|---------|---------|
| `due_period` | string | Monthly, Quarterly, Half-Yearly, Annually | Quarterly | Reporting cycle (existing, unchanged) |
| `start_days_after_period_end` | integer | 7, 15, 30 | 15 | T+start: when the window opens |
| `end_days_after_period_end` | integer | 30, 45, 60, 90 | 60 | T+end: when the window closes |

### Removed Settings

| Key | Replaced By |
|-----|-------------|
| `days_before_due_period_end` | `start_days_after_period_end` |
| `reminder_days` | Run frequency handled by existing `AgentSchedule` |

### Unchanged Settings

| Key | Purpose |
|-----|---------|
| `send_kpi_reminder` | Toggle email reminders on/off |
| `valuation_period` | **Removed** — valuations use the same `due_period` and window as KPIs |

### Run Frequency

No new setting. The existing `AgentSchedule` (daily / weekly / bi-weekly / monthly) controls how often the agent runs. The agent itself adds a **window gate**: if today is outside T+start to T+end, scheduled runs skip silently.

---

## 4. Core Logic Change

### 4.1 Period Computation

```ruby
# NEW: Look-back logic
def compute_check_period
  period = @support_agent.json_fields["due_period"] || "Quarter"
  start_days = (@support_agent.json_fields["start_days_after_period_end"] || 15).to_i
  end_days = (@support_agent.json_fields["end_days_after_period_end"] || 60).to_i

  # Step 1: Find the most recently completed period-end
  # "previous" means the last period that has fully ended before today
  check_date = Date.previous_end_of_period(period)

  # Step 2: Compute the active window
  window_start = check_date + start_days.days   # e.g., June 30 + 15 = July 15
  window_end   = check_date + end_days.days     # e.g., June 30 + 60 = August 29

  # Step 3: Compute the data range to query
  period_start = Date.previous_end_of_period(period, check_date) + 1.day  # Apr 1
  period_end   = check_date                                                 # Jun 30

  {
    check_date: check_date,       # June 30 — the period-end we're validating
    window_start: window_start,   # July 15 — agent starts running
    window_end: window_end,       # August 29 — agent stops running
    period_start: period_start,   # April 1 — query range start
    period_end: period_end        # June 30 — query range end
  }
end
```

### 4.2 Window Gate (Scheduled Runs Only)

```ruby
def within_active_window?
  today = Time.zone.today
  period_info = compute_check_period
  today.between?(period_info[:window_start], period_info[:window_end])
end
```

- **Scheduled runs:** Check `within_active_window?`. If false, skip silently (log but don't run).
- **Adhoc runs:** Always execute. Use the `check_as_on_date` param if provided, otherwise auto-compute.

### 4.3 Data Queries (Range Match)

The agent checks for data where `as_of` / `valuation_date` falls **anywhere within the period range**, not an exact date match.

```ruby
# KPI reports for Q2: any report with as_of between April 1 and June 30
kpi_report = company.portfolio_kpi_reports
  .where(as_of: period_start..period_end)
  .order(as_of: :desc)
  .first

# Valuations for Q2
valuation = company.valuations
  .where(valuation_date: period_start..period_end)
  .first

# Documents: checked via KPI report attachments (existing logic)
```

**Why range, not exact match?** Companies don't always tag data with the exact period-end date. A report with `as_of = May 31` within Q2 is valid Q2 data.

### 4.4 Early Uploads

If a company uploads KPI data on June 25 with `as_of = June 30`, the agent finds it when it runs on July 15 because `June 30` is within `April 1..June 30`. Upload date (`created_at`) is irrelevant — only `as_of` matters.

---

## 5. Reminder Logic

### Consolidated Reminders

One email per company per run, listing only what's missing:

| Missing Items | Reminder Content |
|---------------|-----------------|
| All 3 (KPI + Valuation + Documents) | "KPI report, valuation, and documents are pending for Q2 2026" |
| KPI + Valuation | "KPI report and valuation are pending for Q2 2026" |
| Documents only | "Documents are pending for Q2 2026" |
| Nothing missing | No reminder sent |

### Deduplication

Existing `last_kpi_reminder_sent_at` logic in report `json_fields` prevents sending duplicate reminders on the same day. No change needed.

### Reminder Window

Reminders only sent during the active window (T+start to T+end). After T+end, no more automated reminders.

---

## 6. UI Changes

### 6.1 Agent Edit Page — New Config Partial

**File:** `app/packs/ai/support_agents/views/support_agents/_portfolio_company_config.html.erb`

Added to `_form.html.erb` alongside existing agent-type configs (CashFlow, KYC, DealManagement).

```
┌─────────────────────────────────────────────────────────┐
│  Portfolio Company Agent Configuration                  │
│                                                         │
│  Reporting Period        [Quarterly         ▼]          │
│                                                         │
│  Start Checking After    [15 days           ▼]          │
│  (days after period end)                                │
│                                                         │
│  Stop Checking After     [60 days           ▼]          │
│  (days after period end)                                │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │ ℹ With these settings, for Q2 ending June 30:  │    │
│  │   • Agent starts checking: July 15              │    │
│  │   • Agent stops checking: August 29             │    │
│  │   • Data checked: April 1 – June 30             │    │
│  └─────────────────────────────────────────────────┘    │
│                                                         │
│  Run frequency is set in the Agent Schedule tab.        │
└─────────────────────────────────────────────────────────┘
```

**Dropdown options:**

| Field | Options |
|-------|---------|
| Reporting Period | Monthly, Quarterly, Half-Yearly, Annually |
| Start Checking After | 7 days, 15 days, 30 days |
| Stop Checking After | 30 days, 45 days, 60 days, 90 days |

**Info box:** Dynamically computed preview showing the actual dates based on current selections. Helps the admin understand what the settings mean without guessing.

### 6.2 Dashboard — "Run Now" Button Enhancement

**File:** `app/packs/ai/portfolio_company_dashboard/views/portfolio_company_dashboard/_actions.html.erb`

The existing "Run Validation" button gets an optional date dropdown for adhoc runs.

```
┌──────────────────────────────────────────┐
│  Agent Actions                           │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ ▶ Run Validation                   │  │
│  │   Check all data for completeness  │  │
│  │                                    │  │
│  │   Check period: [Auto (Q2 - Jun 30) ▼]│
│  │                                    │  │
│  │   Options:                         │  │
│  │     • Auto (Q2 - Jun 30, 2026)     │  │
│  │     • Q1 - Mar 31, 2026            │  │
│  │     • Q4 - Dec 31, 2025            │  │
│  │     • Q3 - Sep 30, 2025            │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ ✉ Send Reminders                  │  │
│  │   Email 5 companies with missing   │  │
│  │   submissions                      │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ 👁 View Pending Issues             │  │
│  │   Filter and review all issues     │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

**Dropdown behavior:**
- Default selection: "Auto" — uses the auto-computed previous period-end
- Shows the last 4 valid period-end dates based on the agent's `due_period` setting
- If a random date were somehow entered, the system snaps to the nearest completed period-end
- Adhoc runs always execute regardless of the T+start / T+end window

### 6.3 Dashboard — Active Window Indicator

A small status bar at the top of the dashboard showing the current window state.

```
┌──────────────────────────────────────────────────────────────────┐
│  Portfolio Company Dashboard                                     │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ 🟢 Active Window: Jul 15 – Aug 29 (Q2 2026, Day 6 of 45) │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  [stat cards...]                                                 │
│  [chart + actions...]                                            │
│  [company table...]                                              │
└──────────────────────────────────────────────────────────────────┘
```

States:
- **Active (green):** "Active Window: Jul 15 – Aug 29 (Q2 2026, Day 6 of 45)"
- **Not yet open (grey):** "Next Window Opens: Jul 15 (Q2 2026, in 5 days)"
- **Closed (orange):** "Window Closed: Aug 29 was the last day for Q2 2026"

---

## 7. Execution Modes — Updated

| Mode | Window Gate? | Date Input | Behavior |
|------|-------------|------------|----------|
| Scheduled (cron) | Yes — skips if outside window | Auto-computed | Runs only during T+start to T+end |
| Adhoc (Run Now button) | No — always runs | Dropdown (auto or manual period-end) | FM can run anytime, for any period |
| Single company (investor page) | No — always runs | Uses agent's current period | Step-by-step progress panel |

---

## 8. Files to Change

### Agent Logic (Core)

| File | Change |
|------|--------|
| `app/packs/ai/support_agents/services/portfolio_company_agent.rb` | Replace period calculation with look-back logic; add window gate; unify valuation period with KPI period |
| `config/initializers/date_localized_parse.rb` | Verify `Date.previous_end_of_period` works correctly for all period types |

### Agent Edit Page

| File | Change |
|------|--------|
| `app/packs/ai/support_agents/views/support_agents/_portfolio_company_config.html.erb` | **New file** — config partial with 3 dropdowns + info box |
| `app/packs/ai/support_agents/views/support_agents/_form.html.erb` | Add `PortfolioCompanyAgent` conditional to render new config partial |
| `app/javascript/controllers/portfolio_company_config_controller.js` | **New file** — Stimulus controller for dynamic info box preview |

### Dashboard

| File | Change |
|------|--------|
| `app/packs/ai/portfolio_company_dashboard/views/portfolio_company_dashboard/_actions.html.erb` | Add period-end dropdown to Run Validation button |
| `app/packs/ai/portfolio_company_dashboard/views/portfolio_company_dashboard/show.html.erb` | Add active window indicator bar |
| `app/packs/ai/portfolio_company_dashboard/controllers/portfolio_company_dashboard_controller.rb` | Accept `check_as_on_date` param for adhoc runs |
| `app/packs/ai/portfolio_company_dashboard/services/portfolio_dashboard_presenter.rb` | Pass period info to views for window indicator |

### Scheduler

| File | Change |
|------|--------|
| `app/packs/ai/support_agents/jobs/agent_scheduler/agent_runner_job.rb` | No change — window gate is inside the agent, not the scheduler |

---

## 9. Migration Plan

### Data Migration

No database migration needed. All new settings go into the existing `json_fields` JSON column.

For existing agents, defaults apply automatically:
- `start_days_after_period_end` → 15 (same as old `days_before_due_period_end` default)
- `end_days_after_period_end` → 60 (new, no equivalent before)
- `due_period` → unchanged

### Backward Compatibility

Old `json_fields` keys (`days_before_due_period_end`, `reminder_days`) are read with fallback to new keys during a transition period, then removed.

---

## 10. Open Questions

| # | Question | Options | Recommendation |
|---|----------|---------|----------------|
| 1 | ~~Consolidated vs individual reminders~~ | ~~One email vs separate per category~~ | **Decided: Consolidated** — one email per company listing all missing items |
| 2 | Valuation separate period? | Same window as KPIs vs separate settings | **Recommended: Same window** — simpler config, one set of dropdowns |
| 3 | What if company has no `as_of` on KPI report? | Skip / treat as missing / use `created_at` fallback | Treat as missing — `as_of` is required for proper period matching |

---

## 11. Example Walkthrough

### Setup
- Period: Quarterly
- Start days: 15
- End days: 60
- Schedule: Weekly

### Quarter ends June 30, 2026

| Date | What Happens |
|------|-------------|
| Jul 1–14 | Agent scheduled runs fire but window gate skips (before T+15). No checks, no reminders. |
| Jul 15 | **Window opens.** First scheduled run. Checks each company for KPI reports with `as_of` in Apr 1 – Jun 30, valuations with `valuation_date` in same range, and documents. Company A missing all 3 → consolidated reminder sent. Company B has everything → no reminder. |
| Jul 22 | Second run. Company A uploaded KPIs on Jul 18 (`as_of = Jun 30`). Now only valuation + docs missing → reminder for those 2 only. |
| Jul 29 | Third run. Company A uploaded valuation. Only docs missing → reminder for docs only. |
| Aug 5 | Company A uploaded documents. All complete → no reminder. Agent marks company as compliant. |
| Aug 12–26 | Remaining runs. Only companies still missing items get reminders. |
| Aug 29 | **Window closes.** Last scheduled run. |
| Aug 30+ | Scheduled runs fire but window gate skips. FM can still use "Run Now" with manual date selection. |
| Oct 15 | **Next window opens** for Q3 (ended Sep 30). Agent now checks for Q3 data (Jul 1 – Sep 30). |
