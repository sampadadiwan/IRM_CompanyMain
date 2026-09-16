---
name: portco-analyst
description: "Work on the Portfolio Company Agent (PortfolioCompanyAgent) — the deterministic monitoring agent that checks KPI submission, document compliance, and valuation currency for each portfolio company, generates SupportAgentReports, and powers the Portfolio Company Dashboard. Use when implementing, modifying, or debugging the portco compliance pipeline, consolidated reminders, the dashboard UI, batch/single execution modes, or the look-back window logic."
---

## Context

Before making changes, **read these files in order**:

1. This skill file (you're here)
2. [.claude/skills/agent-charts/SKILL.md](../agent-charts/SKILL.md) — AgentChart model + chart generation (triggered by this agent)
3. [.claude/skills/support-agents/SKILL.md](../support-agents/SKILL.md) — Host framework (SupportAgentService base, SupportAgentJob, execution modes)

## What This Agent Does

**PortfolioCompanyAgent** is a deterministic compliance checker — NO LLM calls. It runs against each portfolio company (Investor with category = "Portfolio Company") in an entity and validates:

1. Are they submitting KPIs on time?
2. Are required documents uploaded?
3. Is their valuation current?

It produces a `SupportAgentReport` per company (pass/fail/blocked) and triggers `AgentChartJob` to generate visual charts from KPI data.

## Domain Concepts

### What is a Portfolio Company?

A portfolio company is a startup/company that the fund has **invested in**. In the data model, it's an `Investor` record with `category == "Portfolio Company"`. The fund manager monitors these companies — they must report KPIs, submit documents, and maintain current valuations.

```
LP (investor) ──invests in──→ Fund ──invests in──→ Portfolio Company (Investor record)
```

### KPIs (Key Performance Indicators)

Metrics the portfolio company reports quarterly/monthly: revenue, burn rate, headcount, ARR, etc. Stored in `PortfolioKpiReport` records. The agent checks whether the latest KPI report was submitted within the configured period.

### The Compliance Loop

```
Agent runs (scheduled or manual)
  ↓
Window gate (scheduled only): skip if today outside T+start..T+end
  ↓
For each portfolio company:
  Step 1: Initialize — validate it's a portfolio company, agent enabled
  Step 2: Check KPI Submission — compute look-back period, query KPIs with as_of in range
  Step 3: Check Document Presence — required docs uploaded with KPI report?
  Step 4: Check Valuations — valuation_date in same period range
  Step 5: Send Reminders — consolidated email listing only missing items (KPIs, docs, valuations). Dedup per day.
  Step 6: Generate Report — save SupportAgentReport (ready/blocked)
```

## Pipeline Steps (Detail)

### Step 1: `initialize_agent`
- Loads `support_agent` and validates target is a portfolio company
- Initializes `ctx[:issues] = { kpi_issues: [], document_issues: [], valuation_issues: [] }`
- Returns false (halts pipeline) if target is not a portfolio company or agent disabled

### Step 2: `check_kpi_submission`
- Calls `compute_check_period(check_as_on_date: ctx[:check_as_on_date])` to determine the look-back period
- Stores `ctx[:period_info]` (period_start, period_end, check_date, window_start, window_end, period_label) for downstream steps
- Queries `portfolio_company.portfolio_kpi_reports.where(as_of: period_start..period_end)` — range match, not exact
- Stores `@last_kpi_report` for document check step
- Issues: `:success` if found, `:blocking` if missing

### Step 3: `check_document_presence`
- Skipped if `@last_kpi_report` is nil (no KPI report to validate against)
- Delegates to base class `SupportAgentService#check_document_presence`
- Checks: form File fields + `required_docs` config + KPI report attachments
- Issues: `:blocking` for each missing doc, `:success` if all present

### Step 4: `check_valuations`
- Reuses `ctx[:period_info]` from `check_kpi_submission` (same period range)
- Queries `portfolio_company.valuations.where(valuation_date: period_start..period_end)` — range match
- Issues: `:success` if found, `:blocking` if missing

### Step 5: `send_kpi_reminder`
- Config: `send_kpi_reminder` (Yes/No)
- Runs after all three checks so `ctx[:issues]` is fully populated
- Builds `missing_items` list from blocking issues across KPIs, documents, and valuations
- Sends consolidated reminder only for what's missing; skipped when everything is submitted
- Dedup: checks `json_fields["last_kpi_reminder_sent_at"]` to avoid double-send on same calendar day
- Mailer: `EntityMailer.kpi_reminder` with `missing_items` and `period_label` params

### Step 6: `generate_progress_reports`
- Aggregates all issues into `SupportAgentReport` (owner: portfolio company)
- Final status: "ready" (no blocking) or "blocked" (has blocking issues)
- Broadcasts row update via Turbo Stream for live UI

## Configuration (json_fields)

### Current Settings (Look-Back Window)

| Field | Type | Default | Purpose |
|---|---|---|---|
| `due_period` | String | "Quarter" | Reporting period: Monthly, Quarterly, Half-Yearly, Annually |
| `start_days_after_period_end` | Integer | 15 | T+start: window opens this many days after period ends |
| `end_days_after_period_end` | Integer | 60 | T+end: window closes this many days after period ends |
| `send_kpi_reminder` | Select | "Yes" | Enable/disable KPI reminder emails |
| `required_docs` | String | "" | CSV of additional required document names |
| `validate_documents` | Select | "Yes" | Enable/disable document presence check |

### Legacy Settings (deprecated, fallback still reads them)

| Field | Replaced by |
|---|---|
| `days_before_due_period_end` | `start_days_after_period_end` (fallback reads old key) |
| `reminder_days` | Run frequency via `AgentSchedule` (no longer day-offset based) |
| `valuation_period` | Unified — uses same `due_period` as KPIs |
| `days_before_valuation_period_end` | Unified — uses same window as KPIs |

## Execution Modes

| Mode | Trigger | Window Gate? | Step UI? | Notifications |
|---|---|---|---|---|
| `:adhoc_batch` | Run Now on support agents page | No | No — batch progress panel | Per-company + summary |
| `:adhoc_batch` (with date) | Dashboard "Run Validation" with period dropdown | No | No — batch progress panel | Per-company + summary |
| `:single_company_with_steps` | "Run Agent" on investor show page | No | Yes — live step circles | Step progress panel |
| `:scheduled` | AgentScheduleJob (cron) | **Yes** — skips outside T+start..T+end | No | Silent |
| Selective batch | "Run on Selected" from portfolio run page | No | No — batch mode | Per-company + summary |

**Note:** AgentChartJob was decoupled from this agent (v2.1, 2026-06-29). Charts are manual-trigger only via "Regenerate" button.

### Batch Processing (`process_batch` class method)

```ruby
# Standard flow (auto-compute period)
PortfolioCompanyAgent.process_batch(
  support_agent_id: id, targets: targets,
  user_id: user_id, entity_id: entity_id,
  execution_mode: :adhoc_batch
)
# → delegates to SupportAgentService.run_batch

# Dashboard flow (manual period selection)
PortfolioCompanyAgent.process_batch(
  support_agent_id: id, targets: targets,
  user_id: user_id, entity_id: entity_id,
  execution_mode: :adhoc_batch,
  check_as_on_date: Date.parse("2026-06-30")
)
# → delegates to run_batch_with_check_date (injects date into Trailblazer ctx)
```

Key methods:
- `process_batch` — entry point; applies window gate for scheduled runs; branches to `run_batch` or `run_batch_with_check_date`
- `run_batch_with_check_date` — mirrors shared `run_batch` loop but adds `check_as_on_date:` to `.wtf?()` ctx
- `compute_check_period(check_as_on_date:)` — computes period range, window dates, period label
- `within_active_window?` — returns true if today is between T+start and T+end
- `PortfolioValidationJob` — dashboard-specific job (avoids modifying shared `SupportAgentJob`)

## Output

### SupportAgentReport (per company)

```json
{
  "kpi_issues": [
    { "type": "info", "message": "Q2 2026 KPIs submitted (as_of: 2026-06-30)", "severity": "success" }
  ],
  "document_issues": [
    { "type": "missing", "message": "Financial Statement", "severity": "blocking" }
  ],
  "valuation_issues": [
    { "type": "missing", "message": "Q2 2026 valuation missing (expected valuation_date between 2026-04-01 and 2026-06-30)", "severity": "blocking" }
  ],
  "final_status": "blocked",
  "last_kpi_reminder_sent_at": "2026-07-22",
  "completed_at": "2026-07-22T11:00:00Z",
  "triggered_by": "manual",
  "run_at": "2026-07-22T10:59:00Z"
}
```

### AgentCharts (DECOUPLED)

Charts are manual-trigger only via the "Regenerate" button on AgentCharts UI. See [agent-charts skill](../agent-charts/SKILL.md) for details.

## Key Files

### Agent Core
| File | Purpose |
|---|---|
| [portfolio_company_agent.rb](../../app/packs/ai/support_agents/services/portfolio_company_agent.rb) | Main 6-step pipeline |
| [support_agent_service.rb](../../app/packs/ai/support_agents/services/support_agent_service.rb) | Base class — step broadcasting, report helpers |
| [support_agent_job.rb](../../app/packs/ai/support_agents/jobs/support_agent_job.rb) | Job orchestrator — dispatches execution modes |
| [support_agent.rb](../../app/packs/ai/support_agents/models/support_agent.rb) | Model — config, AGENT_TYPES, enabled checks |
| [support_agent_report.rb](../../app/packs/ai/support_agents/models/support_agent_report.rb) | Report model — stores per-company results |

### Charts Integration (DECOUPLED — charts no longer auto-triggered by this agent)
| File | Purpose |
|---|---|
| [agent_chart.rb](../../app/packs/ai/agent_charts/models/agent_chart.rb) | Chart definitions + `generate_spec!` |
| [agent_chart_job.rb](../../app/packs/ai/agent_charts/jobs/agent_chart_job.rb) | Chart generation job — tag matching, LLM call |
| [chart_agent_service.rb](../../app/packs/ai/agent_charts/services/chart_agent_service.rb) | LLM call to generate Chart.js JSON |

### Views & UI (Standalone Dashboard)
| File | Purpose |
|---|---|
| [show.html.erb](../../app/packs/ai/portfolio_company_dashboard/views/portfolio_company_dashboard/show.html.erb) | Dashboard page — window status + stats + chart + actions + table + footer |
| [_stats.html.erb](../../app/packs/ai/portfolio_company_dashboard/views/portfolio_company_dashboard/_stats.html.erb) | 7 compact stat cards (Row 1: overview, Row 2: issue breakdown by category) |
| [_chart.html.erb](../../app/packs/ai/portfolio_company_dashboard/views/portfolio_company_dashboard/_chart.html.erb) | Missing by Type bar chart (per-document-type breakdown) |
| [_actions.html.erb](../../app/packs/ai/portfolio_company_dashboard/views/portfolio_company_dashboard/_actions.html.erb) | Agent Actions: Run Validation (with period dropdown), Send Reminders (with last-sent warning), View Pending Issues, Overdue Companies list |
| [_table.html.erb](../../app/packs/ai/portfolio_company_dashboard/views/portfolio_company_dashboard/_table.html.erb) | Full-width company table with dynamic document columns |
| [_footer.html.erb](../../app/packs/ai/portfolio_company_dashboard/views/portfolio_company_dashboard/_footer.html.erb) | Recommended next steps + last run info |
| [_window_status.html.erb](../../app/packs/ai/portfolio_company_dashboard/views/portfolio_company_dashboard/_window_status.html.erb) | Window status indicator bar (Active/Not yet open/Closed) |
| [_report_detail.html.erb](../../app/packs/ai/portfolio_company_dashboard/views/portfolio_company_dashboard/_report_detail.html.erb) | Expandable detail — 3-card accordion (KPI, Docs, Valuations) |
| [portfolio_dashboard_chart_controller.js](../../app/javascript/controllers/portfolio_dashboard_chart_controller.js) | Chart.js bar chart Stimulus controller |
| [portfolio_dashboard_filter_controller.js](../../app/javascript/controllers/portfolio_dashboard_filter_controller.js) | Table search + status filter + stat card click-to-filter |
| [portfolio_dashboard_presenter.rb](../../app/packs/ai/portfolio_company_dashboard/services/portfolio_dashboard_presenter.rb) | Dashboard aggregations — stats, document_types, document_ok?, issues_by_type, last_reminder_sent_at |
| [portfolio_agent_run.html.erb](../../app/packs/core/investors/views/investors/portfolio_agent_run.html.erb) | Selective run page — checkboxes + "Run on Selected" |

### Controllers
| File | Purpose |
|---|---|
| [portfolio_company_dashboard_controller.rb](../../app/packs/ai/portfolio_company_dashboard/controllers/portfolio_company_dashboard_controller.rb) | Standalone dashboard: show, run_validation (head :ok), send_reminders (head :ok) |
| [support_agents_controller.rb](../../app/packs/ai/support_agents/controllers/support_agents_controller.rb) | `run_with_steps`, `run_batch`, portfolio reports tab |
| [agent_charts_controller.rb](../../app/packs/ai/agent_charts/controllers/agent_charts_controller.rb) | CRUD + `regenerate` action |
| [investors_controller.rb](../../app/packs/core/investors/controllers/investors_controller.rb) | `portfolio_agent_run` action |

### Jobs
| File | Purpose |
|---|---|
| [portfolio_validation_job.rb](../../app/packs/ai/portfolio_company_dashboard/jobs/portfolio_validation_job.rb) | Dashboard-specific job — accepts check_as_on_date, avoids modifying shared SupportAgentJob |

### Mailer
| File | Purpose |
|---|---|
| [entity_mailer.rb](../../app/packs/core/entities/mailers/entity_mailer.rb) | `kpi_reminder` — consolidated reminder with missing_items and period_label params |

### Routes
| File | Key routes |
|---|---|
| [config/routes/ai.rb](../../config/routes/ai.rb) | `resources :support_agents` (run_with_steps, run_batch), `resources :agent_charts` (regenerate) |

## Related Models

| Model | Role in Pipeline |
|---|---|
| `Investor` | Portfolio company record (category = "Portfolio Company") |
| `PortfolioKpiReport` | KPI submission by portfolio company |
| `Document` | Uploaded documents (financial statements, compliance docs) |
| `Valuation` | Company valuation records |
| `FormCustomField` | Defines required fields/docs per form type |
| `AgentChart` | Chart definition — prompt, data source, tags |
| `AgentExecutionLog` | Tracks each agent run (timing, status, trigger type) |

## Known Issues

| Issue | Severity | Notes |
|---|---|---|
| 3 duplicate PortfolioCompanyAgent records (IDs 2, 3, 12) for entity 157 | Low | From before setup was idempotent; category nil (not backfilled) |
| No "Generate Charts" button on AgentChart show page | Low | Route exists (`POST /agent_charts/:id/regenerate`) but no UI button |
| All charts re-run on every agent run | Low | Tag-matched charts regenerate even if data unchanged; LLM may produce different specs |
| Batch run has no step UI | By design | Uses `:adhoc_batch` mode; progress via notifications only |

## Dashboard (Standalone — v3)

**Status:** Implemented (2026-07-29). Branch: `feature/portco-standalone-dashboard`.

**Design docs:** `docs/modules/ai/portfolio_company_agent/business_design.md` + `docs/modules/ai/portfolio_company_agent/technical_design.md`

### Current Layout (v3)

1. **Window Status Bar** — Active/Not yet open/Closed indicator with dates
2. **Row 1 — 4 Compact Stat Cards (Overview):** Total Companies | Validated | Up to Date | Not Yet Validated
3. **Row 2 — 3 Compact Stat Cards (Issue Breakdown):** KPI Not Submitted | Valuation Missing | Documents Not Uploaded
4. **Row 3 — Two Panels (50/50):** Missing by Type bar chart (left) | Agent Actions (right)
5. **Row 4 — Full-Width Company Table:** Searchable/filterable with dynamic per-document-type columns
6. **Footer:** Recommended Next Steps (dynamic) + Last run timestamp

### Agent Actions Panel

- **Run Validation** — form with period dropdown (Auto or past 4 periods); responds `head :ok` (no page reload)
- **Send Reminders** — consolidated emails listing missing items per company; shows last-sent date + days-ago warning in confirm dialog; responds `head :ok`
- **View Pending Issues** — server-side filter link
- **Overdue Companies** — top 5 companies with blocking issues

### Design Decisions (v3)

- **Standalone pack** — `app/packs/ai/portfolio_company_dashboard/` — decoupled from support_agents framework views
- **Compact stat cards** — `h4` numbers, `py-1 px-3` padding for minimal vertical space
- **No page reload** — Run Validation and Send Reminders respond with `head :ok`; batch progress panel updates via Turbo Streams
- **Consistent hover** — all action buttons use neutral `border rounded` with CSS border-color hover
- **Last-sent warning** — Send Reminders button shows "Last sent: Jul 28 (1 day ago)" and confirm dialog warns before re-sending
- **Consolidated reminders** — one email per company listing only missing items (KPIs, Documents, Valuations); `EntityMailer.kpi_reminder` accepts `missing_items` and `period_label` params
- **Dynamic document columns** — one column per File-type `FormCustomField`; `presenter.document_ok?(report, doc_name)` per cell
- **AgentChartJob decoupled** — charts are manual-trigger only via "Regenerate" button

## Related Skills

- [agent-charts](../agent-charts/SKILL.md) — AgentChart model + chart generation (triggered by this agent)
- [support-agents](../support-agents/SKILL.md) — Host framework (base classes, job orchestration, execution modes)
- [portfolio-assistant](../portfolio-assistant/SKILL.md) — Chat bubble adapter for portfolio Q&A (separate from this agent)
