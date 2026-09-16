# AI Agents Roadmap

## Overview

This document proposes AI agents that could serve fund managers, risk & compliance, operations, and the CFO. Each agent is assessed for **buildability**: whether it can be coded as a reliable automation today, and where the honest blockers are.

The existing Support Agent Framework (`SupportAgent`, `SupportAgentReport`, `AgentSchedule`, ActionCable progress updates) is the assumed foundation. Six agents are already live in that framework — they are documented here for completeness and excluded from the roadmap.

---

## Already Built (Do Not Re-implement)

| Agent class | What it does | Type |
|---|---|---|
| `CallNoticeAgent` | 5-step checklist before sending a capital call (KYC, docs generated, docs approved, notification configured, ready-to-send) | Automation |
| `KycOnboardingAgent` | Multi-step KYC verification: field completeness, document presence, document validity, field-to-document consistency, AML screening trigger | AI (LLM for doc extraction) |
| `PortfolioCompanyAgent` | Monitors portfolio companies for KPI submission status, document presence, and valuation accuracy | Automation |
| `PortfolioReportAgent` | Generates and refines AI portfolio report sections from uploaded documents and web search context | AI (LLM) |
| `CashFlowAssistantAgent` | Calculates current cash positions across configured funds, checks data freshness, emails consolidated report | Automation |
| `FundStatsAgent` | Periodic fund statistics email: commitments, capital calls, portfolio investments, KYC counts, documents, stakeholder activity | Automation |

---

## Tier 1 — Buildable Now (Deterministic, All Data In-System)

These agents have no AI inference requirement and follow the same Trailblazer step pattern as the existing agents. See `docs/modules/ai/roadmap/ai_agents_implementation_plan.md` for detailed specs.

### KYC Expiry Alert — extension of `KycOnboardingAgent`
**Persona:** Risk & Compliance  
**Trigger:** Daily scheduled job  
**What it does:** Adds a `check_expiry_status` step and implements the existing stub `send_reminders` step. Flags KYCs expiring within 60/30/15 days and sends pre-warning emails with document upload links.  
**Not already covered:** `KycOnboardingAgent` validates document *content*. It has no expiry alerting and `send_reminders` is currently a no-op stub.

---

### Distribution Readiness Agent — new agent `DistributionReadinessAgent`
**Persona:** Ops  
**Trigger:** On-demand before finalising a distribution  
**What it does:** Validates that per-investor net payables are computed, fees are applied, distribution notices are generated and approved, and bank details are on file.  
**Why it's buildable:** Direct mirror of `CallNoticeAgent` — same step pattern, same `SupportAgentReport` persistence. `CapitalDistribution` and related records already hold all required data.

---

### KPI Collection Campaign — extension of `PortfolioCompanyAgent`
**Persona:** Ops  
**Trigger:** Scheduled at period start; escalating reminders at days 7, 14, 21  
**What it does:** Adds a `send_kpi_reminder` step that fires `EntityMailer.kpi_reminder` when `check_kpi_submission` finds a blocking issue. Escalation thresholds and last-sent tracking stored in `SupportAgentReport.json_fields`.  
**Not already covered:** `PortfolioCompanyAgent` detects missing KPIs but takes no outbound action. `KpiReminderJob` exists but has an empty body.

---

### Data Quality Agent — new agent `DataQualityAgent`
**Persona:** Ops  
**Trigger:** Nightly scheduled job  
**What it does:** Runs SQL integrity checks across each Fund — called capital exceeding commitment, missing valuations on portfolio companies, FX rates older than 30 days. Produces a health score and fix-it list per fund.  
**Why it's buildable:** Every check is a SQL query on existing tables. Output is a `SupportAgentReport` per fund.

---

### E-Signing Monitor — new agent `EsignMonitorAgent`
**Persona:** Ops  
**Trigger:** Daily scheduled job  
**What it does:** Finds documents with `esign_status: "requested"` sent more than N days ago, fires resend via the existing `resend_for_esign?` path, and flags expired/voided documents for ops review.  
**Why it's buildable:** `Document` already has `sent_for_esign`, `esign_status`, and `resend_for_esign?`. No new schema required.

---

## Tier 2 — Buildable With Caveats

These are mostly feasible but the deliverable is narrower than the name implies.

### Statement of Account Auto-Generator
**Persona:** Ops  
**Trigger:** Monthly/quarterly schedule  
**What it does:** Generates SoAs for every LP across all funds and queues them for review before portal delivery.  
**What is buildable:** SoA generation already exists. Scheduling and routing to a review queue is straightforward.  
**The caveat:** SoAs require a human approval step before LP delivery — a compliance expectation, not just UX. The agent saves preparation time but cannot remove the approval gate. The honest pitch is "no more manual triggering", not "fully automated".

