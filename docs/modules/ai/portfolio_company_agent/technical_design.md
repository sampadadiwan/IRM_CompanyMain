# Portfolio Company Agent — Look-Back Window Redesign

## Technical Design Document

**Date:** 2026-07-21 (updated 2026-08-13)
**Status:** Implemented — dashboard enhancements (skip-reminders, per-company Send Reminders, validation summary email, dashboard scoping) on `feature/portco-dashboard-enhancements`
**Branch:** `feature/portco-dashboard-enhancements` (continuation of `feature/portco-standalone-dashboard`)

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

### New Settings (2026-08-13)

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `kpi_reminder_recipients` | TextArea | "" | Comma-separated email addresses for KPI reminders. If blank, no reminders sent even when `send_kpi_reminder` = Yes. Replaces the old fallback to `@entity.employees`. Provisioned via `SupportAgentsSetupService`. |

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

### Guard Chain (send_kpi_reminder step)

Guards execute in order; first match skips the step:

1. **Agent toggle:** `enabled?("send_kpi_reminder")` — agent-level on/off
2. **Per-company opt-out:** `portfolio_company.json_fields["skip_kpi_reminder"]` — FM excludes sold/written-off companies
3. **No missing items:** all KPIs, docs, valuations submitted — no reminder needed
4. **Same-day dedup:** `last_kpi_reminder_sent_at` in report `json_fields` — one reminder per day max
5. **No recipients configured:** `support_agent.json_fields["kpi_reminder_recipients"]` blank — skip silently

### Recipients

`kpi_reminder_recipients` (TextArea on agent config) holds comma-separated email addresses. Passed as `recipient_emails` param to `EntityMailer.kpi_reminder`. The mailer prefers this over the legacy `@entity.employees` fallback (which sent to fund team, not portfolio company contacts).

```ruby
# entity_mailer.rb — preference chain
@to ||= params[:recipient_emails].presence || @entity.employees.pluck(:email).join(',')
```

The legacy `entities_controller#kpi_reminder` caller does not pass `recipient_emails`, so it still falls back to entity employees.

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

### Skip Reminders Toggle

The `skip_reminders` param threads from the Run Validation form checkbox → `run_validation` controller action → `PortfolioValidationJob` → `process_batch` → `run_batch_with_check_date` → Trailblazer ctx. The `send_kpi_reminder` step checks `ctx[:skip_reminders]` as the first guard.

- Hidden field ensures `send_reminders=0` is always submitted when unchecked
- Checkbox only rendered when `support_agent.json_fields["send_kpi_reminder"]` is Yes/true/1
- Default: unchecked (skip reminders) — FM validates first, then sends reminders separately

### Per-Company Send Reminders Panel

The Send Reminders action uses an inline collapsible panel (Bootstrap collapse, not modal — avoids backdrop hover-flicker issues) with:

- **Select2 search** — multi-select dropdown for finding companies by name; syncs with table checkboxes via `send-reminders-select` Stimulus controller
- **Company table** — scrollable (max-height 250px) with columns: checkbox, company name, issue count, last-reminded date (with days-ago display, or "Never")
- **Select all** — header checkbox, checked by default
- **Sync behavior** — selecting in Select2 checks the table row; unchecking a table row removes from Select2; toggling select-all updates both

**Data source:** `presenter.overdue_companies` returns companies with blocking issues, each with `:name`, `:owner_id`, `:issues_count`, `:last_reminder_sent_at`.

**Form submission:** Only `selected_ids[]` checkboxes are submitted (not the Select2 values). Controller reads `params[:selected_ids]` to scope reminder emails.

### Dashboard Scoping (`last_run_target_ids`)

`PortfolioValidationJob` persists the resolved target IDs in `support_agent.json_fields["last_run_target_ids"]` after each run:

- **Scoped run** (FM selected specific companies/tags/sectors): stores the resolved array of Investor IDs
- **All-company run** (no selection): stores `nil` — dashboard shows everything, no toggle bar

The dashboard `show` action reads `last_run_target_ids`:
- When present (array): filters reports to only those companies; shows a toggle bar with "Show last run (N)" / "Show all" links
- When nil: no filtering, no toggle bar

