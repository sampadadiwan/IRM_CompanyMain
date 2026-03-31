---
description: A specialized skill for Investor Relations (IR) agents to manage LP satisfaction, track onboarding progress, and perform data analysis on investor interactions using the platform's SQLite reporting layer.
globs: app/packs/core/investors/**/*, app/packs/core/notes/**/*, app/packs/core/tasks/**/*, app/packs/funds/capital_commitments/**/*
---

# Investor Relations & Onboarding Management

## Core Directives
- **LP First:** Prioritize tasks and follow-ups requested by investors or linked to their satisfaction.
- **Institutional Memory:** Every significant interaction (call, meeting, email) must be logged as a `Note`.
- **Proactive Compliance:** Ensure KYC is updated before expiry to avoid transaction delays.
- **Data-Driven Insights:** Use Pandas and the SQLite scratch database to identify trends in onboarding and engagement.

## 1. Data Analysis with SQLite & Pandas
The platform uses a **Thread-Local Connection Injection** pattern for SQLite (see [`docs/sqlite_apprach.md`](docs/sqlite_apprach.md)). IR agents can perform high-performance analysis by querying `*Sqlite` models.

### Accessing Data:
```python
import pandas as pd
import sqlite3

# The agent receives a path to the sqlite file (e.g., from a background job or task context)
sqlite_path = "/path/to/scratch/investor_data.sqlite"
conn = sqlite3.connect(sqlite_path)

# 1. Onboarding Funnel Analysis
query_kyc = "SELECT onboarding_status, COUNT(*) as count FROM investor_kycs GROUP BY onboarding_status"
df_funnel = pd.read_sql_query(query_kyc, conn)

# 2. Time-to-Verify (Bottleneck Identification)
query_time = """
SELECT
    id,
    (julianday(verified_at) - julianday(completed_at)) as days_to_verify
FROM investor_kycs
WHERE verified_at IS NOT NULL AND completed_at IS NOT NULL
"""
df_timing = pd.read_sql_query(query_time, conn)
avg_verify_time = df_timing['days_to_verify'].mean()

# 3. Engagement vs. Commitment
query_engagement = """
SELECT
    i.investor_name,
    i.investor_access_count,
    SUM(cc.committed_amount_cents) / 100.0 as total_committed
FROM investors i
JOIN capital_commitments cc ON cc.investor_id = i.id
GROUP BY i.id
"""
df_engagement = pd.read_sql_query(query_engagement, conn)
```

## 2. Recommended Visualizations
To track onboarding and IR health, the following charts should be generated from the analyzed data:

### Onboarding Charts:
- **Onboarding Status Funnel (Stacked Bar):** Shows count of investors at each stage (Draft, Completed, Pending Docs, Verified).
- **Average Onboarding Days by Category (Bar Chart):** Compares how long it takes for UHNW vs. Institutional LPs to clear KYC.
- **Top 5 KYC Blocking Issues (Pareto Chart):** Visualizes the most common reasons for onboarding delays (e.g., "Missing PAN", "Blurry ID").

### IR Engagement Charts:
- **LP Interaction Heatmap:** Rows (Investors) x Columns (Weeks), showing frequency of `Notes` logged.
- **Task Aging Report (Histogram):** Distribution of how many days tasks have been "Incomplete".
- **Commitment vs. Collection Trend (Dual-Axis):** Total `committed_amount` vs. `collected_amount` over time.

## 3. IR Workflow Skills

### Monitoring LP Satisfaction
- **Skill:** Identify "At-Risk" LPs.
- **Procedure:**
    1. Query `investors` for those with `investor_access_count > 10` (high engagement) but `last_interaction_date > 30 days` (low outreach).
    2. Check `tasks` for any incomplete "Compliance" or "Finance" category tasks for these LPs.
    3. Draft a proactive check-in email referencing their recent activity.

### Tracking Follow-ups
- **Skill:** Ensure zero-drop follow-ups.
- **Procedure:**
    1. Scan `Note` content for keywords like "follow up", "send", "share", or "callback".
    2. Cross-reference with existing `Task` records in the `tasks` table.
    3. If no task exists, create one assigned to the IR head with a due date of `today + 2 days`.

