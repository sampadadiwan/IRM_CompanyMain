# Portfolio Company Dashboard — User Guide

The Portfolio Company Dashboard is a visual compliance overview built into the Portfolio Company Agent's **Portfolio Agent Reports** tab. It shows at a glance how many companies have submitted their data, where the gaps are, and what needs attention — without scrolling through individual reports.

This guide covers the dashboard itself. For how the underlying agent works (what it checks, how to configure it, how to schedule it), see the [Portfolio Company Agent User Guide](portfolio_company_agent_user_guide.md).

## Table of Contents

1. [Accessing the Dashboard](#1-accessing-the-dashboard)
2. [Stat Cards](#2-stat-cards)
3. [Missing by Type Chart](#3-missing-by-type-chart)
4. [Agent Actions Panel](#4-agent-actions-panel)
5. [Company Table](#5-company-table)
6. [Searching Companies](#6-searching-companies)
7. [Filtering by Status](#7-filtering-by-status)
8. [Pagination](#8-pagination)
9. [Sending Reminders](#9-sending-reminders)
10. [Footer — Recommended Next Steps](#10-footer--recommended-next-steps)
11. [FAQ](#faq)

---

## 1. Accessing the Dashboard

1. Navigate to **AI > Support Agents**.
2. Open the **Portfolio Company Agent** card.
3. Click the **Portfolio Agent Reports** tab.

The dashboard appears once the agent has been run at least once and has report data. If no reports exist yet, the tab shows a message prompting you to run the agent.

---

## 2. Stat Cards

Five cards across the top of the dashboard provide an instant health check of your portfolio.

| Card | What it shows |
|------|---------------|
| **Total Companies** | How many portfolio companies your entity tracks |
| **Submissions Received** | Companies that have submitted data (fully or partially), shown as a count and percentage |
| **Fully Complete** | Companies with zero compliance issues — everything is submitted and current |
| **Pending Submissions** | Companies that haven't submitted anything at all |
| **Total Issues** | The sum of all blocking issues across every company |

**Clicking a stat card filters the company table** below it to show only the relevant companies. For example, clicking "Fully Complete" shows only companies with a green "Complete" status. Clicking "Total Companies" clears the filter and shows everyone.

After clicking a card, the table scrolls into view automatically so you can see the filtered results immediately.

---

## 3. Missing by Type Chart

A vertical bar chart on the left side of Row 2 shows how many companies have issues in each compliance category:

- **KPI** — companies with missing KPI submissions
- **Valuation** — companies with outdated or missing valuations
- **Per-document-type bars** — one bar for each document type your fund requires (e.g., "Financial Statement", "Board Minutes", "Cap Table")

This answers the question: **"Where is the biggest compliance gap?"** If the "Board Minutes" bar is the tallest, that's where most companies are falling behind.

The document bars are **dynamic** — they're driven by the File-type custom fields configured on your entity's KPI report form. If your fund tracks 3 document types, you'll see 3 document bars. If you track 1, you'll see 1.

---

## 4. Agent Actions Panel

The right side of Row 2 contains action buttons and a list of pending companies.

### Action Buttons

| Button | What it does |
|--------|-------------|
| **Run Validation** | Triggers the agent to check all portfolio companies for compliance. This is the same as clicking "Run Now" on the General tab. |
| **Send Reminders** | Sends KPI reminder emails to all overdue companies. See [Sending Reminders](#9-sending-reminders) for details. |
| **Generate Report** | Produces a quarterly compliance summary (future feature). |
| **View Pending Issues** | Filters the company table to show only companies with at least one blocking issue. |

### Pending Companies List

Below the buttons, a compact list shows the most overdue companies sorted by issue count (highest first). Each entry shows the company name, how many issues it has, and how many days since the agent last ran for that company. This is the "who do I call first?" shortlist.

---

## 5. Company Table

The full-width table at the bottom of the dashboard shows one row per portfolio company with the following columns:

| Column | What it shows |
|--------|---------------|
| **Company Name** | The portfolio company's name |
| **Status** | A color-coded badge — **Complete** (green), **Incomplete** (yellow), or **Pending** (red) |
| **KPI** | Green checkmark if KPIs are submitted for the current period; red X if missing |
| **Valuation** | Green checkmark if a current valuation exists; red X if missing or outdated |
| **[Document columns]** | One column per required document type. Green checkmark if uploaded; red X if missing. These columns are dynamic — they match the File-type fields configured on your KPI report form. |
| **Issues** | Total count of blocking issues for this company |
| **Last Updated** | When the agent last ran for this company |
| **Actions** | **Eye icon** — expand the row to see a detailed breakdown of all issues. **Chart icon** — navigate to the company's page. |

### Expanding a Row

Click the eye icon in the Actions column to expand a detail panel below the row. This shows the full list of KPI issues, document issues, and valuation issues with their severity levels — the same information you'd see in an individual report.

---

## 6. Searching Companies

The **search box** in the top-right of the table header lets you find a company by name. Start typing and the table filters to show only matching companies.

Search works **server-side** — it queries the database directly, so it works reliably even with hundreds of portfolio companies. The search runs automatically after you stop typing, or you can press Enter.

Search results **persist through pagination** — if you search for "Tiger" and there are multiple pages of results, navigating to page 2 still shows only companies matching "Tiger."

Search also **combines with status filters** — you can search within a filtered view. For example, filter to "Incomplete" status and then search for a company name to find it within that subset.

To clear the search, delete the text from the search box and press Enter.

---

## 7. Filtering by Status

There are two ways to filter the company table by status:

### Using Stat Cards

Click any stat card to filter the table. For example:
- Click **Fully Complete** to see only companies with a "Complete" status
- Click **Pending Submissions** to see only companies with a "Pending" status
- Click **Total Companies** to clear the filter and show all companies

### Using the Status Dropdown

The **status dropdown** next to the search box lets you filter by status directly: All Statuses, Complete, Incomplete, or Pending.

When a filter is active, a **"Filtered: [Status]"** badge appears in the table header along with a **Clear** button to reset the filter.

Filters persist through pagination and combine with search — filtering to "Complete" and then paging to page 2 still shows only complete companies.

---

## 8. Pagination

The table shows **10 companies per page**. When your portfolio has more than 10 companies, pagination controls appear below the table with:

- A "Showing X-Y of Z" count on the left
- Page number links on the right

Navigating between pages **stays within the tab** — the rest of the dashboard (stat cards, chart, action buttons) stays in place. Only the table updates.

Pagination preserves your current **search query** and **status filter**. If you've filtered to "Incomplete" companies and searched for "Capital," paging through results keeps both the filter and search active.

---

## 9. Sending Reminders

The **Send Reminders** button sends KPI reminder emails to all portfolio companies that are currently overdue (have a "blocked" status from the agent).

### How it works

1. Click **Send Reminders** in the Agent Actions panel.
2. A confirmation dialog appears showing how many overdue companies will be emailed. Click OK to proceed.
3. The system sends a KPI reminder email to each overdue company.
4. A flash message confirms how many reminders were sent.

### Deduplication

The system tracks when each company was last reminded. If a company has already received a reminder **today**, it is skipped — you can safely click the button multiple times without sending duplicate emails.

The confirmation message tells you how many were sent and how many were skipped: *"Reminders sent to 12 overdue companies. 3 already reminded today."*

### When the button is disabled

The Send Reminders button appears **disabled** (greyed out) when there are no overdue companies — meaning every company is either complete or hasn't been checked yet.

---

## 10. Footer — Recommended Next Steps

At the bottom of the dashboard, a footer section shows dynamic suggestions based on your current portfolio data:

- **Send reminder to X overdue companies** — with a "Send Now" button that triggers the same action as the Send Reminders button above
- **Review Y issues that need attention** — a count of total blocking issues across all companies
- **Last run timestamp** — when the agent last ran, shown with a green success indicator

---

## FAQ

**Q: The stat cards show different numbers than what I see in the table. Why?**
A: Stat cards always show totals across your **entire portfolio**. The table may be filtered by status or search — the stat card numbers don't change when you filter. This is intentional so you always have the full picture at the top while drilling into specifics in the table.

**Q: I searched for a company but nothing appeared. Is the search broken?**
A: The search matches on **company name only**. Make sure you're searching by the company's name as it appears in the "Company Name" column. The search is case-insensitive and matches partial names (searching "tig" will find "Tiger Global").

**Q: The document columns are missing from the table. How do I get them?**
A: Document columns are driven by **File-type custom fields** configured on your entity's KPI report form. If no File-type fields are configured, no document columns appear. Ask your administrator to set up the required document types in the KPI report form configuration.

**Q: I clicked Send Reminders but the message says "0 sent." Why?**
A: Either all overdue companies were already reminded today (check the "X already reminded today" part of the message), or there are no overdue companies (the agent found no companies with a "blocked" status).

**Q: The chart looks squashed or doesn't show up properly.**
A: This can happen if you navigate away from the tab and come back quickly. Click another tab and return to the Portfolio Agent Reports tab — the chart re-renders automatically when the tab becomes visible.

**Q: Can I export the table data?**
A: Not yet. Exporting to Excel/PDF is planned for a future release.

**Q: How often should I run the agent to keep the dashboard current?**
A: That depends on your reporting cadence. Most funds set up a **daily schedule** so the dashboard reflects overnight submissions. You can also run it on-demand by clicking "Run Validation" whenever you want a fresh check.
