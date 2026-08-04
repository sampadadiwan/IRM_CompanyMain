# Portfolio Company Agent — Dashboard Redesign (Business Design)

## Purpose

The Portfolio Company Agent monitors portfolio companies for compliance — KPI submissions, document uploads, and valuation currency. The current "Portfolio Agent Reports" tab displays results as a plain table with expandable accordion rows. This redesign transforms that tab into a visually rich, demo-ready dashboard that communicates portfolio health at a glance and enables quick actions.

## Problem Statement

The current UI is functional but bland:

- Raw table with no summary stats — the fund manager must scan every row to understand overall health
- No visual charts — compliance status is buried in expandable text rows
- No quick actions — to run the agent, send reminders, or export reports, the user must navigate elsewhere
- Documents are shown as a single bucket — the fund manager cannot tell which specific document type is missing (Financial Statement vs Board Minutes vs Cap Table)
- Not suitable for client demos or investor presentations

## Revision History

| Date | Change | Reason |
|------|--------|--------|
| 2026-06-25 | Initial design | — |
| 2026-06-29 | v2 — Product feedback incorporated | Clickable stat cards, full-width table, dynamic document columns, decouple charts, remove insights/overdue sidebars |
| 2026-06-30 | v2.2 — Server-side pagination, search, send reminders | Pagy pagination (10/page), Ransack server-side search, Send Reminders implemented, stat card filtering via Turbo Frames |

## Target Users

- **Fund Managers** — daily users monitoring portfolio company compliance and data submissions
- **Operations team** — tracking overdue submissions and sending reminders
- **Sales/Demo team** — showcasing AI agent capabilities to prospective clients

## Dashboard Layout

### Row 1: Summary Stat Cards (Clickable)

Five cards across the top providing an instant health check. **Clicking any card filters the company table** to show only the relevant companies.

| Card | What It Shows | Click Action |
|------|--------------|-------------|
| Total Companies | Count of portfolio companies being tracked | Resets filter — shows all companies |
| Submissions Received | Companies that submitted data (full or partial), with percentage | Filters table to Complete + Incomplete companies |
| Fully Complete | Companies with zero compliance issues, with percentage | Filters table to "Complete" status only |
| Pending Submissions | Companies that haven't submitted anything | Filters table to "Pending" status only |
| Total Issues | Sum of all blocking issues across all companies | Filters table to companies with at least 1 issue |

Each card shows the number prominently with a small icon and a progress bar for percentage-based metrics.

### Row 2: Two Panels (50/50 split)

**Left Panel — Missing by Type (Bar Chart)**

A vertical bar chart showing how many companies have issues in each compliance dimension:

- **KPI** bar — e.g., "9 companies have missing KPI submissions"
- **Valuation** bar — e.g., "7 companies have outdated valuations"
- **Per-document-type** bars — one bar per configured document type, showing how many companies are missing that specific document

Example with 3 document types configured:
- KPI: 9
- Valuation: 7
- Financial Statement: 8
- Board Minutes: 12
- Cap Table: 5

This answers: "Where is the biggest compliance gap? Is it mostly KPIs or a specific document?" Helps the fund manager prioritize which type of follow-up to do first.

The document bars are dynamic — driven by the File-type custom fields configured on the entity's KPI report form. If the fund has 3 document types, there are 3 document bars. If 1, just 1 bar.

**Right Panel — Agent Actions + Pending Companies**

Top section: Four action buttons stacked vertically:

| Button | What It Does |
|--------|-------------|
| Run Validation | Triggers the agent to check all companies for compliance (existing batch run) |
| Send Reminders | Sends KPI reminder emails to all overdue companies. This is a manual "nudge" — the first reminder goes out automatically during the agent run, but this button re-sends only to companies that still haven't uploaded after X days |
| Generate Report | Produces a quarterly compliance summary and emails it |
| View Pending Issues | Filters the company table below to show only companies with issues |

Bottom section: A compact list of pending/overdue companies with issue counts. Shows the 5 most overdue companies. This is the "who do I call first?" shortlist.

### Row 3: Full-Width Company Table

The core of the dashboard. A searchable, filterable table with one row per portfolio company, spanning the full width of the page.

