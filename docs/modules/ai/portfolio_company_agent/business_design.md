# Portfolio Company Agent — Look-Back Window Redesign

## Business Design Document

**Date:** 2026-07-21 (updated 2026-08-13)
**Status:** Implemented — dashboard enhancements (skip-reminders, per-company Send Reminders, validation summary email, dashboard scoping) added 2026-08-13

---

## 1. Purpose

The Portfolio Company Agent automatically checks whether portfolio companies have submitted their KPIs, valuations, and documents for a given reporting period. When data is missing, it sends reminder emails to the companies.

Currently, the agent checks the **wrong period** — it looks at the current quarter instead of the previous one. Since companies submit data *after* a quarter ends (not during it), the agent misses valid submissions entirely.

This redesign introduces a **look-back window** so the agent checks the correct period at the right time.

---

## 2. User Stories

1. **As a fund manager,** I want the agent to check whether Q2 data has been submitted starting 15 days after Q2 ends, so companies have time to prepare their submissions before being flagged.

2. **As a fund manager,** I want the agent to automatically stop sending reminders after 60 days, so companies aren't endlessly nagged.

3. **As a fund manager,** I want to manually run the agent for any past period, so I can spot-check historical submissions even after the window has closed.

4. **As a fund manager,** I want one consolidated reminder email per company listing all missing items, instead of separate emails for KPIs, valuations, and documents.

---

## 3. How It Works — Example

### Setup

A fund configures the Portfolio Company Agent with:
- **Reporting Period:** Quarterly
- **Start checking after:** 15 days
- **Stop checking after:** 60 days
- **Run frequency:** Weekly (set in Agent Schedule)

### What Happens After Q2 Ends (June 30, 2026)

| Date | What Happens |
|------|-------------|
| Jul 1–14 | Nothing. Companies are preparing their Q2 submissions. Agent waits. |
| Jul 15 | **Checking starts.** Agent runs for the first time. Looks at each company: do they have a KPI report, valuation, and documents for Q2 (April 1 – June 30)? Companies missing any items receive a reminder email. |
| Jul 22 | Agent runs again. Companies that submitted since last week are no longer flagged. Those still missing items get another reminder — but only for what's still missing. |
| Jul 29 – Aug 26 | Agent continues running weekly. Each run only reminds about items that are still outstanding. |
| Aug 29 | **Checking stops.** Last automated run. No more reminders after this. |
| After Aug 29 | The fund manager can still click "Run Now" on the dashboard and manually select a period to check. |

### Timeline Visualization

```
April 1          June 30         July 15                    August 29
  |---- Q2 2026 ----|              |---- CHECKING WINDOW ---|
  Companies submit                 Agent runs weekly,
  data for this                    checking: "Did you
  period                           submit your Q2 data?"
```

---

## 4. How the Agent Knows Which Period to Check

There are **two different things** happening — configuration (set once by the admin) and the actual data check (automatic).

### What the Admin Configures (Agent Edit Page)

The admin sets **rules** — how the agent should behave:
- **Reporting Period:** How often do companies report? (Quarterly, Monthly, etc.)
- **Start/Stop days:** When should checking begin and end after a period closes?

The admin does **not** set a specific date like "June 30" here. The system computes the correct period automatically based on today's date and the reporting period setting.

### What the Agent Checks Automatically

When the agent runs, it auto-computes: "What is the most recently completed period?" Based on today's date:
- If today is July 21 and period = Quarterly → last completed quarter = Q2, ended June 30
- If today is November 5 and period = Quarterly → last completed quarter = Q3, ended September 30

It then queries: "Does this company have a KPI report with `as_of` date in that period's range?"

`as_of` is **not a setting** — it's a date that **already exists** on every KPI report and valuation in the system. When a portfolio company uploads their Q2 KPI report, they tag it with `as_of = June 30` (or any date within Q2). The agent simply looks for reports tagged within the period's date range.

