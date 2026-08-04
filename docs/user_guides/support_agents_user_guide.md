# Support Agents User Guide

Support Agents are AI-powered automation tools that run checks, extract data, generate reports, and send alerts on your behalf. Each agent targets a specific operational area — KYC, distributions, e-signing, data quality, deal management, and more — and can be triggered manually, from a portfolio company page, or on a recurring schedule.

**What they enable:**

- **Automated daily ops** — catch commitment overflows, stale valuations, and stuck e-sign requests without manual checks.
- **Consistent KYC verification** — validate every investor's documents and fields through the same pipeline every time.
- **Deal intelligence** — score investors, extract term sheet data, and surface stagnant deals automatically.
- **Board-ready briefings** — compare investor presentations across periods and generate grounded pre-board questions.
- **Configurable per entity** — each agent is configured independently; fields, schedules, and LLM models are all adjustable through the UI.

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Setting Up Agents](#2-setting-up-agents)
3. [Configuring LLM Keys](#3-configuring-llm-keys)
4. [Running an Agent](#4-running-an-agent)
5. [Scheduling an Agent](#5-scheduling-an-agent)
6. [Understanding Reports](#6-understanding-reports)
7. [Agent Reference](#7-agent-reference)
   - [KYC Onboarding Agent](#7-1-kyc-onboarding-agent)
   - [KYC Doc Extractor](#7-2-kyc-doc-extractor)
   - [Distribution Readiness Agent](#7-3-distribution-readiness-agent)
   - [E-Sign Monitor](#7-4-e-sign-monitor)
   - [Data Quality Agent](#7-5-data-quality-agent)
   - [Note Summarizer Agent](#7-6-note-summarizer-agent)
   - [Deal Management Agent](#7-7-deal-management-agent)
   - [Portfolio Scoring Agent](#7-8-portfolio-scoring-agent)
   - [Deals Report Agent](#7-9-deals-report-agent)
   - [Investor Presentation Analyst](#7-10-investor-presentation-analyst)
8. [FAQ](#8-faq)
9. [AI Governance & Compliance FAQ](#9-ai-governance--compliance-faq)

---

## 1. Prerequisites

### LLM API Keys

Agents that use AI (summaries, scoring, term extraction, presentation analysis) require at least one LLM provider key configured for your entity. See [Configuring LLM Keys](#3-configuring-llm-keys).

Agents that are fully deterministic — E-Sign Monitor, Distribution Readiness, Data Quality — work without any LLM key.

### Entity Flags

Each agent has a corresponding feature flag that must be enabled for your entity before the agent can run. Your CapHive administrator enables these from the Admin panel. If the "Run Now" button on an agent's page appears greyed out, the flag is not yet enabled — contact your administrator.

### Admin Role

Only users with the **Company Admin** role can set up, configure, and run agents.

---

## 2. Setting Up Agents

Navigate to **AI → Support Agents**.

Click **Setup All Agents** in the top-right header. A popup lists every agent that will be created or updated. Agents that are already fully configured are not touched. Click **Run Setup** to provision them.

This is idempotent — it is safe to run multiple times. Running setup after a platform update adds any newly available agents or configuration fields without overwriting anything you have already customised.

After setup, each agent appears as a card on the index page grouped by category (Ops, Finance, Portfolio, Onboarding).

### What Setup Creates

For each agent type included in the platform:

- A **FormType** record that holds the agent's configuration fields.
- The agent's **configuration fields** (e.g. checkboxes, text inputs) with default values.
- A **SupportAgent record** with the agent enabled and its default JSON configuration.
- A **schedule** where applicable (e.g. daily for E-Sign Monitor, monthly for Note Summarizer).
- **Seed files** where required (e.g. the default investor scoring rubric for Deal Management Agent).

### Verifying Setup — the Configuration Warning Banner

After setup, open each agent you plan to use and check its **General** tab. If anything the agent needs is missing or misconfigured, a **yellow warning banner** appears at the top of the page listing every problem in plain language — for example an unset check toggle, a missing email recipient, a fund without a required template, or a skill file that has not been uploaded.

Three rules of thumb:

- **A clean page means the agent is ready to run.** No banner, no known setup gaps.
- **Resolve every item in the banner before relying on the agent.** A run with unresolved items will either fail outright or — worse — silently skip the affected steps and still report success. The banner tells you which of the two will happen for each item.
- **An unset Yes/No toggle counts as "off", not "on".** If a toggle was never given a value (for example on an agent set up before that option existed), the step it controls is silently skipped. The banner flags every unset toggle; setting it explicitly to Yes or No clears the warning. An explicit **No** is respected as your choice and is never flagged.

Re-running **Setup All Agents** fills in most banner items automatically (missing fields, missing defaults, missing seed files). Items that depend on your data — recipients, fund templates, uploaded skill files — must be resolved by hand and the banner links out to where.

---

## 3. Configuring LLM Keys

Navigate to **AI → Support Agents → LLM Keys**.

Enter an API key for each provider you want to use. Keys are stored per entity — different entities can use different providers.

| Provider | Where to get a key | Agents that use it |
|---|---|---|
| **Google Gemini** | [aistudio.google.com](https://aistudio.google.com/app/apikey) | Presentation Analyst (default), any agent if set as default |
| **OpenAI** | [platform.openai.com](https://platform.openai.com/api-keys) | Any agent when set as default model |
| **Anthropic** | [console.anthropic.com](https://console.anthropic.com/account/keys) | Any agent when set as default model |
| **OpenRouter** | openrouter.ai → Keys | Any agent when set as default model (access to many models via one key) |

After adding a key, set the **Default LLM Model** to the model you want agents to use when no per-agent model is configured.

Each agent also has its own **AI Model** field (visible on the agent's detail page) which overrides the entity default for that agent specifically.

> **Tip:** Gemini Flash is recommended as the default — it has a 1M token context window, making it suitable for document-heavy agents like the Presentation Analyst and KYC Doc Extractor.

---

## 4. Running an Agent

### From the Agent's Show Page

1. Navigate to **AI → Support Agents** and click any agent card to open it.
2. On the **General** tab, click **Run Now**.
3. A progress panel appears inline showing each step as it completes.
4. When finished, a status badge (Completed / Partial / Failed) appears and links to the generated report.

> If **Run Now** is disabled (greyed out), the agent's entity flag is not enabled. Contact your administrator.

### From a Portfolio Company or Investor Page

Several agents can be triggered in context — from the record they operate on:

- **KYC Onboarding Agent** — from an InvestorKYC record page → Run KYC Agent.
- **Portfolio Company Agent** — from a Portfolio Company page → Misc → Run Portfolio Agent.
- **Portfolio Scoring Agent** — from a Portfolio Company page → Misc → Run Scoring Agent.
- **Note Summarizer Agent** — from an Investor page → Misc → Summarize Notes.
- **Deal Management Agent** — from a Deal page → Run Agent button.

Running in context processes only that one record and shows a real-time step-by-step progress panel.

### From the Execution History Tab

The **Execution History** tab on each agent's show page lists past runs with their status, start time, and duration. Click any row to inspect the report for that run.

---

## 5. Scheduling an Agent

1. Open any agent's show page and click the **Schedule** tab.
2. Set the **Frequency** (daily, weekly, monthly) and **Run At Time**.
3. Toggle **Enabled** on.
4. Configure notification preferences — who gets emailed on failure, partial success, or full success.
5. Save.

The scheduler runs in the background; you do not need to keep the page open. Scheduled runs create the same reports as manual runs and appear in Execution History.

Agents that don't have a schedule tab (e.g. KYC Doc Extractor, Portfolio Scoring Agent) are triggered by events or manually — they don't support recurring schedules.

---

## 6. Understanding Reports

Each agent run produces one or more **SupportAgentReport** records. Where to find them:

- **General tab → "View Report" link** — the most recent report for the agent as a whole.
- **Execution History tab** — all past runs; click a row to see the full report.
- **Category-specific tabs** — Portfolio Agent Reports, Scoring Reports, Deal Reports, Note Summaries — show reports grouped by the records they cover (portfolio companies, deals, investors).

### Report Status Badges

| Badge | Meaning |
|---|---|
| **Completed** | All steps finished with no blocking issues. |
| **Partial** | Some records were processed successfully; others had issues or were skipped. |
| **Failed** | The run encountered a hard error. Check the error message in Execution History. |
| **Pending** | The run is in the queue or currently executing. |

### Issues Within a Report

Each report contains a list of **issues** — individual findings from the agent's checks. Each issue has a severity:

| Severity | Meaning |
|---|---|
| **Blocking** | Something must be fixed before the operation (distribution, KYC, etc.) can proceed. |
| **Warning** | Something worth attention but not an immediate blocker. |
| **Info** | Informational — passed checks, notes, or context. |

---

## 7. Agent Reference

### 7.1 KYC Onboarding Agent

**Category:** Onboarding

Orchestrates a multi-step verification pipeline for each InvestorKYC record in the entity. Runs a fixed sequence of checks and supports both scheduled (daily/weekly) and event-driven execution (on new KYC upload or field update).

**Steps run per KYC record:**

1. Field Completeness — verifies all mandatory fields are populated.
2. Document Presence — checks required document types have been uploaded.
3. Document Validity — validates document content and labels against expected criteria.
4. Field-to-Document Consistency — ensures field values match the uploaded documents.
5. Expiry Status — flags documents nearing or past their expiry date.
6. Send Reminders — notifies investors about missing or expiring items.
7. Trigger AML — initiates AML screening automatically once all checks pass.

**Configuration fields:**

| Field | Description |
|---|---|
| Check KYC expiry status | When Yes, flags expired KYC records as blocking and records approaching expiry as warnings. |
| Expiry warning thresholds (days) | Comma-separated day counts, e.g. `60,30,15`. A warning is issued when the record expires within any of these thresholds. Leave blank to only flag already-expired records. |

---

### 7.2 KYC Doc Extractor

**Category:** Onboarding

Triggered automatically when an investor uploads a KYC document. Reads the document using the configured extraction rules, asks the LLM to extract specific field values (PAN number, address, full name), and pre-populates the KYC form so the investor only needs to review and confirm — not type everything manually.

**How it works:**

- Extraction rules are defined per KYC FormType (Individual / Non-Individual).
- Each rule specifies: the document label to read, the prompt to send the LLM, and which field to write the result into.
- Overwrite mode `blank_only` (default) only fills empty fields — it never overwrites data the investor has already entered. Set to `always` to overwrite regardless.

No configuration changes are needed after initial setup — the extraction rules are seeded automatically when you run **Setup All Agents**.

---

### 7.3 Distribution Readiness Agent

**Category:** Finance

Validates that all prerequisites are in place before a capital distribution payment is released. Runs against each CapitalDistribution in the entity and surfaces any blockers before funds are wired.

**Checks (each independently toggleable):**

| Check | What it verifies |
|---|---|
| Check investor KYC | Investor has a completed KYC record. |
| Check net payable computed | Distribution net payable amount has been calculated. |
| Check notices generated | Distribution notice documents have been generated. |
| Check notices approved | Generated notices are in an approved state. |
| Check bank details on file | Investor has valid bank account details recorded. |

All failing checks produce **Blocking** issues. The distribution is marked **Ready to Pay** only when all enabled checks pass.

---

### 7.4 E-Sign Monitor

**Category:** Ops

Monitors the e-signature pipeline daily. Surfaces documents that have been stuck in "requested" state beyond the configured threshold, and flags voided or expired e-sign records for manual re-initiation. Sends an email summary to the ops team — no documents are automatically resent.

**Configuration fields:**

| Field | Description |
|---|---|
| Send e-sign reminders | When Yes, surfaces documents past the reminder threshold in the report. |
| Flag expired/voided documents | When Yes, includes expired, cancelled, or voided documents in the report. |
| Reminder after (days) | Days a document may remain in "requested" state before appearing in the report. Default: 3. |

**Recommended schedule:** Daily at 08:00.

---

### 7.5 Data Quality Agent

**Category:** Ops / Finance

Runs nightly data integrity checks across each fund and produces a health score (percentage of active checks passing) plus a fix-it list emailed to configured recipients.

**Checks (each independently toggleable):**

| Check | What it verifies |
|---|---|
| Check commitment overflows | Any LP whose total called amount exceeds their commitment. |
| Check missing/stale valuations | Portfolio companies with no valuation updated within N days. |
| Check stale FX rates | Currencies whose exchange rate has not been updated within N days. |

**Configuration fields:**

| Field | Description |
|---|---|
| Stale valuation threshold (days) | Default: 90. Adjust to match your valuation cadence. |
| Stale FX rate threshold (days) | Default: 30. Match to your FX data provider's update frequency. |
| Email quality report after each run | When Yes, emails the health score and fix-it list after every run. |
| Report recipient email(s) | Comma-separated email addresses. Leave blank to send to all active entity employees. |

**Recommended schedule:** Daily at 01:00.

---

### 7.6 Note Summarizer Agent

**Category:** Portfolio

Generates an LLM summary of investor notes on a monthly or quarterly schedule. Processes each investor in the entity, collecting notes within the configured lookback window, and produces three sections per investor: Key Themes, Action Items, and Relationship Status.

**Steps:**

1. Auto-Tag Notes — untagged notes in the period are tagged by the LLM in one batch call.
2. Collect Notes — notes within the period are gathered, filtered by tag if configured.
3. Generate Summary — LLM produces Key Themes, Action Items, and Relationship Status.
4. Save Note — summary is written back as a Note tagged `summary` on the investor record.
5. Save Report — persists the summary as a SupportAgentReport visible on the Note Summaries tab.

Investors with zero qualifying notes in the period are skipped at zero LLM cost.

**Configuration fields:**

| Field | Description |
|---|---|
| Summary period | `Month` = previous calendar month; `Quarter` = previous calendar quarter. |
| Tag filter | Comma-separated tags to restrict which notes are collected, e.g. `call,meeting`. Leave blank for all notes. |
| Auto-tag untagged notes | When Yes, untagged notes are sent to the LLM for tag assignment before summarising. |
| Available tags (vocabulary) | Comma-separated tags the LLM must choose from when auto-tagging, e.g. `call,meeting,kpi,board-meeting`. Leave blank for free-form tagging. |

**Recommended schedule:** Monthly on the 1st at 06:00.

---

### 7.7 Deal Management Agent

**Category:** Portfolio / Finance

Monitors the health of a single deal with six independently-toggleable capabilities. Designed to run weekly per deal or on-demand when you need a pipeline snapshot.

**Capabilities:**

| Capability | What it does |
|---|---|
| Check deal progress | Flags investors with no update or activity completion within N days as stagnant. Surfaces overdue DealActivity steps. |
| Check document checklist | Verifies that each document name in "Required documents" is present in the deal data room (case-insensitive). |
| Extract deal terms | Sends all data-room documents to the LLM and extracts structured terms (valuation, instrument, closing date, etc.). Cached — only re-runs when documents or the prompt change. |
| Summarize investor notes & docs | Produces a three-section summary (Key Themes, Action Items, Investor Engagement) per active investor from their document folder and completed activity attachments. |
| Score investors | Scores each active investor 0–100 using the uploaded Scoring Skill File as the rubric. Scores are written back to the DealInvestor record. |
| Send email digest | Sends a pipeline summary email after every run covering overdue activities, document gaps, and investor scores. |

**Configuration fields:**

| Field | Description |
|---|---|
| Stagnant threshold (days) | Investors with no update within this many days are flagged. Default: 14. |
| Required documents | Comma-separated document names that must be present in the data room, e.g. `NDA, Term Sheet, Pitch Deck`. |
| Term extraction prompt | Custom instructions for term extraction. Leave blank to extract common deal terms automatically. |
| Note period | `Month` or `Quarter` — lookback window for investor document and note collection. |
| Scoring Skill File | Upload a .txt or .md file defining your scoring rubric (5 dimensions, 0–20 each = 100 total). A default rubric is uploaded by Setup. |
| Min bullet points per section | Minimum bullet points per scoring dimension. Default: 3. |
| Notify email | Email address for the post-run pipeline digest. Leave blank to suppress outbound email. |

---

### 7.8 Portfolio Scoring Agent

**Category:** Portfolio

Scores each portfolio company using sector-specific LLM skill prompts. Gathers documents, KPI data, and valuations as context, then asks the LLM to produce a structured investment score with an overall score (0–100), grade, summary, and per-dimension breakdown.

**Steps:**

1. Load Skill — finds the skill prompt file matching the company's sector (or falls back to the Generic Portfolio Skill).
2. Gather Data — collects all documents (PDF, XLSX, PPTX, DOCX, TXT, CSV), KPI reports, and valuations.
3. Generate Score — sends context and skill prompt to the configured LLM.
4. Store Score — persists the structured score to the investor record and saves a SupportAgentReport.

Companies without a sector are skipped — a sector must be set to match a skill prompt.

**Configuration fields:**

| Field | Description |
|---|---|
| Generic Portfolio Skill | Fallback skill prompt file used when no sector-specific skill matches. |
| Sector-specific skill files | Upload additional skill files for specific sectors (e.g. Beauty & Skincare). The filename is matched against the portfolio company's sector field. |
| KPI frequency filter | Restricts which KPI report periods are sent as context. `All` includes every period type. |
| Documents from last N KPI reports | Number of the most recent Actual KPI periods from which to pull attached documents. Default: 1. |
| Document name filter | Comma-separated document names to include. Leave blank to send all documents from the selected reports. |
| Min points per section | Minimum bullet points per scoring dimension. Default: 3. |

**Tip:** To add a sector-specific skill, go to the agent's edit page and upload a `.md` or `.txt` file in the matching skill field. The file should define your scoring criteria for that sector.

---

### 7.9 Deals Report Agent

**Category:** Finance

Iterates over all open deals (or a configured subset) and produces a detailed fundraising status report per deal. Includes targets vs committed amounts, fill rate, activity step distribution, top investors, and staleness detection.

Results are saved as SupportAgentReport records per deal and an email summary is sent to configured recipients.

**Configuration (set via the agent's json_fields):**

| Field | Description |
|---|---|
| deal_ids | Comma-separated Deal IDs to include. Leave blank to process all Open deals. |
| report_recipients | Comma-separated email addresses for the summary email. |
| stale_days | Days without investor activity before a deal is flagged stale. Default: 30. |

Reports are visible on the agent's **Deal Reports** tab, grouped by deal.

---

### 7.10 Investor Presentation Analyst

**Category:** Portfolio

Reads investor presentations (PDF, PPTX, DOCX) attached to KPI reports across periods, extracts structured intelligence, compares across periods to surface commitment misses and dropped risks, and produces a pre-board briefing of 8–12 grounded questions plus a Management Accountability Score (0–100).

**Steps:**

1. Collect Presentations — finds KPI report documents matching the `presentation_doc_names` list.
2. Extract Intelligence — reads each document in full (Gemini Flash, 1M token context) and extracts 8 structured categories per period.
3. Cross-Period Analysis — compares all periods in one LLM call to produce five comparison lenses (commitment misses, dropped risks, metric anomalies, etc.).
4. Generate Briefing — produces 8–12 grounded pre-board questions. Cached when no new flags have appeared since the last run.
5. Score — computes the Management Accountability Score from the flags arithmetically (no additional LLM call).
6. Save — persists results to a SupportAgentReport visible on the Presentation Reports tab.

**Configuration fields:**

| Field | Description |
|---|---|
| Presentation document names | Comma-separated substrings matched against document names on each KPI report. Default: `Investor Update, Board Deck, Management Presentation, Quarterly Update, Investor Presentation`. |
| Max periods to analyze | Maximum number of the most recent KPI periods to include. Default: 8. |
| KPI report tag | Which KPI report type to scan. Default: `Actual`. |
| Comparison strategy | `all_periods` (one call, more accurate) or `sliding_window` (one call per adjacent pair, cheaper for many periods). |
| LLM model | Must support ≥500K token context. Default: `gemini-3-flash`. |

**Recommended schedule:** Monthly on the 1st at 06:00, so briefings are ready before board meetings.

**Note:** The chat panel can be enabled on this agent (Chat tab) to let fund managers ask follow-up questions about the analysis in natural language.

---

## 8. FAQ

**Q: The "Run Now" button is greyed out. What should I do?**
A: The agent's entity flag is not enabled. Contact your CapHive administrator to enable the corresponding feature flag for your entity in the Admin panel.

**Q: An agent run shows "Failed". How do I find out what went wrong?**
A: Open the agent's **Execution History** tab and click the failed run row. The error message is shown in the report. Common causes: missing LLM API key, no data matching the agent's targets (e.g. no open deals), or a misconfigured extraction rule.

**Q: I ran Setup All Agents but a specific agent doesn't appear.**
A: The agent's entity flag is not enabled — Setup creates the agent record but it won't appear in the regular index until the feature flag is on. Contact your administrator to enable it.

**Q: Can I change the LLM model for one agent without affecting others?**
A: Yes. Open the agent's show page, click **Edit**, and set the **AI Model** field. This overrides the entity default for that agent only.

**Q: How do I add a new sector skill to the Portfolio Scoring Agent?**
A: Open the Portfolio Scoring Agent's **Edit** page. Scroll to the skill file fields. Upload a `.md` or `.txt` file in the field matching your sector name. If no matching sector field exists yet, contact your administrator — new sectors can be added as custom fields via Setup.

**Q: The Note Summarizer ran but some investors show "skipped". Why?**
A: Investors are skipped when they have zero qualifying notes in the lookback period. This is by design — no LLM call is made, so there's no cost. To see all investors including skipped ones, open the **Note Summaries** tab on the agent page.

**Q: Can I run Deal Management Agent for all deals at once?**
A: Deal Management Agent runs per deal (scoped to one deal's data room and investors). To process all deals, use **Deals Report Agent** instead — it iterates over all open deals automatically and produces a consolidated fundraising report.

**Q: The Presentation Analyst found no documents. What should I check?**
A: Verify that presentation documents are attached to KPI reports (not just to the portfolio company directly). Check that the document names contain one of the substrings in the **Presentation document names** field (case-insensitive). The default list includes: `Investor Update`, `Board Deck`, `Management Presentation`, `Quarterly Update`, `Investor Presentation`.

**Q: Is it safe to run Setup All Agents again after adding a new agent?**
A: Yes — setup is idempotent. It only creates what's missing and merges new configuration keys without overwriting existing values. You can run it after every platform update to pick up new agents and fields.

**Q: How do I prevent an agent from sending emails during a test run?**
A: Set the agent's email/recipient field to a test address before running, or temporarily disable the send_report / notify_email field. For entity-wide email suppression during testing, enable **Sandbox Mode** in Entity Settings — all emails will route to the sandbox address instead.

---

## 9. AI Governance & Compliance FAQ

Answers to the AI governance and security questions most commonly asked during client due diligence.

**Q: Does the application use AI / LLM technology?**
A: Yes. The platform is multi-LLM and supports all major providers: OpenAI (GPT-5 family), Anthropic (Claude family), Google Gemini, and — via OpenRouter — many additional models including Qwen, DeepSeek, Kimi, and MiniMax. API keys are configured per client entity, and each agent can be pinned to a specific model. Several agents (E-Sign Monitor, Distribution Readiness, Data Quality) are fully deterministic and use no LLM at all.

**Q: Provide a high-level description of the AI technology.**
A: The platform provides Support Agents — AI-powered automation tools used across the platform to run checks, extract data from documents, generate summaries and scores, and send alerts. Each agent targets a specific operational area (KYC, distributions, e-signing, data quality, deal management, portfolio analysis). See the [Agent Reference](#7-agent-reference) in this guide for a full description of each agent.

**Q: Are there documented escalation procedures for legal or compliance violations?**
A: Yes. Any event in which the AI is abused, manipulated, or has its security controls circumvented is treated as a security incident under our documented Cybersecurity Risk Management Policy and Security Event Review Methodology. Events are classified by severity (Critical / High / Medium / Low); Critical and High events are triaged within 24 hours, and every confirmed incident is documented with its timeline, impact, and remediation.

**Q: What is the risk classification in the event of the AI being abused, manipulated, or having its security controls circumvented?**
A: Such an event is classified under our standard four-tier severity scheme based on impact, with any cross-tenant data exposure or unauthorized privilege change treated as Critical. By design, however, the impact of AI manipulation is structurally bounded: all AI agents operate strictly within the authenticated user's tenant and role permissions, which are enforced by deterministic application-layer authorization outside the AI model — a manipulated model cannot grant itself access the user does not already have. All data gathering is performed by the application within the tenant's scope (the AI cannot query data belonging to another tenant), AI agents do not autonomously execute financial transactions or modify permissions, and all AI outputs are persisted as auditable reports subject to human review.

**Q: Is the AI assessed for bias?**
A: Not separately for the specific use cases within CapHive. The platform uses state-of-the-art foundation models from major providers, which undergo bias and safety testing in their respective labs. As an additional safeguard, we recommend manual review of all AI-generated output before it is acted upon.

**Q: Is there real-time human override of the decision process? And is this logged?**
A: Yes. An in-flight agent run can be cancelled at any time from the agent's page; the cancellation is logged in the run's report, including who cancelled it and when. In addition, AI-generated outputs such as investor scores and note summaries can be manually edited by an administrator after review, and every run — completed or cancelled — is retained in the Execution History audit trail.

**Q: Could the AI decision impact any individual(s)?**
A: Yes — for example, agents generate reports and scores for portfolio companies and investors. All AI output is decision support, not automated decision-making: nothing is auto-actioned against an individual, and we recommend manual review of all AI-generated output before accepting it.

**Q: Please provide a brief description of the decision making / decision support.**
A: Agents produce reports, scores, summaries, and alerts that support human decisions — flagging blockers before a distribution, surfacing stale data, scoring investors against a client-defined rubric, or generating pre-board briefing questions. The final decision in every case rests with the platform's human users. See the [Agent Reference](#7-agent-reference) for what each agent produces.

**Q: Is this clearly communicated to the users of the platform?**
A: Yes. This user guide describes every agent, what it does, and what it produces. Within the platform, each agent's page shows the AI model in use, its configuration, and its full run history, and AI-generated reports are clearly presented as agent output for review.

**Q: What is the highest sensitivity of data the AI will process (including prompts, files, logs, or generated outputs)?**
A: All the data of a tenant on the platform can potentially be used by the AI. However, every agent is disabled by default and is enabled only if requested by the client — and only for the specific agents the client deems appropriate, via per-agent feature flags. Further, because the platform is multi-LLM with per-tenant API keys, the client may choose an LLM provider that matches their own criteria for data privacy.

**Q: Does the system use any technology that could be seen as privacy intrusive (e.g. user tracking, profiling, recording, or targeting)?**
A: No. The platform does not track user behaviour, record users, or perform advertising-style profiling or targeting. Agent scoring features evaluate investors and portfolio companies against business rubrics defined by the client, produce transparent written justifications, and are subject to human review and manual override.
