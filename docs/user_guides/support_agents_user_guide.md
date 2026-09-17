# Support Agents User Guide

Support Agents are AI-powered automation tools that run checks, extract data, generate reports, and send alerts on your behalf. Each agent targets a specific operational area — KYC, distributions, e-signing, data quality, deal management, and more — and can be triggered manually, from a portfolio company page, or on a recurring schedule.

> **Where to find it:** Top-bar [**Company menu → Agents**](/support_agents); click an agent card to open it and use **Run Now** on its **General** tab, or **Setup All Agents** on the list page to provision every agent. Needs the **company_admin** role, and each agent must be enabled for your entity by CapHive support.

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
   - [Portfolio Assistant](#7-11-portfolio-assistant)
8. [Frequently Asked Questions](#8-frequently-asked-questions)
9. [Frequently Asked Questions: AI Governance & Compliance](#9-frequently-asked-questions-ai-governance-compliance)
10. [Related Guides](#10-related-guides)

---

## 1. Prerequisites

### LLM API Keys

Agents that use AI (summaries, scoring, term extraction, presentation analysis) require at least one LLM provider key configured for your entity. See [Configuring LLM Keys](#3-configuring-llm-keys).

Agents that are fully deterministic — E-Sign Monitor, Distribution Readiness, Data Quality — work without any LLM key.

### Entity Flags

Each agent has a corresponding feature flag that must be enabled for your entity before the agent can run. Only CapHive support can enable these; your own admins cannot switch them on. If the "Run Now" button on an agent's page appears greyed out and its **General** tab shows a red **Disabled** badge, the flag is not yet enabled — contact CapHive support.

### Admin Role

Only users with the **Company Admin** role can set up, configure, and run agents.

---

## 2. Setting Up Agents

Open the **Company menu** (house icon at the top right) and choose [**Agents**](/support_agents).

Click **Setup All Agents** in the top-right header. A popup lists every agent that will be created or updated. Agents that are already fully configured are not touched. Click **Run Setup** to provision them.

This is idempotent — it is safe to run multiple times. Running setup after a platform update adds any newly available agents or configuration fields without overwriting anything you have already customised.

After setup, every agent appears as a card on the index page grouped by category (Ops, Finance, Portfolio, Onboarding). Agents that CapHive support has not enabled for your entity still appear, with a **Disabled** badge on the card.

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

On the Support Agents page (**Company menu → Agents**), click **LLM Keys** at the top right. This opens the [**AI Provider Keys**](/support_agents/llm_keys) page.

Enter an API key for each provider you want to use. Keys are stored per entity — different entities can use different providers.

| Provider | Where to get a key | Agents that use it |
|---|---|---|
| **Google Gemini** | [aistudio.google.com](https://aistudio.google.com/app/apikey) | Agents on a Gemini model (the default model for new agents) |
| **OpenAI** | [platform.openai.com](https://platform.openai.com/api-keys) | Any agent whose **AI Model** is an OpenAI model |
| **Anthropic** | [console.anthropic.com](https://console.anthropic.com/account/keys) | Any agent whose **AI Model** is a Claude model |
| **OpenRouter** | openrouter.ai → Keys | Any agent whose **AI Model** is an OpenRouter model (access to many models via one key) |

After adding a key, click **Save Keys**. You can also set the **Default LLM Model**, which is used only when an agent has no model of its own.

Each agent also has its own **AI Model** field (visible on the agent's detail page), and every agent is created with one already filled in, so in practice this is the model the agent runs on. To switch an agent to a different provider, edit its **AI Model**.

> **Tip:** Gemini Flash is recommended as the default — it has a 1M token context window, making it suitable for document-heavy agents like the Presentation Analyst and KYC Doc Extractor.

---

## 4. Running an Agent

### From the Agent's Show Page

1. Open [**Company menu → Agents**](/support_agents) and click any agent card to open it.
2. On the **General** tab, click **Run Now** and confirm.
3. A progress panel appears inline showing each step as it completes.
4. When finished, the panel's status badge changes from the running step count to the outcome (for example **Ready ✓**, **Blocked ✗** or **Cancelled**), and the run is listed in **Execution History**.

> If **Run Now** is disabled (greyed out), the agent's entity flag is not enabled. Contact CapHive support.

### From a Portfolio Company or Investor Page

Several agents can be triggered in context — from the record they operate on:

- **KYC Onboarding Agent** — from a KYC record page → **KYC Actions** → **Run Kyc Onboarding Agent**.
- **Portfolio Company Agent** — from a Portfolio Company page → **Misc** → **Run Portfolio Company Agent**.
- **Portfolio Scoring Agent** — from a Portfolio Company page → **Misc** → **Run Scoring Agent**.
- **Note Summarizer Agent** — from a record's notes list → **Summarise Notes**.
- **Deal Management Agent** — from a Deal page → the agent card's **Run Now** button.

Running in context processes only that one record and shows a real-time step-by-step progress panel.

### From the Execution History Tab

The **Execution History** tab on each agent's show page lists past runs with their trigger (Manual or Scheduled), status, start time, and duration. Click the arrow at the end of a row to expand its details, such as the error message or what the agent found.

---

## 5. Scheduling an Agent

1. Open any agent's show page and click the **Schedule** tab.
2. Set the **Frequency** (daily, weekly, monthly, bimonthly, quarterly or half-yearly), **Run On**, **Run At** and **Timezone**.
3. Tick **Enable scheduled runs for this agent**.
4. Configure notifications — under **Notify When** tick **On Success**, **On Failure** and/or **On Partial Success**, and pick the **Notification Recipients**.
5. Click **Save Schedule**.

The scheduler runs in the background; you do not need to keep the page open. Scheduled runs create the same reports as manual runs and appear in Execution History.

Every agent has a **Schedule** tab, but Setup creates no default schedule for agents that are normally triggered by events or manually (e.g. KYC Doc Extractor, Portfolio Scoring Agent).

---

## 6. Understanding Reports

Each agent run produces one or more **SupportAgentReport** records. Where to find them:

- **General tab → progress panel** — appears after **Run Now** and shows the live status of that run.
- **Execution History tab** — all past runs; expand a row to see its details.
- **Category-specific tabs** — Portfolio Agent Reports, Scoring Reports, Deal Reports, Note Summaries — show reports grouped by the records they cover (portfolio companies, deals, investors).

### Report Status Badges

| Badge | Meaning |
|---|---|
| **Completed** | All steps finished with no blocking issues. |
| **Partial** | Some records were processed successfully; others had issues or were skipped. |
| **Failed** | The run encountered a hard error. Check the error message in Execution History. |
| **Queued / Running** | The run is waiting in the queue or currently executing. |

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

### 7.11 Portfolio Assistant

**Category:** Portfolio

A conversational assistant, not a scheduled checker — it answers questions about your portfolio companies on demand instead of producing a periodic report. Ask it about valuations, investment transactions, cap tables, KPIs, fund performance ratios, and documents, and it replies in plain language with tables, links back to the underlying records, and charts when you ask for one.

**Where to find it:**

- On the Investors index page, the chat bubble answers questions across your **entire portfolio** — e.g. "which companies had a valuation increase last quarter?" or "show total invested by company."
- On an individual portfolio company's page, the chat bubble is scoped to **that company only** — e.g. "summarize this company's performance" or "list its last 10 investment transactions."

**What it can answer:**

- Company lookups and details (sector, tags, city, primary contact).
- A quick financial snapshot for one company: total invested, current fair market value, latest valuation, and TVPI/RVPI.
- Valuation history and trends, including line/bar charts.
- Investment transaction history (buys, sells, conversions) and cap table ownership breakdowns.
- KPI trends (e.g. Revenue, EBITDA) — by default it looks at the last 12 months; ask for "all time" or a specific date range for longer history.
- Fund performance ratios (TVPI, RVPI, and similar multiples).
- Document lookup, including reading the content of a specific document to answer a question about it.

**Configuration fields:** none beyond the standard AI Model override — this agent has no report schedule or check toggles since it responds to questions rather than running checks.

**Tip:** Every record the assistant references links back to that record's page, so you can jump straight from a chat answer to the underlying valuation, investment, or document.

---

## 8. Frequently Asked Questions

### Navigation and getting there

**Where do I find Support Agents in CapHive?**
Click the house icon at the top right to open the **Company menu**, then choose [**Agents**](/support_agents). The page lists every agent as a card grouped by category (Ops, Finance, Portfolio, Onboarding), with a filter box to search by name, category or description.

**The Agents item in the Company menu is greyed out with a lock icon. Why?**
The menu item is locked when no support agent is enabled for your entity; hovering shows "AI Agents are disabled. Contact support to enable it". Agents are licensed per entity by CapHive, so contact CapHive support and name the agents you want. See [Entity Flags](#entity-flags).

**Who can see and use the Support Agents page?**
Only users with the **company_admin** role see your entity's agents; other employees get an empty list. Editing, running, scheduling and deleting agents all require **company_admin**, and **Setup All Agents** and **LLM Keys** are available to company admins and CapHive support. See [Admin Role](#admin-role).

**How do I open a single agent and what tabs will I see?**
On the [Support Agents](/support_agents) page, click the agent's card to open its page. Every agent has **General**, **Schedule** and **Execution History** tabs; some add their own report tabs, such as **Scoring Reports**, **Deal Reports**, **Note Summaries** or **Presentation Reports**.

**Where do I enter LLM API keys for agents?**
On the [Support Agents](/support_agents) page, click **LLM Keys** at the top right. This opens the [**AI Provider Keys**](/support_agents/llm_keys) page, where you enter a key per provider and pick the **Default LLM Model**. See [Configuring LLM Keys](#3-configuring-llm-keys).

**Can I run an agent from the record it works on instead of the agents page?**
Yes, for several agents. On a Portfolio Company stakeholder page, open **Misc** for **Run Portfolio Company Agent** or **Run Scoring Agent**; on a KYC record, open **KYC Actions** for **Run Kyc Onboarding Agent**; on a record's notes list, click **Summarise Notes**. A locked, greyed-out item means that agent is not enabled for your entity.

### Creating, updating and managing agents

**How do I create the agents for my entity?**
Go to [**Company menu → Agents**](/support_agents), click **Setup All Agents**, review the list of agents marked **New** or **Update**, and click **Run Setup**. This provisions every agent type the platform offers in one step. See [Setting Up Agents](#2-setting-up-agents).

**Can I add a single agent by hand instead of running setup?**
Yes. On the [Support Agents](/support_agents) page, open the **New Support Agent** dropdown and pick the agent type, fill in the form and save. The dropdown only lists agent types whose configuration forms already exist for your entity, so run **Setup All Agents** first if it is empty.

**How do I change an agent's settings?**
Open the agent, stay on the **General** tab and click **Edit**. You can change the name, description, category, **Enabled**, **Enable on Demand Run**, **Enable Chat Assistant**, **AI Model** and the agent-specific configuration fields described in the [Agent Reference](#7-agent-reference).

**How do I add, replace or remove an LLM API key?**
Open [**LLM Keys**](/support_agents/llm_keys) on the Support Agents page, type the new key into the provider's field and click **Save Keys**. Leaving a field blank keeps the existing key; tick **Remove** next to a provider to delete its key. A provider's models only become selectable once its key is saved.

**How do I schedule an agent to run automatically?**
Open the agent, go to the **Schedule** tab, tick **Enable scheduled runs for this agent**, choose **Frequency** (daily, weekly, monthly, bimonthly, quarterly or half-yearly), **Run On**, **Run At** and **Timezone**, and click **Save Schedule**. See [Scheduling an Agent](#5-scheduling-an-agent).

**How do I choose who is emailed about scheduled runs?**
On the agent's **Schedule** tab, under **Notify When** tick **On Success**, **On Failure** and/or **On Partial Success**, then pick users in **Notification Recipients** and click **Save Schedule**. By default failure and partial-success notices are on and success notices are off.

**How do I pause an agent without deleting it?**
To stop scheduled runs, untick **Enable scheduled runs for this agent** on the **Schedule** tab and save. The configuration, reports and execution history are kept, and you can still run it manually or re-enable the schedule later.

**How do I delete an agent?**
Open the agent and click **Delete** on the **General** tab, then confirm. Deletion only succeeds for an agent that has never run; once it has reports, execution logs or chat sessions, those records block the delete, so pause its schedule instead.

**How do I stop a run that is in progress?**
While a run's progress panel shows it as running, click **Cancel** in that panel. The button disappears once the run has finished, so a completed run cannot be cancelled.

**What permissions do I need and how do I get them?**
You need the **company_admin** role, which another company admin grants from [**Company menu → User**](/users) → open your user → **Edit** → **Roles**. The agent itself must also be enabled for your entity, which only CapHive support can do.

### Why use Support Agents

**Why should I use Support Agents instead of checking things manually?**
Agents run the same checks the same way every time, across every fund, investor, deal or KYC record, and on a schedule nobody has to remember. They catch problems such as commitment overflows, stale valuations, stuck e-sign requests or missing KYC documents before they block a distribution or a closing.

**What can Support Agents do for me?**
They verify KYC records, extract data from uploaded documents, check distribution readiness, monitor e-sign requests, score data quality, summarise investor notes, track deal pipelines, score portfolio companies and prepare pre-board briefings. Each one is described in the [Agent Reference](#7-agent-reference).

**Who typically uses Support Agents?**
Fund operations and compliance teams use the Ops and Onboarding agents for daily checks, finance teams use the distribution and data-quality agents before money moves, and investment teams use the Portfolio and deal agents for monitoring and board preparation. Setup and configuration is done by a company admin.

**What happens if I never set up LLM keys?**
Deterministic agents (E-Sign Monitor, Distribution Readiness, Data Quality) still run normally. Agents that summarise, score or extract data need a provider key and fail without one, showing the error in **Execution History**.

**Do agents make decisions or change my data on their own?**
Agents produce reports, scores and alerts for a person to act on; they do not move money, approve records or change permissions. A few write results back as designed: Note Summarizer saves a summary note, the scoring agents store scores, and KYC Doc Extractor fills empty KYC fields.

### What happens when I…

**What happens when I click Run Setup?**
CapHive creates any missing agent records (enabled, with the default AI model), their configuration fields and defaults, default schedules and seed files such as the scoring rubric. Values you already customised are never overwritten, nobody is notified, and it does not license agents for your entity.

**What happens when I click Run Now?**
After you confirm, the run is queued in the background and a progress panel shows each step, or a batch panel when the agent covers several funds or companies. A new entry appears in **Execution History** as a manual run, and the panel's status badge updates when it finishes.

**Who is notified when a manual run finishes?**
The user who clicked **Run Now** gets an in-app alert when the run completes or fails, and batch runs with failures also email the failure details to that user. Agents that send their own emails, such as the Data Quality report or the Deal Management digest, send them to the recipients configured on the agent.

**What happens when I save a schedule?**
CapHive checks for due schedules every 10 minutes and starts the agent at the next matching **Run At** time; a schedule is skipped while a previous run is still in progress. Each run is logged in **Execution History** as scheduled and retried per **Retry on Failure** and **Retry Interval**.

**Who is notified about scheduled runs?**
Only the users in **Notification Recipients**, by email and as an in-app notification, and only for the outcomes ticked under **Notify When**. If the recipient list is empty, no one in your team is notified; CapHive support may still get an internal error report.

**What happens when I save LLM keys?**
The keys and **Default LLM Model** are saved for your entity and used by the next agent run; runs already in progress are not affected. Agents with their own **AI Model** keep using that model instead of the default.

**What happens when I edit an agent's configuration?**
The change applies from the next run, whether manual or scheduled; existing reports keep the results they were produced with. The configuration warning banner on the **General** tab is re-checked each time you open the page. See [Verifying Setup](#verifying-setup-the-configuration-warning-banner).

**What happens when I cancel a run?**
The run's report is marked **Cancelled** (stored as failed), recording who cancelled it and when. Cancel does not stop the background job, so remaining steps can still run and nothing already written or sent is undone; review the records the run touches.

**What happens when I delete an agent?**
The agent and its schedule are removed and it disappears from the [Support Agents](/support_agents) page. This cannot be undone, but running **Setup All Agents** again recreates the agent with default settings, not your old configuration.

**What happens if a Yes/No setting on an agent is left unset?**
An unset toggle counts as **No**, so the step it controls is silently skipped and the run can still report success. The warning banner on the **General** tab lists every unset toggle; set each one explicitly to clear it.

### Troubleshooting and edge cases

**The "Run Now" button is greyed out. What should I do?**
The agent is not enabled (licensed) for your entity, and its **General** tab shows a red **Disabled** badge. Contact CapHive support to enable that agent; your own admin cannot switch it on from the agent's page.

**An agent run shows "Failed". How do I find out what went wrong?**
Open the agent's **Execution History** tab and expand the failed run to see its error details. Common causes are a missing LLM API key, no data matching the agent's targets (for example no open deals), or a misconfigured extraction rule.

**I ran Setup All Agents but an agent shows as Disabled. Why?**
Setup creates an agent record for every agent type, but licensing is separate: agents not enabled for your entity show a **Disabled** badge on their card and a greyed-out **Run Now**. Contact CapHive support to enable the agents you need.

**Can I change the LLM model for one agent without affecting others?**
Yes. Open the agent, click **Edit** on the **General** tab and set the **AI Model** field. This overrides the entity's **Default LLM Model** for that agent only.

**How do I add a new sector skill to the Portfolio Scoring Agent?**
Open the Portfolio Scoring Agent's **Edit** page, scroll to the skill file fields and upload a `.md` or `.txt` file in the field matching your sector name. If no matching sector field exists yet, contact your administrator, as new sectors are added as custom fields via Setup.

**The Note Summarizer ran but some investors show "skipped". Why?**
Investors are skipped when they have zero qualifying notes in the lookback period, so no LLM call and no cost is incurred. To see all investors including skipped ones, open the **Note Summaries** tab on the agent page.

**Can I run Deal Management Agent for all deals at once?**
Deal Management Agent runs per deal, scoped to one deal's data room and investors. To cover all deals, use **Deals Report Agent** instead, which iterates over every open deal and produces a consolidated fundraising report.

**The Presentation Analyst found no documents. What should I check?**
Check that presentations are attached to KPI reports, not only to the portfolio company, and that their names contain one of the substrings in **Presentation document names** (case-insensitive). The defaults are `Investor Update`, `Board Deck`, `Management Presentation`, `Quarterly Update` and `Investor Presentation`.

**Is it safe to run Setup All Agents again?**
Yes, setup is idempotent. It only creates what is missing and merges new configuration keys without overwriting existing values, so run it after every platform update to pick up new agents and fields.

**How do I prevent an agent from sending emails during a test run?**
Set the agent's email or recipient field to a test address before running, or temporarily turn off its send-report or notify-email field. For entity-wide suppression, tick **Sandbox** on **Company menu → Company Profile** → **Edit** so all notifications go to the sandbox emails instead.

**My scheduled agent did not run. What should I check?**
Confirm **Enable scheduled runs for this agent** is ticked and saved, and check **Run At** and **Timezone** on the **Schedule** tab. Runs are picked up within 10 minutes of the due time and are skipped while an earlier run of the same agent is still in progress.

**Where can I see who ran an agent and when?**
The agent's **Execution History** tab lists every run with its trigger type (manual or scheduled), status, start time and duration, and each run is kept after it completes or is cancelled.

**The yellow warning banner will not go away. What does it mean?**
The banner lists setup gaps the agent found, such as an unset toggle, a missing email recipient or an unuploaded skill file. Re-run **Setup All Agents** to fill defaults, then fix the remaining data items by hand. See [Verifying Setup](#verifying-setup-the-configuration-warning-banner).

---

## 9. Frequently Asked Questions: AI Governance & Compliance

Answers to the AI governance and security questions most commonly asked during client due diligence.

**Does the application use AI / LLM technology?**
Yes. The platform is multi-LLM and supports all major providers: OpenAI (GPT-5 family), Anthropic (Claude family), Google Gemini, and — via OpenRouter — many additional models including Qwen, DeepSeek, Kimi, and MiniMax. API keys are configured per client entity, and each agent can be pinned to a specific model. Several agents (E-Sign Monitor, Distribution Readiness, Data Quality) are fully deterministic and use no LLM at all.

**Provide a high-level description of the AI technology.**
The platform provides Support Agents — AI-powered automation tools used across the platform to run checks, extract data from documents, generate summaries and scores, and send alerts. Each agent targets a specific operational area (KYC, distributions, e-signing, data quality, deal management, portfolio analysis). See the [Agent Reference](#7-agent-reference) in this guide for a full description of each agent.

**Are there documented escalation procedures for legal or compliance violations?**
Yes. Any event in which the AI is abused, manipulated, or has its security controls circumvented is treated as a security incident under our documented Cybersecurity Risk Management Policy and Security Event Review Methodology. Events are classified by severity (Critical / High / Medium / Low); Critical and High events are triaged within 24 hours, and every confirmed incident is documented with its timeline, impact, and remediation.

**What is the risk classification in the event of the AI being abused, manipulated, or having its security controls circumvented?**
Such an event is classified under our standard four-tier severity scheme based on impact, with any cross-tenant data exposure or unauthorized privilege change treated as Critical. By design, however, the impact of AI manipulation is structurally bounded: all AI agents operate strictly within the authenticated user's tenant and role permissions, which are enforced by deterministic application-layer authorization outside the AI model — a manipulated model cannot grant itself access the user does not already have. All data gathering is performed by the application within the tenant's scope (the AI cannot query data belonging to another tenant), AI agents do not autonomously execute financial transactions or modify permissions, and all AI outputs are persisted as auditable reports subject to human review.

**Is the AI assessed for bias?**
Not separately for the specific use cases within CapHive. The platform uses state-of-the-art foundation models from major providers, which undergo bias and safety testing in their respective labs. As an additional safeguard, we recommend manual review of all AI-generated output before it is acted upon.

**Is there real-time human override of the decision process? And is this logged?**
Yes. An in-flight agent run can be marked cancelled from its progress panel; the cancellation is logged in the run's report, including who cancelled it and when, although it does not interrupt steps the background job is already processing. In addition, AI-generated outputs such as investor scores and note summaries can be manually edited by an administrator after review, and every run — completed or cancelled — is retained in the Execution History audit trail.

**Could the AI decision impact any individual(s)?**
Yes — for example, agents generate reports and scores for portfolio companies and investors. All AI output is decision support, not automated decision-making: nothing is auto-actioned against an individual, and we recommend manual review of all AI-generated output before accepting it.

**Please provide a brief description of the decision making / decision support.**
Agents produce reports, scores, summaries, and alerts that support human decisions — flagging blockers before a distribution, surfacing stale data, scoring investors against a client-defined rubric, or generating pre-board briefing questions. The final decision in every case rests with the platform's human users. See the [Agent Reference](#7-agent-reference) for what each agent produces.

**Is this clearly communicated to the users of the platform?**
Yes. This user guide describes every agent, what it does, and what it produces. Within the platform, each agent's page shows the AI model in use, its configuration, and its full run history, and AI-generated reports are clearly presented as agent output for review.

**What is the highest sensitivity of data the AI will process (including prompts, files, logs, or generated outputs)?**
All the data of a tenant on the platform can potentially be used by the AI. However, every agent is disabled by default and is enabled only if requested by the client — and only for the specific agents the client deems appropriate, via per-agent feature flags. Further, because the platform is multi-LLM with per-tenant API keys, the client may choose an LLM provider that matches their own criteria for data privacy.

**Does the system use any technology that could be seen as privacy intrusive (e.g. user tracking, profiling, recording, or targeting)?**
No. The platform does not track user behaviour, record users, or perform advertising-style profiling or targeting. Agent scoring features evaluate investors and portfolio companies against business rubrics defined by the client, produce transparent written justifications, and are subject to human review and manual override.

---

## 10. Related Guides

- [AI Features](ai_features_user_guide) — overview of AI Rules, agents, AI portfolio reports and chats.
- [LLM Configuration Guide](llm_configuration_guide) — provider keys and the default model agents fall back to.
- [Customer Support Agent](customer_support_agent_user_guide) — the in-app assistant that answers questions from these guides.
- [Agent Charts](agent_charts_user_guide) — charts generated from agent runs and chats.
- [Investor KYC](investor_kyc_user_guide) — the KYC records the KYC Onboarding Agent and KYC Doc Extractor work on.
- [Connect Claude via MCP](mcp_server/user_guide_mcp_connect_claude) — querying the same data from an external AI client.
- [KYC Onboarding Agent](agents/kyc_onboarding_agent_user_guide) — step-by-step guide to the most commonly used onboarding agent.
- [Data Quality Agent](agents/data_quality_agent_user_guide) — the nightly fund health score and fix-it list in detail.