---

### Concentration Risk Monitor
**Persona:** Risk & Compliance  
**Trigger:** After each new investment or valuation update  
**What it does:** Computes portfolio concentration by sector, stage, geography, and instrument after each change. Alerts if a single position exceeds a configurable % of NAV.  
**What is buildable:** Concentration percentages are SQL aggregations on existing data.  
**The caveat:** "Breaches diversification mandate" requires the mandate to be encoded as structured rules — most mandates live in the fund's LPA (PDF). Alerting on a configurable hard threshold (e.g., >25% in one sector) is buildable; validating against the actual LPA mandate is not without manual rule encoding per fund.

---

### LP Engagement Monitor
**Persona:** Fund Manager / IR  
**Trigger:** Weekly  
**What it does:** Flags LPs who have not engaged with the portal before an upcoming capital call.  
**What is buildable:** The concept is sound and the notification path exists.  
**The caveat:** Caphive does not currently instrument LP portal activity at the event level (page views, document downloads, assistant queries). The agent requires adding an audit/activity log to the investor portal first — a non-trivial instrumentation effort. Without that data, the agent can only flag LPs who have never logged in at all, which is a weak signal.

---

## Tier 3 — Not Reliably Automatable (Honest Blockers)

These agents sound compelling but have fundamental blockers that prevent reliable, unsupervised automation.

### Fee & Expense Audit Agent
**Persona:** CFO  
**Why it cannot be automated:** Management fee basis, carry thresholds, hurdle rates, and expense caps are defined per-fund in the LPA — a PDF legal document. These terms are not stored as structured data in Caphive. Until LPA terms are structured data (or manually encoded per fund), the agent can surface the raw numbers but cannot determine whether they are correct per the LPA.

---

### Cash Flow Forecasting Agent
**Persona:** CFO  
**Why it cannot be automated:** `CashFlowAssistantAgent` already covers current cash positions. A *forecast* additionally requires knowing when the GP plans to deploy capital — information that lives in the fund manager's head and deal pipeline probability estimates, not in structured fields. Committed-uncalled capital is already on the dashboard; calling it a "12-month forecast" would be misleading without a GP-input deployment schedule.

---

### Regulatory Reporting Agent
**Persona:** Risk & Compliance  
**Why it cannot be automated:** Regulatory filing formats (SEBI AIF reports, IFRS NAV disclosures, FATCA/CRS) are jurisdiction-specific, change periodically, and carry legal liability if filed incorrectly. An agent can assemble a draft but cannot own the submission without a licensed compliance officer sign-off and a maintained schema per regulation.

---

### AML / Adverse Media Monitor
**Persona:** Risk & Compliance  
**Why it cannot be automated:** Requires real-time access to external sanctions lists (OFAC, UN, EU) and adverse media databases (Refinitiv World-Check or similar) — none of which are in Caphive. Note that `KycOnboardingAgent` already triggers a basic AML screening step, but that is a pass/fail gate on a known list, not continuous monitoring. External adverse media monitoring requires a paid vendor, a legal liability framework, and a human adjudication workflow for every hit.

---

## Summary

| Agent | Persona | Tier | Type | Blocker |
|---|---|---|---|---|
| KYC Expiry Alert (extend `KycOnboardingAgent`) | Compliance | 1 — Build now | Automation | — |
| Distribution Readiness (new `DistributionReadinessAgent`) | Ops | 1 — Build now | Automation | — |
| KPI Collection Campaign (extend `PortfolioCompanyAgent`) | Ops | 1 — Build now | Automation | — |
| Data Quality Agent (new `DataQualityAgent`) | Ops | 1 — Build now | Automation | — |
| E-Signing Monitor (new `EsignMonitorAgent`) | Ops | 1 — Build now | Automation | — |
| SoA Auto-Generator | Ops | 2 — Caveats | Automation | Approval gate cannot be removed; saves prep time only |
| Concentration Risk Monitor | Compliance | 2 — Caveats | Automation | Mandate rules must be manually encoded per fund; LPA is a PDF |
| LP Engagement Monitor | Fund Manager / IR | 2 — Caveats | Automation | Requires new portal activity instrumentation first |
| Fee & Expense Audit | CFO | 3 — Blocked | Automation | LPA terms not structured data |
| Cash Flow Forecasting | CFO | 3 — Blocked | Automation | Deployment timeline not structured; `CashFlowAssistantAgent` already covers current positions |
| Regulatory Reporting | Compliance | 3 — Blocked | AI + Human | Jurisdiction-specific schema, legal liability, requires licensed sign-off |
| AML / Adverse Media | Compliance | 3 — Blocked | Automation + Ext. API | Needs external vendor, legal framework, human adjudication |