### What the FM Selects on "Run Now" (Dashboard)

When running manually, the FM picks **which period-end to check** from a dropdown of past dates (June 30, March 31, December 31, etc.). This overrides the auto-computation — useful when:
- The automated window has closed (past T+60)
- The FM wants to re-check a historical period
- The FM wants to spot-check before the window opens

### Summary

| Where | What's Set | By Whom | Example |
|-------|-----------|---------|---------|
| Agent Edit Page | Rules: period, start/stop days | Admin (once) | Quarterly, T+15, T+60 |
| Agent Schedule | How often to run | Admin (once) | Weekly |
| Run Now dropdown | Which period to check (optional) | FM (each adhoc run) | Q2 - Jun 30, 2026 |
| KPI Report / Valuation | `as_of` / `valuation_date` | Portfolio company (when uploading) | June 30, 2026 |
| Agent logic | Auto-computes the period | System (automatic) | "Last completed quarter = Q2" |

---

## 5. Configuration — Agent Edit Page (Admin)

Three new dropdowns on the agent edit page:

```
┌─────────────────────────────────────────────────────────┐
│  Portfolio Company Agent Configuration                  │
│                                                         │
│  Reporting Period        [Quarterly         ▼]          │
│  Options: Monthly, Quarterly, Half-Yearly, Annually     │
│                                                         │
│  Start Checking After    [15 days           ▼]          │
│  (days after period end)                                │
│  Options: 7 days, 15 days, 30 days                      │
│                                                         │
│  Stop Checking After     [60 days           ▼]          │
│  (days after period end)                                │
│  Options: 30 days, 45 days, 60 days, 90 days            │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │ With these settings, for Q2 ending June 30:     │    │
│  │   • Agent starts checking: July 15              │    │
│  │   • Agent stops checking: August 29             │    │
│  │   • Data checked: April 1 – June 30             │    │
│  └─────────────────────────────────────────────────┘    │
│                                                         │
│  Run frequency is set in the Agent Schedule tab.        │
└─────────────────────────────────────────────────────────┘
```

The info box at the bottom updates dynamically as the admin changes selections, showing a real example of what the settings mean.

---

## 6. Dashboard — "Run Now" with Period Selection and Target Selector (FM)

The dashboard's "Run Validation" button includes two controls:
1. **Check period** — which reporting period to validate against
2. **Run on** — which companies to include in the validation run

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
│  │   Run on:                          │  │
│  │   [All Companies (20)          ▼]  │  │
│  │                                    │  │
│  │   Options:                         │  │
│  │     • All Companies (20)           │  │
│  │     • Selected Companies           │  │
│  │     • By Tag                       │  │
│  │     • By Sector                    │  │
│  │                                    │  │
│  │   [Run]                            │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ ✉ Send Reminders                  │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ 👁 View Pending Issues             │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

### Check Period Options

- **"Auto"** (default): Checks the most recently completed period — the system figures out the right one automatically
- Past periods are shown as options for historical checks
- The "Run Now" button works anytime — it is not restricted to the checking window

### Target Selector — "Run on" Options

Three Select2 multi-select dropdowns (Tags, Sectors, Companies) replace the old checkbox panels. All optional — leaving all empty runs on all companies. Tags + sectors are AND'd when both present; explicit company IDs are always additive.

### Skip Reminders Toggle

A checkbox in the Run Validation form: "Send reminders to companies with missing items" (unchecked by default). Only visible when the agent-level `send_kpi_reminder` setting is enabled. When unchecked, the `send_kpi_reminder` step is skipped entirely — the FM validates first, then decides whether to send reminders separately via the Send Reminders panel.

### Dashboard Scoping After Run

After the run completes, the dashboard stats and table show only **companies the agent has run for** (companies with a SupportAgentReport matching `last_run_target_ids`). A toggle bar at the top lets the FM switch between "Show last run (N)" and "Show all". When the FM runs on all companies, `last_run_target_ids` is cleared (nil) and no toggle bar appears — the dashboard shows everything.

