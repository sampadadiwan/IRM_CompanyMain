# Deal Weekly Summary — Business Design

## Purpose

The Deal Weekly Summary enhances the existing Deal Management Agent to send a weekly email summary of what changed in a specific deal during the past week. Instead of logging into the platform daily, the fund manager receives a concise email highlighting new additions, step movements, stagnation, status changes, and pending tasks — with clickable links to a full dashboard on the platform.

Each deal gets its **own agent** with its **own configuration**. If a fund manager has 3 active deals, they set up 3 agents — each with step presets and thresholds tailored to that deal's structure.

---

## Who Is This For?

Fund managers and deal teams who use the Deals module to track any kind of pipeline:
- **Fundraising** — tracking LP commitments toward a fund target
- **LP Onboarding** — tracking onboarding progress for new investors
- **Co-investments / Deal Deployment** — tracking potential companies for investment

Since each deal defines its own steps, the report adapts automatically to any use case.

---

## How It Works

### One Agent Per Deal

Each deal has its own Deal Management Agent instance. The fund manager configures it from the deal's **Agent Settings** tab:
- Which step transitions to highlight in the report
- Which status changes to track
- Stagnation threshold
- Email recipients
- Schedule (weekly, day of week, time)

### Weekly Email (Lightweight)

Every week, the fund manager receives a **short, colorful HTML email** for each configured deal. The email shows:

1. **Executive Summary** — a one-paragraph overview (e.g., "This week, 3 new investors were added to Fund II Raise. 5 moved from Outreach to First Call. 2 investors remain stagnant and 1 declined.")
2. **Key counts** — new investors, step transitions, stagnant count, status changes, task counts
3. **One highlighted overdue task** — the most critical overdue item with responsible person and due date
4. **AI Insight** (optional) — a one-liner actionable recommendation powered by AI

Every number in the email is **clickable** — clicking navigates to the deal's Weekly Summary tab on the platform.

### Full Dashboard (On Platform)

When the user clicks any link in the email, they land on a new **"Weekly Summary" tab** within the deal's detail page. This tab shows:

1. All the email sections with full detail (not just counts, but names and specifics)
2. Expandable tables showing which investors were added, moved, became stagnant
3. Charts — deal funnel, mix by source, mix by lead
4. Task detail tables with responsible person, due dates
5. Historical reports — ability to browse past weeks' summaries

---

## Report Sections

### Section 1: Executive Summary

A natural language paragraph summarizing the week's activity for this deal:

> "This week, 3 new companies were added to Fund II Raise. 8 investors advanced across stages. 5 remain stagnant, while 2 completed and 3 declined."

Also includes:
- Deal name and week date range
- Generation date
- "View Full Dashboard" CTA button → opens the deal's Weekly Summary tab

---

### Section 2: Deals Summary (three sub-panels)

#### Panel A — Overall Progress
- **New investors added** this week — count of DealInvestors created during the period
- **Step transitions** — investors who moved from one step to another, shown with actual step names:
  - "Outreach → First Call: 5"
  - "DD → Term Sheet: 2"
- The user **presets which step transitions** to show when configuring the agent. If a deal has 10 steps, the report only shows the transitions the user selected — avoiding clutter.
- If no presets are configured, all non-zero transitions are shown.

#### Panel B — Stagnant / Stuck Investors
Three-way breakdown comparing this week vs last week:
- **Previously stagnant, now active** — was stuck last week but has had activity since (positive signal)
- **Still stagnant** — was stuck last week, still no activity (ongoing concern). Shows "since DD Mon YYYY" indicating the date of their last activity.
- **Newly stagnant** — became stagnant this week (new concern). Shows "since DD Mon YYYY" indicating the date of their last activity.

The "since" date is computed as the most recent of: the investor record's last update, or their latest deal activity update. This gives the fund manager immediate context on how long each investor has been inactive.