This ensures the dashboard always reflects the last run's scope by default, while giving the FM a one-click way to see all companies.

### Validation Summary Email

After every adhoc run, `process_batch` calls `send_validation_summary` which:

1. Loads latest reports for all processed companies via single query: `SupportAgentReport.where(owner_id: owner_ids, latest: true)`
2. Aggregates stats mirroring `PortfolioDashboardPresenter` logic (up_to_date, has_issues, per-category overdue counts)
3. Builds `issues_by_type` hash with per-document-type granularity (e.g., "Financial Statement" → 3, "Board Deck" → 1)
4. Builds `company_rows` — per-company status with `doc_status = nil` when KPI not submitted (renders as "--" in email)
5. Preloads investor names via single query: `Investor.where(id: owner_ids).pluck(:id, :investor_name).to_h`
6. Delivers `PortfolioValidationDigestMailer` with `entity_id` in params (required by `ApplicationMailer#setup_defaults`)

**Pattern:** Follows `DealManagementDigestMailer` — inherits `SupportAgentBaseMailer` for shared email helpers (`sa_banner`, `sa_callout`, `sa_section`, `sa_kv_table`, `sa_footer`).

**N+1 prevention:** Two queries total — one for reports, one for investor names. No per-company queries.

**Error handling:** Wrapped in `rescue StandardError => e` with logger — email failure does not block the batch result.

### Document Column Display

When a company hasn't submitted KPIs, the document check step (`check_document_presence`) is skipped entirely because documents attach to KPI reports. This means absence of `document_issues` in the report doesn't mean "documents OK" — it means "not checked."

Both the dashboard table and validation summary email handle this:
- **Dashboard table:** `presenter.kpi_submitted?(report)` returns false → document columns show "--"
- **Email:** `doc_status = Array(...).none? { ... } if kpi_ok` → returns `nil` when KPI not submitted → template renders "--"

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

### 6.2 Dashboard — "Run Validation" with Period + Target Selector

**Files:**
- `app/packs/ai/portfolio_company_dashboard/views/portfolio_company_dashboard/_actions.html.erb`
- `app/packs/ai/portfolio_company_dashboard/controllers/portfolio_company_dashboard_controller.rb`
- `app/packs/ai/portfolio_company_dashboard/jobs/portfolio_validation_job.rb`
- `app/javascript/controllers/portfolio_validation_target_controller.js`

The "Run Validation" form has four controls: a period dropdown, three Select2 multi-selects for targeting, and a skip-reminders checkbox.

```
┌──────────────────────────────────────────┐
│  Agent Actions                           │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ ▶ Run Validation                   │  │
│  │   Check data for completeness      │  │
│  │                                    │  │
│  │   Check period:                    │  │
│  │   [Auto (Q2 - Jun 30, 2026)    ▼] │  │
│  │                                    │  │
│  │   Tags:     [SaaS ×  HealthTech ×] │  │
│  │   Sectors:  [All sectors       ▼]  │  │
│  │   Companies:[All companies     ▼]  │  │
│  │                                    │  │
│  │   ☐ Send reminders to companies    │  │
│  │     with missing items             │  │
│  │                                    │  │
│  │   [Run]                            │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

**Period dropdown behavior:**
- Default selection: "Auto" — uses the auto-computed previous period-end
- Shows the last 4 valid period-end dates based on the agent's `due_period` setting
- Adhoc runs always execute regardless of the T+start / T+end window

**Target selector behavior:**
- Three Select2 multi-select dropdowns: Tags, Sectors, Companies — all optional
- Leaving all empty runs on all companies (same as before)
- Tags + sectors are AND'd when both present; explicit company IDs are always additive
- Stimulus controller (`portfolio-validation-target`) builds a human-readable label from selected values for the confirm dialog (e.g., "tagged SaaS, in sectors HealthTech, 3 selected companies")

**Data flow:**

```
Form submits: target_tags[]/target_sectors[]/target_ids[] + check_as_on_date + send_reminders
  → controller#run_validation
    → resolve_target_ids: queries Investor with entity_id scoping
      → returns Array<Integer> (specific IDs) or nil (all companies)
    → PortfolioValidationJob.perform_later(target_ids: [...], check_as_on_date: ..., skip_reminders: ...)
      → Job: persists last_run_target_ids (nil for all, array for scoped)
        → PortfolioCompanyAgent.process_batch(targets: scoped_relation, skip_reminders: ...)
          → send_validation_summary (email to FM after batch completes)