| Column | Content |
|--------|---------|
| Company Name | Name of the portfolio company |
| Status | Color-coded badge: Complete (green), Incomplete (yellow), Pending (red) |
| KPI | Green checkmark if submitted, red X if missing |
| Valuation | Green checkmark if current, red X if outdated |
| *[Document Type 1]* | Green checkmark if uploaded, red X if missing |
| *[Document Type 2]* | Green checkmark if uploaded, red X if missing |
| *[...additional document types]* | Dynamic — one column per configured File-type field |
| Issues Count | Total blocking issues for this company |
| Last Updated | When the agent last ran for this company |
| Actions | View details (expandable row), view company page |

**Document columns are dynamic** — driven by the File-type custom fields configured on the entity's KPI report form. One fund might see 2 document columns, another might see 5. Each column header shows the document type name (e.g., "Financial Statement", "Board Minutes", "Cap Table").

Table features:
- **Server-side pagination** — 10 companies per page, navigation stays within the table (no full page reload)
- **Search box** — filter by company name (server-side via Ransack, scales to 500+ companies)
- **Status filter dropdown** — show All / Complete / Incomplete / Pending (server-side via Turbo Frames)
- **Clickable stat cards** — clicking a stat card in Row 1 automatically filters this table
- Search and status filter are preserved when paginating — page 2 of "Complete" companies shows only complete companies

### Footer

- **Recommended Next Steps** — dynamic suggestions based on current data (e.g., "Send reminder to 5 overdue companies", "Review 11 issues that need attention") with action buttons
- **Last run timestamp** — "Last run: Jun 25, 2026 10:30 AM" with a green success indicator

## Removed from v1 Design

The following sections were in the initial design but removed based on product feedback:

| Section | Reason for Removal |
|---------|-------------------|
| **Portfolio Insights sidebar** (LLM-generated) | Product felt the data is already visible in the table; the insights were redundant |
| **Overdue Companies sidebar** | Info is now accessible via clickable stat cards (click "Pending Submissions" to filter) |
| **Portfolio KPI Charts section** (Row 4) | Charts are decoupled from this agent. Chart Agent will be a separate, independent agent — different use case, and coupling slows down the compliance run |
| **Automatic chart generation on agent run** | Same as above — running the portfolio agent no longer auto-triggers `AgentChartJob` |

## User Flows

### Flow 1: Morning Health Check
1. Fund manager opens the agent dashboard
2. Glances at stat cards — "8 of 16 complete, 28 issues"
3. Clicks "Pending Submissions" stat card — table filters to show only pending companies
4. Checks Missing by Type chart — "Board Minutes are the biggest gap with 12 companies missing"
5. Clicks "Send Reminders" — emails go to overdue companies

### Flow 2: Document Compliance Drill-Down
1. Fund manager wants to check Financial Statement compliance specifically
2. Looks at the bar chart — sees "Financial Statement: 8 companies missing"
3. Scrolls to full-width table — scans the "Financial Statement" column for red X marks
4. Identifies which specific companies are missing this document
5. Takes action — emails those companies directly or clicks "Send Reminders"

### Flow 3: Client Demo
1. Sales team shows the dashboard to a prospective client
2. Stat cards and bar chart demonstrate portfolio monitoring at a glance
3. Clicks stat cards to show interactive filtering
4. Full-width table shows per-document-type compliance with checkmarks/X marks
5. Action buttons demonstrate automated workflows (validation, reminders)

## Success Metrics

- Fund managers can assess portfolio health in under 10 seconds (stat cards)
- Per-document-type compliance visible at a glance (no more "Documents: X" bucket)
- Compliance follow-ups initiated directly from the dashboard (action buttons) rather than navigating to separate pages
- Stat cards are interactive — clicking filters the table, reducing clicks to drill down
- Demo-ready appearance — suitable for client presentations

## Phase 2 (Post-Launch)

| Feature | Notes |
|---------|-------|
| ~~Send Reminders button~~ | **Done (v2.2)** — sends KPI reminder emails to overdue companies, deduplicates (once per day) |
| ~~Pagination~~ | **Done (v2.2)** — Pagy server-side pagination, 10 per page, Turbo Frame navigation |
| Generate Report on email | Quarterly compliance summary PDF |
| Historical trend comparison | Current quarter vs. previous quarter compliance rates |
| Export Tracker (Excel/PDF) | Export the company table |
| Chart Agent as separate agent | Independent agent for KPI chart generation |
| Portfolio Insights (LLM) | Revisit if product wants AI-generated insights later |