---

## 7. Dashboard — Window Status Indicator

A status bar shown **at the top of the dashboard**, just below the title and above the stat cards. It tells the FM at a glance whether the automated checking window is active, upcoming, or closed.

### Where It Appears

```
┌──────────────────────────────────────────────────────────────────┐
│  Portfolio Company Dashboard                                     │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ 🟢 Active Window: Jul 15 – Aug 29 (Q2 2026, Day 6 of 45) │  │  ← THIS BAR
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  [Total Companies] [Validated] [Up to Date] [Not Yet Validated]  │  ← stat cards row 1
│  [KPI Not Submitted] [Valuation Missing] [Documents Missing]     │  ← stat cards row 2
│  [Chart]                    [Agent Actions]                      │  ← chart + actions
│  [Company Table]                                                 │  ← table
└──────────────────────────────────────────────────────────────────┘
```

### How the State Is Determined

The system always looks at the **most recently completed period's** window. Example with Period = Quarterly, T+15, T+60:

```
June 30          July 15    Aug 29         Sep 30          Oct 15    Nov 29
  |                |-----------|              |               |---------|
  Q2 ended         Q2 WINDOW                  Q3 ends         Q3 WINDOW

         ①              ②            ③                 ④           ⑤
      Before         Active        Closed           Before       Active
      Q2 window      Q2 window     Q2 window        Q3 window    Q3 window
```

| # | Today's Date | Most Recently Completed Period | Window | Condition | State |
|---|-------------|-------------------------------|--------|-----------|-------|
| ① | July 5 | Q2 (Jun 30) | Jul 15 – Aug 29 | Today < Jul 15 | **Not yet open** |
| ② | July 21 | Q2 (Jun 30) | Jul 15 – Aug 29 | Today between Jul 15 and Aug 29 | **Active** |
| ③ | Sep 5 | Q2 (Jun 30) | Jul 15 – Aug 29 | Today > Aug 29, Q3 not ended yet | **Closed** |
| ④ | Oct 2 | Q3 (Sep 30) | Oct 15 – Nov 29 | Today < Oct 15 | **Not yet open** |
| ⑤ | Oct 20 | Q3 (Sep 30) | Oct 15 – Nov 29 | Today between Oct 15 and Nov 29 | **Active** |

### Display for Each State

| State | Color | Display |
|-------|-------|---------|
| Active | Green | 🟢 **Active Window:** Jul 15 – Aug 29 (Q2 2026, Day 6 of 45) |
| Not yet open | Grey | ⏸ **Next Window Opens:** Jul 15 (Q2 2026, in 5 days) |
| Closed | Orange | 🟠 **Window Closed:** Aug 29 was the last day for Q2 2026. Next window opens Oct 15 (Q3). |

The "Closed" state includes a forward-looking hint so the FM knows when the next automated window will open.

---

## 8. Trigger Points — Where Can the Agent Be Run?

The agent can be triggered from three different places. Each has a different level of control:

### Overview

| # | Trigger Point | Where | Period Selection | Who Uses It |
|---|--------------|-------|-----------------|-------------|
| 1 | **Dashboard "Run Validation"** | Portfolio Company Dashboard (`/portfolio_company_dashboard`) | Period dropdown + target selector (all, selected, by tag, by sector) | FM doing detailed portfolio review |
| 2 | **Support Agent "Run Now"** | Support Agents index/show page (`/support_agents`) | No dropdown — always auto-computes the most recently completed period | Admin running a quick check |
| 3 | **Investor Page "Run Agent"** | Portfolio company detail page (`/investors/:id`) | No dropdown — always auto-computes, runs for that single company only | FM checking one specific company |

### Why No Dropdown on #2 and #3?