```

**Security:** `resolve_target_ids` re-queries with `entity_id` scoping — tampered IDs from other entities are filtered out. The job adds a second validation layer with the same scoping.

**Tag/sector resolution:** Tags and sectors are plain string columns on `investors` (`tag_list` comma-separated, `sector` plain string). The controller queries all portfolio companies, splits/deduplicates values, and uses `.tally` for counts. Filtering uses existing scopes: `Investor.with_tag_list(tags)` (LIKE-based OR) and `Investor.in_sector(sectors)` (LIKE-based OR).

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

| Mode | Window Gate? | Date Input | Target Input | Behavior |
|------|-------------|------------|-------------|----------|
| Scheduled (cron) | Yes — skips if outside window | Auto-computed | All companies | Runs only during T+start to T+end |
| Adhoc (Dashboard) | No — always runs | Dropdown (auto or manual period-end) | Target selector (all, selected, by tag, by sector) | FM can run anytime, for any period, on any subset |
| Adhoc (Support Agents page) | No — always runs | Auto-computed | All companies | Quick trigger, no targeting |
| Single company (investor page) | No — always runs | Uses agent's current period | Single company | Step-by-step progress panel |

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
| `app/packs/ai/portfolio_company_dashboard/views/portfolio_company_dashboard/_actions.html.erb` | Period dropdown + Select2 target selectors (Tags, Sectors, Companies) + skip-reminders checkbox + Send Reminders collapsible panel with per-company table |
| `app/packs/ai/portfolio_company_dashboard/views/portfolio_company_dashboard/_stats.html.erb` | 7 compact stat cards (h4 numbers, py-1 px-3 padding) |
| `app/packs/ai/portfolio_company_dashboard/views/portfolio_company_dashboard/show.html.erb` | Active window indicator bar + last-run scope toggle (show-all/show-last-run) |
| `app/packs/ai/portfolio_company_dashboard/controllers/portfolio_company_dashboard_controller.rb` | `show` queries target selector data + reads `last_run_target_ids` for scoping + `show_all` param; `run_validation` accepts selections + `send_reminders` toggle; `send_reminders` reads `selected_ids[]` |
| `app/packs/ai/portfolio_company_dashboard/jobs/portfolio_validation_job.rb` | Accepts `target_ids` + `skip_reminders`; persists `last_run_target_ids` (nil for all-company, array for scoped); scopes targets |
| `app/javascript/controllers/portfolio_validation_target_controller.js` | Stimulus controller — builds target label from Select2 selections, confirm dialog with reminder state |
| `app/javascript/controllers/send_reminders_select_controller.js` | **New file** — Stimulus controller syncing Select2 ↔ table checkboxes for Send Reminders panel |
| `app/packs/ai/portfolio_company_dashboard/services/portfolio_dashboard_presenter.rb` | Dashboard aggregations + `kpi_submitted?` + `overdue_companies` with per-company `last_reminder_sent_at` |

### Validation Summary Email

| File | Change |
|------|--------|
| `app/packs/ai/portfolio_company_dashboard/mailers/portfolio_validation_digest_mailer.rb` | **New file** — inherits `SupportAgentBaseMailer`; loads support_agent, user, successes, errors, summary; mails to FM |
| `app/packs/ai/portfolio_company_dashboard/views/portfolio_validation_digest_mailer/validation_summary.html.erb` | **New file** — email template: banner, overview stats, Missing by Type bar chart, issue callouts, per-company table, errors, footer |
| `app/packs/ai/support_agents/services/portfolio_company_agent.rb` | Added `send_validation_summary` class method (called from `process_batch` after adhoc runs); aggregates reports, builds summary hash, delivers mailer |

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