Stagnation threshold is configurable per agent (default: uses the deal's existing `stagnant_days` config or 14 days).

#### Panel C — Status Changes (Preset)
- Which investors changed status during the week
- The user **presets which statuses** to track (e.g., "only show Declined and Active")
- Examples: "Companies moved to Active: 2", "Companies declined: 3"

All counts are clickable → navigate to the deal's Weekly Summary tab with the detail expanded.

---

### Section 3: Pending Tasks Summary

Tasks for this deal and its investors:

**Count cards:**
- **Overdue tasks** — past due date, not completed. Clicking "View details" expands a collapsible table inline.
- **Upcoming pending tasks** — due this week, not yet completed. Collapsible table inline.
- **Tasks completed this week** — marked done during the period. Collapsible table inline.

**Highlighted overdue task** — the most critical overdue item showing:
- Task name
- Responsible person
- Due date
- "View all overdue →" link to full tasks tab

**Collapsible detail tables** (expand inline on the dashboard, no page redirect):

Each table shows Task, Company, Responsible, Due Date columns. Maximum rows configurable (default 5). If there are more tasks than the max, a "View all →" link navigates to the deal's tasks tab.

The email shows the same count cards and highlighted task. Charts link to the dashboard for full detail.

---

### Section 4: Pipeline Overview (Charts) — Dashboard Only

These charts appear on the deal's **Weekly Summary tab** (not in the email). The email includes a "View your deal stats →" CTA link instead.

Charts available (user presets which to show):

- **Deal Funnel (By Current Stage)** — horizontal bar chart showing how many investors are at each step
- **Mix by Source** — donut chart showing investment amounts grouped by source (Referrals, Outbound, Events, etc.)
- **Mix by Lead** — donut chart showing investment amounts grouped by deal lead

These charts already exist on the deal's Charts tab. The Weekly Summary tab reuses the same data, snapshotted at report time.

---

### Section 5: AI Insight (Optional)

A one-liner AI-generated recommendation based on the deal's weekly data:

> "Focus on moving 4 investors from Diligence to IC — they've been stagnant for 12+ days."

Optional — enabled/disabled in agent settings. When enabled, the system makes one AI call per report.

---

## Configuration

The fund manager configures each deal's agent via the deal's **Agent Settings** tab. All settings are stored in the agent's `json_fields` (no migration needed).

### Core Settings

| Setting | json_fields key | Description | Default |
|---|---|---|---|
| **Report recipients** | `notify_email` | Email address to receive digest + weekly summary | — (required) |
| **Stagnation threshold** | `stagnant_days` | Days of no activity before an investor is flagged stagnant | 14 days |
| **Target deals** | `deal_ids` | Comma-separated deal IDs to monitor, e.g. `"10,12"`. Blank = all open deals | All open |

### Feature Toggles

| Setting | json_fields key | Description | Default |
|---|---|---|---|
| **Check progress** | `check_progress` | Detect stagnant investors and overdue activities | — |
| **Check documents** | `check_documents` | Verify required documents in the data room | — |
| **Extract terms** | `extract_terms` | LLM extraction of deal terms from data room documents | — |
| **Summarize notes** | `summarize_notes` | LLM summary of investor notes | — |
| **Score investors** | `score_investors` | LLM-generated investor scores (0–100) | — |
| **Weekly summary** | `weekly_summary` | **Master toggle** for the weekly summary email + dashboard | — |
| **AI Insight** | `enable_ai_insight` | AI-generated one-liner recommendation (requires `weekly_summary`) | — |

### Weekly Summary Settings (only active when `weekly_summary` = "Yes")

| Setting | json_fields key | Description | Default |
|---|---|---|---|
| **Report period** | `report_period` | Number of days to look back for changes | 7 |
| **Preset steps** | `preset_steps` | Step transition pairs to show, e.g. `"1-2,3-4"`. Blank = all non-zero | All |
| **Preset statuses** | `preset_statuses` | Status changes to highlight, e.g. `"Declined,Active"`. Blank = all | All |
| **Charts to show** | `preset_charts` | Charts to display: `"funnel,source,lead"`. Blank = all | All |
| **Max tasks in email** | `max_tasks_in_email` | Max task rows in overdue/pending/completed tables | 5 |

### Other Settings

| Setting | json_fields key | Description | Default |
|---|---|---|---|
| **Required documents** | `required_docs` | Comma-separated doc names to check, e.g. `"Term Sheet,KYC,NDA"` | — |
| **Term extraction prompt** | `term_extraction_prompt` | Custom prompt for LLM term extraction | Built-in |
| **Note period** | `note_period` | Period for document collection ("Month" or "Quarter") | Quarter |

### Minimum Config for Weekly Summary

To receive weekly summary emails, set at minimum:
1. `notify_email` — the recipient email
2. `weekly_summary` — set to "Yes"
3. `deal_ids` — the target deal(s)

Since each deal has its own agent, the step presets are specific to that deal's step structure. No ambiguity about which steps belong to which deal.

---

## User Journey

### Journey 1: Receiving the Weekly Email

1. Monday morning, fund manager receives **"Fund II Raise — Weekly Summary"** email
2. Sees: "3 new investors, 5 moved to First Call, 2 stagnant, 1 declined"
3. Clicks "Overdue Tasks: 2"
4. Browser opens → logs into Caphive → lands on **Fund II Raise → Weekly Summary tab**
5. Sees the full task table with overdue items, clicks into the specific task

### Journey 2: Checking the Dashboard Directly

1. Fund manager opens **Fund II Raise** deal page
2. Clicks the **"Weekly Summary"** tab (alongside Board, Grid, Charts, Activities, Settings)
3. Sees the latest weekly summary with all sections and charts
4. Can browse historical reports (previous weeks)

### Journey 3: Configuring the Report

1. Fund manager opens **Fund II Raise** → **Agent Settings** tab
2. Finds the Deal Management Agent configuration
3. Enables weekly summary features: sets recipients, picks step presets, configures stagnation threshold
4. Sets schedule (weekly on Monday at 8 AM)
5. Clicks **"Run Now"** to generate an immediate test report

### Journey 4: Multiple Deals

1. Fund manager has 3 deals: "Fund II Raise", "LP Onboarding Q3", "Co-Investment Pipeline"
2. Each deal has its own agent configured independently
3. Monday morning: receives 3 separate emails, one per deal
4. Each email links to its own deal's Weekly Summary tab

---

## Relationship to Existing Features

### DealManagementAgent (Enhanced — this feature)

The existing Deal Management Agent already monitors a single deal with:
- Stagnation detection (per-investor)
- Overdue activity detection
- Document checklist verification
- LLM term extraction from data room
- LLM investor scoring (0-100 with grades)
- Email digest

We add the weekly summary capabilities on top:
- Period-based delta computation (new investors, step transitions, status changes)
- Three-way stagnation breakdown (new vs still vs recovered)
- Task aggregation with detail
- Preset step/status configuration
- New lightweight email template
- New "Weekly Summary" tab on the deal page
- Optional AI insight

The existing deep-analysis features (scoring, term extraction, document checklist) remain available and independently toggleable. The weekly summary is an additional layer.

### DealsReportAgent (Unchanged)

The entity-level DealsReportAgent remains available for cross-deal fundraising snapshots if needed in the future. It is not part of this feature.

---

## Open Questions

1. **Preset steps format** — When configuring step presets, should the user select from a dropdown of the deal's actual steps, or type them manually? Dropdown is better UX since it pulls from the deal's templates.

2. **AI Insight** — Must-have for launch or later addition?

3. **Historical reports** — How many past weeks should the dashboard show? Last 4? Last 12?

4. **Email per deal vs consolidated** — If a fund manager has 3 deals, they get 3 separate emails. Should we offer a consolidated email option as a future enhancement?

5. **Stagnation threshold** — The existing DealManagementAgent already has `stagnant_days` config. We reuse it for the weekly summary. Is 14 days a good default?