The Support Agent "Run Now" and Investor page buttons are part of the **generic support agent UI** — shared across all agent types (Deal, KYC, CashFlow, Portfolio Company, etc.). Adding a period dropdown there would mean putting agent-type-specific UI into a generic shared page.

The **Dashboard** is the dedicated, purpose-built view for portfolio company monitoring. That's where the FM goes for full control — period selection, window status, stat cards, company table, reminders. The other two buttons are convenience shortcuts that use sensible defaults (auto-computed period).

### Visual Summary

```
┌──────────────────────────────────────────────────────────────┐
│  1. DASHBOARD (full control)                                 │
│     /portfolio_company_dashboard                             │
│                                                              │
│     [Run Validation]  +  [Check period: Q2 - Jun 30 ▼]      │
│                       +  [Run on: All Companies ▼]           │
│     ✓ Period dropdown    ✓ Target selector                   │
│     ✓ Window indicator   ✓ Stat cards                        │
│     ✓ Company table      ✓ Send Reminders                    │
│     ✓ View Pending Issues                                    │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  2. SUPPORT AGENTS PAGE (quick trigger)                      │
│     /support_agents                                          │
│                                                              │
│     [Run Now]  → auto-computes period, runs all companies    │
│     No dropdown, no dashboard features                       │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  3. INVESTOR PAGE (single company)                           │
│     /investors/:id                                           │
│                                                              │
│     [Run Agent]  → auto-computes period, runs this company   │
│     No dropdown, step-by-step progress panel shown           │
└──────────────────────────────────────────────────────────────┘
```

---

## 9. Reminder Emails

### Recipients

Reminders are sent to the email addresses configured in the **KPI reminder email recipients** field on the agent edit page. This is a comma-separated list (e.g., `cfo@portco.com, ops@portco.com`). If left blank, no reminder emails are sent even when reminders are enabled.

Previously, reminders fell back to the fund entity's employees — this sent reminders to the FM's own team instead of the portfolio company's contacts.

### Per-Company Opt-Out

Individual portfolio companies can be excluded from reminders by setting the `skip_kpi_reminder` field to "Yes" on the Investor record. Use for sold, written-off, or companies who handle their own reporting.

### One Email Per Company

Each reminder is a single consolidated email listing everything that's missing:

**Example — all 3 missing:**
> Subject: Action Required: Missing KPIs, Documents, Valuations for Q2 2026
>
> The following items are pending for Q2 2026 (April – June):
> - KPI Report
> - Valuation
> - Documents
>
> Please submit at your earliest convenience.

**Example — only valuation missing:**
> Subject: Action Required: Missing Valuations for Q2 2026
>
> The following item is pending for Q2 2026 (April – June):
> - Valuation
>
> Please submit at your earliest convenience.

**No reminder sent** if the company has submitted everything.

### Reminder Frequency

Reminders are sent once per agent run. If the agent is scheduled weekly, companies receive at most one reminder per week. No duplicate reminders on the same day.

### Sending Reminders (Two Paths)

**Path 1 — During Agent Run:** The Run Validation form includes a "Send reminders to companies with missing items" checkbox (unchecked by default, only shown when agent-level `send_kpi_reminder` is enabled). If checked, reminders are sent as part of the agent pipeline for each company with missing items. If unchecked, the `send_kpi_reminder` step is skipped.

**Path 2 — Standalone Send Reminders:** The dashboard's Send Reminders panel expands inline (Bootstrap collapse) with:
- A Select2 search bar for finding companies
- A scrollable table showing all overdue companies with: checkbox (pre-selected), company name, issue count, and last-reminded date with days-ago display
- A "Select all" checkbox in the header (checked by default)
- Selecting/deselecting in the Select2 syncs with the table checkboxes and vice versa

Only the checked companies receive reminders when the "Send Reminders" button is clicked.

### Feedback After Sending

