# PRD: Continuous Quality & Evaluation Loop for Domain Support Agents

**Status:** Draft
**Author:** Product
**Date:** 2026-06-23

---

## Contents

1. [Problem Statement](#1-problem-statement)
2. [Goals & Success Metrics](#2-goals--success-metrics)
3. [Who It's For](#3-whos-its-for)
4. [Scope — Which Agents](#4-scope--which-agents)
5. [The Three Failure Layers](#5-the-three-failure-layers)
6. [Worked Examples Per Agent](#6-worked-examples-per-agent)
7. [Functional Requirements](#7-functional-requirements)
8. [Non-Functional Requirements](#8-non-functional-requirements)
9. [Data Captured](#9-data-captured)
10. [Review Workflow](#10-review-workflow)
11. [Out of Scope](#11-out-of-scope)
12. [Open Questions](#12-open-questions)
13. [Acceptance Criteria](#13-acceptance-criteria)
14. [Implementation Phases](#14-implementation-phases)

---

## 1. Problem Statement

Caphive runs a family of domain-specific Support Agents — `CallNoticeAgent`, `KycOnboardingAgent`, `PortfolioScoringAgent`, `DealManagementAgent`, `NoteSummarizerAgent`, `RtaReconciliationAgent`, and others — that check, extract, score, and summarize fund-manager data, several with an LLM call inside one or more steps. Today, if such a step crashes, we know about it. If a step's LLM call returns a confidently wrong score, a missed inconsistency, or a dropped action item, **we have no way of knowing** — there is no mechanism anywhere in the codebase that captures whether an agent's output was actually correct, only whether it ran without raising.

This is a real and growing risk surface: these agents write decisions back into the system (KYC consistency flags, portfolio scores, extracted deal terms) that fund managers and ops staff act on directly. A silently wrong score or a missed document mismatch is indistinguishable today from a correct one — both show up as a "successful" step.

This PRD proposes a quality and evaluation loop for this agent family, calibrated to how they actually fail — which is materially different from how the existing chat-based agents (`CustomerSupportAgent` et al.) fail, since domain agents don't produce a conversational answer that a generic judge can score.

---

## 2. Goals & Success Metrics

### Goals

1. Every domain agent step that calls an LLM has its output's correctness tracked over time, not just its crash/non-crash status.
2. Schema-invalid LLM output (parses but fails validation) is tracked as its own category, separable from genuine crashes, and trendable per agent type.
3. Human corrections to agent output (a GP overriding a score, ops dismissing a flagged KYC issue) are captured as structured, queryable data — not lost as one-off UI actions.
4. Agents whose output should be stable for unchanged input (e.g. re-scoring the same portfolio company against the same documents) are checked for drift on a regular cadence, without requiring hand-labeled ground truth.
5. The highest-risk agents (those where a wrong output causes real harm — KYC consistency checks, deal term extraction) have a small hand-labeled golden set that runs before any change to their prompts, skill files, or tools.

### Success Metrics

| Metric | Target |
| :--- | :--- |
| Domain agent steps with LLM calls instrumented for schema-validity tracking | 100% |
| Agents with an override/correction action wired into their report UI | 100% of agents that persist a score, flag, or extracted value |
| High-risk agents (KYC consistency, deal term extraction) with a golden test set | 100% before any prompt/skill-file change ships |
| Drift-check coverage for scoring/extraction agents | 100% run on a recurring schedule against frozen fixtures |
| Correction-log items reviewed within SLA | 100% within 5 business days |

---

## 3. Who It's For

**Primary:** Caphive engineering — needs visibility into whether a prompt or skill-file change improved or degraded an agent's real-world accuracy before and after shipping it.

**Secondary:** Fund manager ops users and GPs who interact with agent output (KYC review queues, portfolio scoring panels, deal term extraction) — they are the source of the correction signal and the consumers of more trustworthy output.

**Not for:** Chat-based agents (`CustomerSupportAgent`, `LpAssistantAgent`, and other `GenericChatAgent`-based agents). Those already have a dedicated continuous-improvement design — see `docs/modules/ai/customer_support_agent/customer_support_agent_prd.md` §8 — built around judging free-text answers, which doesn't apply here.

---

## 4. Scope — Which Agents

All `SupportAgentService < Trailblazer::Operation` subclasses that are **not** `GenericChatAgent`-based:

`CallNoticeAgent`, `KycOnboardingAgent`, `KycDocExtractorAgent`, `PortfolioCompanyAgent`, `PortfolioScoringAgent`, `PortfolioReportAgent`, `DataQualityAgent`, `EsignMonitorAgent`, `DealManagementAgent`, `DealsReportAgent`, `DistributionReadinessAgent`, `NoteSummarizerAgent`, `PresentationAnalystAgent`, `RtaReconciliationAgent`.

Within this set, two sub-categories require different treatment:

| Category | Agents | LLM in the loop? | Primary risk |
| :--- | :--- | :--- | :--- |
| Deterministic checks | `CallNoticeAgent`, `DataQualityAgent`, `EsignMonitorAgent`, `DistributionReadinessAgent`, parts of `KycOnboardingAgent` | No | A rule itself regresses (code bug), not an accuracy problem |
| LLM-assisted extraction/scoring/summarization | `KycOnboardingAgent` (document validity), `PortfolioScoringAgent`, `DealManagementAgent`, `NoteSummarizerAgent`, `RtaReconciliationAgent`, `PresentationAnalystAgent`, `PortfolioReportAgent` | Yes | Confidently wrong output with no signal |

---

## 5. The Three Failure Layers

Every domain agent run can fail in three distinct ways. Today, only the first is captured.

| Layer | Description | Captured today? |
| :--- | :--- | :--- |
| 1. Crash | Exception during a step | Yes — `AgentExecutionLog` status/error_message, `SupportAgentReport` step status |
| 2. Schema-invalid output | LLM call returns malformed or incomplete structured output; the step catches the exception and reports it as a failure | Partially — visible per-run as a failed step, but not aggregated or distinguished from a true crash anywhere |
| 3. Confidently wrong output | The call succeeds, output validates, but the value is simply incorrect | Not captured at all |

Layer 3 is where real-world risk lives (a wrong KYC consistency verdict, an inflated portfolio score, a missed deal term), and it currently has zero supporting infrastructure. This PRD is primarily about closing that gap, with layer 2 visibility as a useful byproduct.

---

## 6. Worked Examples Per Agent

### `KycOnboardingAgent` — document validity check

Extracts field values from an uploaded KYC document and checks them against the corresponding DB fields. The two error directions are not symmetric: a **false negative** (says "consistent" when a PAN or address genuinely doesn't match) silently clears a KYC that should have been blocked; a **false positive** only creates an extra manual review. Today neither direction is tracked separately.

**Requirement:** a small hand-labeled fixture set of investor KYC + document pairs, some deliberately mismatched, run before any change to this agent's prompt or extraction logic. Recall on the deliberately-mismatched cases is weighted above precision.

### `PortfolioScoringAgent` — portfolio company scoring

Scores a portfolio company against a rubric loaded from a skill document. The cheapest high-value check here needs no ground truth at all: re-score the same company against the same frozen set of documents on a recurring cadence and flag if the score moves more than a defined threshold with no new documents introduced. A large swing signals the prompt, skill file, or underlying model changed — a drift alarm, not an accuracy judgment.

**Requirement:** a recurring drift check across a fixed panel of portfolio companies with frozen document snapshots.

### `DealManagementAgent` — deal term extraction

Extracts structured terms (valuation, round size, lead investor) from a term sheet. This requires actual ground truth: a small set of real term sheets with a human-confirmed set of expected field values, diffed field by field. Fields carry different severity — an incorrect valuation is a more serious error than a misspelled investor name — so scoring must be per-field, not a single pass/fail outcome.

**Requirement:** a hand-labeled golden set, scored per field, run before changes to the extraction prompt.

### `NoteSummarizerAgent` — note summarization

Summarizing free text is hard to grade with exact match, but doesn't require an LLM judge either. A structured (non-prose) list of expected action items per test investor allows grading by recall — did the summary surface every item on the list — which targets the real harm (a dropped action item) directly.

**Requirement:** structured expected-action-item lists per test fixture, graded by recall, not prose comparison.

### `CallNoticeAgent`, `DataQualityAgent`, `EsignMonitorAgent` — deterministic checks

No LLM involved. These are a standard regression-testing problem, already addressed by the project's existing Cucumber suite. The one gap worth closing: a **fire-rate monitor** in production — if a check's pass/fail rate moves sharply from its historical baseline (e.g. `verify_investor_kyc` suddenly blocking 40% of capital calls instead of its usual ~5%), that's almost always a code regression in the check itself, not a genuine spike in bad data, and nothing surfaces that today except a user complaint.

**Requirement:** a baseline-deviation alert on step pass/fail rates for deterministic agents.

---

## 7. Functional Requirements

### 7.1 Inference Logging

Every LLM call made inside a domain agent step must be logged individually (not just at the run level), capturing: which agent and step it belongs to, a reference to the input it was given, the raw model response, the parsed/validated result, whether schema validation passed, which model was used, and how long the call took.

### 7.2 Correction Capture

Every domain agent report screen that displays a score, a flagged issue, or an extracted value must offer a "this was wrong" action with a required free-text reason. Submitting it must be recorded as a structured, queryable correction — not just an audit-log line — so corrections can be reviewed and aggregated per agent type over time.

### 7.3 Drift Checking

For scoring/extraction agents, a recurring job must re-run a fixed panel of records against frozen input snapshots and compare new output to the previous run's output, alerting when the difference exceeds an agent-specific threshold.

### 7.4 Golden Test Sets

For the highest-risk agents (`KycOnboardingAgent` document validity, `DealManagementAgent` term extraction, and any agent added later with a similarly high cost-of-error), a hand-labeled set of 10–20 fixtures must exist and be runnable on demand, scored against expected output with per-field or per-case granularity as appropriate. Running this set must be required before any change to that agent's prompt, skill file, or extraction logic ships.

### 7.5 Baseline Deviation Alerts

For deterministic (non-LLM) agents, step-level pass/fail rates must be tracked against a rolling historical baseline, with an alert when the current rate deviates beyond a defined band.

### 7.6 Cross-Agent Visibility

A single view must show, per agent type: schema-validity failure rate, correction rate, drift-check status (where applicable), and golden-set pass rate (where applicable) — so a regression in any one domain agent is visible without checking each agent individually.

---

## 8. Non-Functional Requirements

- Inference logging must not materially increase latency on the agent's user-facing run (writes can be async/fire-and-forget).
- Correction capture must work for both web-triggered and scheduled/batch agent runs.
- Drift checks and golden test runs must not consume production LLM quota in a way that competes with live agent runs — they should run on a separate schedule/budget.
- All captured data must be queryable per `agent_type`, not siloed per individual agent implementation, so the cross-agent view (7.6) doesn't require bespoke code per agent.

---

## 9. Data Captured

Two new categories of record are needed, conceptually:

**Per-inference record** — one entry per LLM call made inside any agent step. Tracks: agent type, step name, a reference/fingerprint of the input, the raw and parsed output, a schema-valid flag, model used, latency, and cost. This is what makes layer 2 (schema-invalid output) trendable instead of buried in a free-text error message.

**Per-correction record** — one entry per human override of an agent's persisted output. Tracks: agent type, the report/issue being corrected, who made the correction, the reason given, and what the corrected value should have been (where applicable). This is the project's only source of real-world ground truth that doesn't require anyone to hand-build a fixture set — it accumulates automatically from normal usage once wired up.

Neither of these exists today. Today's `AgentExecutionLog` tracks run-level timing and crash status only; there is no override/dismiss action anywhere on `SupportAgentReport` for domain agents (that capability exists only inside the `customer_support_agent` pack, scoped to chat feedback).

---

## 10. Review Workflow

1. Corrections and schema-validity failures accumulate per agent type.
2. On a recurring cadence, the team owning each agent's domain (e.g. Risk & Compliance for `KycOnboardingAgent`, Ops for `CallNoticeAgent` and `DataQualityAgent`) reviews new corrections for that agent.
3. Recurring correction patterns (e.g. "scoring agent consistently overrates SaaS companies") get promoted into the golden test set so the same mistake is caught automatically before the next prompt change ships.
4. Drift alerts and baseline-deviation alerts are triaged like any other production alert — investigate whether the agent's logic, prompt, or underlying model changed, or whether the alert reveals a genuine and expected shift in the underlying data.

---

## 11. Out of Scope

- Chat-based agents (`CustomerSupportAgent`, `LpAssistantAgent`, and other `GenericChatAgent`-based agents) — already covered by a separate continuous-improvement design.
- Building golden test sets for every domain agent on day one — start with the highest-risk agents (KYC consistency, deal term extraction) and expand based on correction-log volume.
- Automated retraining or prompt auto-tuning — this PRD is about visibility and a human review loop, not closed-loop automated correction.

---

## 12. Open Questions

- Where should per-inference and per-correction records live — new tables, or folded into existing `SupportAgentReport.json_fields`? A dedicated table is queryable across agent types without parsing JSON blobs; reusing `json_fields` is cheaper to ship but harder to aggregate later.
- Who owns reviewing the correction log per agent — the domain team that owns that agent (Risk for KYC, Ops for call notices), or a single central "agent quality" reviewer across all of them?
- Should baseline-deviation thresholds for deterministic agents be one generic percentage band applied everywhere, or does each agent need its own baseline (a 5% KYC-block rate may be entirely normal; a 5% FX-staleness rate might not be)?
- How many golden-set fixtures are "enough" per high-risk agent before treating coverage as adequate, and who authors them — engineering, or the domain team?

---

## 13. Acceptance Criteria

- Every domain agent step that makes an LLM call produces a per-inference record with a schema-valid flag, queryable by agent type.
- Every domain agent report that persists a score, flag, or extracted value has a working correction action visible to the relevant user role.
- `KycOnboardingAgent`'s document validity check and `DealManagementAgent`'s term extraction each have a runnable golden test set with recorded baseline scores.
- `PortfolioScoringAgent` (and any other scoring/extraction agent in scope) has a recurring drift check against a frozen fixture panel, with alerting on threshold breach.
- A single dashboard view shows schema-validity failure rate, correction rate, drift status, and golden-set pass rate per agent type.
- At least one deterministic agent (e.g. `CallNoticeAgent` or `DataQualityAgent`) has a working baseline-deviation alert on step pass/fail rate.

---

## 14. Implementation Phases

**Phase 1 — Correction capture.** Wire the "this was wrong" action into `SupportAgentReport`-backed views for the agents that persist scores/flags/extracted values. Cheapest, highest-leverage: starts producing real labeled data immediately with no fixture authoring required.

**Phase 2 — Inference logging.** Instrument every domain agent's LLM-calling steps to log per-inference records, surfacing schema-validity failure rate per agent type for the first time.

**Phase 3 — Golden test sets for highest-risk agents.** Hand-build fixture sets for `KycOnboardingAgent` document validity and `DealManagementAgent` term extraction; require a passing run before shipping prompt/skill-file changes to those agents.

**Phase 4 — Drift checks.** Stand up the recurring frozen-fixture re-run for scoring/extraction agents (`PortfolioScoringAgent` first).

**Phase 5 — Cross-agent dashboard and baseline-deviation alerts.** Bring all four signal types together into one view; add fire-rate monitoring for deterministic agents.
