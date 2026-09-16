---
description: A specialized skill for onboarding agents to manage investor KYC lifecycles, verify documents using AI, and perform regulatory compliance analysis using SQLite and Pandas.
globs: app/packs/core/investor_kycs/**/*, app/packs/core/investors/**/*, app/packs/core/documents/**/*
---

# Investor Onboarding & KYC Management

## Core Directives
- **Zero-Tolerance for Placeholders:** Ensure no KYC fields contain "N/A", "Unknown", or other placeholders (e.g., "NA", "UNK", "TEST").
- **Data-Driven Compliance:** Monitor the onboarding funnel to identify and resolve systemic delays in verification and AML screening.

## 1. Onboarding Data Analysis (SQLite & Pandas)
Agents can analyze the onboarding health by querying the `investor_kycs`, `investors`, and `aml_reports` tables.

### Analysis Patterns:
```python
import pandas as pd
import sqlite3
from datetime import date

# Context: The agent uses the provided sqlite scratch file
conn = sqlite3.connect('onboarding_scratch.sqlite')

# 1. Onboarding KPIs (Verified, Unverified, Completed, Expired)
query_kpis = f"""
SELECT
    COUNT(*) as total_kycs,
    SUM(CASE WHEN verified = 1 THEN 1 ELSE 0 END) as verified_count,
    SUM(CASE WHEN verified = 0 THEN 1 ELSE 0 END) as unverified_count,
    SUM(CASE WHEN completed_by_investor = 1 THEN 1 ELSE 0 END) as completed_count,
    SUM(CASE WHEN expiry_date < '{date.today()}' THEN 1 ELSE 0 END) as expired_count
FROM investor_kycs
"""
df_kpis = pd.read_sql_query(query_kpis, conn)

# 2. Investor-Linked KYC Status (Relationship Analysis)
# This query identifies investors missing KYCs or with unverified KYCs
query_investor_kycs = """
SELECT
    i.investor_name,
    i.category as investor_category,
    ik.full_name as kyc_entity_name,
    ik.kyc_type,
    ik.verified,
    ik.completed_by_investor
FROM investors i
LEFT JOIN investor_kycs ik ON ik.investor_id = i.id
ORDER BY i.investor_name
"""
df_investor_status = pd.read_sql_query(query_investor_kycs, conn)

# 3. Document Consistency Heatmap Data
query_docs = """
SELECT
    ik.kyc_type,
    d.name as doc_label,
    COUNT(*) as total_uploads,
    SUM(CASE WHEN d.approved = 0 THEN 1 ELSE 0 END) as rejection_count
FROM investor_kycs ik
JOIN documents d ON d.owner_id = ik.id AND d.owner_type = 'InvestorKyc'
GROUP BY ik.kyc_type, d.name
"""
df_rejections = pd.read_sql_query(query_docs, conn)

```

## 2. Onboarding Visualization Strategy
The following charts are essential for tracking the onboarding pipeline, mirroring the platform's dashboard logic:

### Progress & Efficiency:
- **Onboarding Status Summary (Cards/Bar):** Visualizes counts for *Verified*, *Unverified*, *Completed*, and *Expired* KYCs.
- **KYC Conversion Funnel (Funnel Chart):** Tracks LPs from *Invited* -> *Form Completed* (`completed_by_investor`) -> *Docs Verified* (`verified`) -> *AML Cleared* (`aml_status`).
- **KYC Coverage by Investor Category (Stacked Bar):** Shows % of investors in each category (e.g., UHNW, Institutional) with *Verified* KYCs.
- **KYC Type Split (Donut/Bar):** Compares `Individual` vs. `Non Individual` onboarding progress.

### Compliance & Risk:
- **Expiry Risk (Timeline/Gantt):** Visualizes upcoming `expiry_date` for KYCs over the next 6 months.
- **Common Rejection Reasons (Pareto Chart):** Analysis of document rejection trends (e.g., "Blurry PAN", "Invalid Address Proof").

## 3. Onboarding Workflow Skills

### Field & Document Verification
- **Skill:** Execute a multi-step integrity check.
- **Procedure:**
    1. Check field completeness by filtering out invalid tokens like "N/A" or "UNK" from `InvestorKyc` attributes.
    2. Confirm visual content of PAN/ID matches the `owner_tag` using computer vision/LLM analysis.
    3. Cross-verify the `full_name`, `address`, and `PAN` against the `KycData` (CKYC/KRA) registry responses linked to the KYC record.

### Investor Onboarding Gap Analysis
- **Skill:** Identify investors who haven't started or completed their KYC.
- **Procedure:**
    1. Run the **Investor-Linked KYC Status** analysis pattern.
    2. Filter for investors where `kyc_entity_name` is NULL (no KYC record) or `completed_by_investor` is 0 (started but not finished).
    3. Generate a follow-up list for Relationship Managers (RMs) based on the `investors` table mapping.