After clicking Send Reminders (from either button), the dashboard shows a clear message:
- **"Reminders sent to N companies."** — emails were queued successfully
- **"Reminders were already sent today. No new reminders sent."** — all companies were skipped (same-day dedup)
- **"N opted out of reminders."** — companies with `skip_kpi_reminder` set to Yes
- **"No recipient emails configured. Add recipients in the agent settings."** — `kpi_reminder_recipients` is blank
- **"No overdue companies to send reminders to."** — no companies have blocking issues

---

## 10. What the Agent Checks

For each portfolio company, the agent verifies three things for the selected period:

| Check | What It Looks For | How It Matches |
|-------|-------------------|----------------|
| **KPI Report** | A KPI report with `as_of` date within the period (e.g., April 1 – June 30 for Q2) | Any report in the range counts — doesn't need to be tagged with the exact period-end date |
| **Valuation** | A valuation with `valuation_date` within the period | Same range matching |
| **Documents** | Documents attached to the KPI report | Checked only if a KPI report exists |

### Edge Cases

| Scenario | Behavior |
|----------|----------|
| Company uploads Q2 data before June 30 (e.g., `as_of = June 30` uploaded on June 25) | Agent finds it — upload date doesn't matter, only `as_of` date |
| Company uploads Q2 data on July 10 with `as_of = June 30` | Agent finds it — `as_of` is within Q2 range |
| Company uploads data with `as_of = July 10` for Q2 work | Agent misses it — July 10 is Q3, not Q2. This is a data entry error |
| Company has no KPI report at all | Marked as missing. Documents check is skipped (documents attach to KPI reports) |

---

## 11. Validation Summary Email

After every adhoc (manual) run, the FM who triggered the run receives a validation summary email. This email serves as a **historical record** of that run's results — since the platform does not persist historical run data (reports are upserted per company), the email is the only snapshot of what was found at that point in time.

### What It Contains

1. **Banner** — "Portfolio Validation Summary" with tone (warning if issues, success if all clear)
2. **Overview Stats** — Companies Checked, Up to Date, Has Issues
3. **Missing by Type** — HTML bar chart showing counts per category (KPI, Valuation, and per-document-type like Financial Statement, Board Deck, etc.)
4. **Issue Breakdown** — Callout cards for KPI Not Submitted, Valuation Missing, Documents Not Uploaded (only categories with issues)
5. **Company Details** — Per-company table with columns: Company, Status, KPI (check/cross), Valuation (check/cross), Documents (check/cross or "--")
6. **Processing Errors** — If any companies failed to process, listed with error messages

### Key Behaviors

- **No dashboard links** — The dashboard shows live data that may change after the snapshot was taken. Including links would be misleading.
- **Documents column shows "--" when KPI not submitted** — When a company hasn't submitted KPIs, the document check is skipped (documents attach to KPI reports). Showing "--" instead of a check mark prevents the false impression that documents are OK.
- **Scheduled runs don't send this email** — Scheduled runs are silent by design. Only adhoc runs (dashboard, support agents page, investor page) trigger the summary.
- **Subject line** — `[Alert] Portfolio Validation — N companies checked` (if issues) or `[Summary] Portfolio Validation — N companies checked` (if all clear)

---

## 12. Benefits

1. **Correct period checking** — Agent validates the period companies are actually submitting for, not the current in-progress period
2. **Configurable timing** — Funds can set their own grace period (T+7, T+15, T+30) and deadline (T+30, T+60, T+90)
3. **Reduced noise** — Consolidated reminders instead of multiple emails; no reminders outside the window
4. **Manual flexibility** — "Run Now" works anytime for any period, not locked to the automated window
5. **Clear visibility** — Dashboard shows whether the window is active, upcoming, or closed
6. **Historical record** — Validation summary email after each manual run preserves a snapshot of results
7. **Targeted runs** — FM can run on specific companies, tags, or sectors instead of all-or-nothing
8. **Reminder control** — Skip reminders during validation, then send selectively via the per-company Send Reminders panel
