# Portfolio Scoring Agent - Implementation Plan

---

## Contents

1. [Overview & Purpose](#1-overview--purpose)
2. [Design Summary](#2-design-summary)
3. [Skill File System](#3-skill-file-system)
4. [Agent Steps Definition](#4-agent-steps-definition)
5. [Default Score Schema](#5-default-score-schema)
6. [UI Design](#6-ui-design)
7. [Technical Architecture](#7-technical-architecture)
8. [Files to Create / Modify](#8-files-to-create--modify)
9. [Implementation Plan](#9-implementation-plan)

---

## 1. Overview & Purpose

### What is the Portfolio Scoring Agent?

An AI-powered support agent that scores portfolio companies using **sector-specific skill files** uploaded by the tenant. The agent gathers all available structured and unstructured data for a portfolio company (KPIs, KPI report documents, portfolio investments, valuations), sends it to an LLM together with the relevant skill prompt, and stores a JSON score that is rendered as a widget on the portfolio company dashboard.

### Problem it Solves

- Provides a consistent, repeatable scoring methodology per sector (D2C, Fintech, SaaS, etc.)
- Each tenant can define their own scoring criteria via markdown skill files — no code change required
- Scores are stored historically so portfolio managers can track improvement over time
- Score is surfaced directly on the portfolio company dashboard as a widget

### Agent Type

> **AI Support Agent** (uses LLM)
> - Sector-aware: selects the right skill prompt for each portfolio company's sector
> - Configurable output: skill file defines dimensions, weights, and narrative style
> - Default JSON schema enforced; skill can extend it freely
> - Run on demand for a single company or in batch across all matching companies
> - Full history preserved: each run creates a new `SupportAgentReport`

### Scope

| In Scope | Out of Scope |
| :--- | :--- |
| KPI data (all periods, all tags) | Automated emailing of scores |
| KPI report attached documents (full text) | Scoring of non-portfolio-company investors |
| Portfolio investments (all instruments) | Comparison scoring across multiple companies |
| Valuations (latest + history) | Custom scoring UI builder |
| Batch run across all sector-matched companies | Real-time KPI streaming |
| Per-company "Run" button on dashboard | |
| Score widget on Portfolio Company Dashboard | |

---

## 2. Design Summary

| Decision | Choice | Rationale |
|---|---|---|
| Skill storage | File custom field on SupportAgent | Reuses existing infrastructure, no new tables |
| Skill identification | `meta_data` on `FormCustomField` | e.g. `skill: true, sector: D2C` — parsed at runtime |
| Sector matching | `Investor.sector` field | Existing field, already populated for portfolio companies |
| Score storage | New `SupportAgentReport` per run | Full history, queryable by investor + agent type |
| Score format | JSON with default schema + free-form extension | Skill defines dimensions; agent validates required keys |
| Widget | New "Scoring Report" in Portfolio Company Dashboard | Reads latest SupportAgentReport |
| Run trigger | Existing `run_support_agents_path` + new button | Consistent with other agents (e.g. PortfolioCompanyAgent) |

---

## 3. Skill File System

### How Skills Work

A **skill** is a `File`-type custom field added to the `SupportAgent`'s form type by the admin. The uploaded markdown file contains:

- Scoring instructions for the LLM
- Dimensions to evaluate (and optionally their weights)
- The required JSON output structure (extending the default schema)
- Any sector-specific context (e.g. D2C-specific KPI benchmarks)

The custom field's `meta_data` column identifies it as a skill and specifies the sector it applies to:

```
skill: true, sector: D2C
```

### How the Agent Finds the Right Skill

Exact sector match wins; falls back to a `General` skill if no sector-specific file is configured. This means one general-purpose skill file can serve as the default for any tenant portfolio.

```ruby
# In SupportAgent model
def skill_for_sector(sector)
  skill_fields = form_custom_fields.select { |f| f.field_type == "File" && f.meta_data.to_s.match?(/skill/i) }
  fcf = skill_fields.find { |f| f.meta_data.to_s.match?(/sector[:\s=]+#{Regexp.escape(sector.to_s)}/i) } ||
        skill_fields.find { |f| f.meta_data.to_s.match?(/sector[:\s=]+General/i) }
  return nil unless fcf

  # Document is stored with field.human_label as its name
  documents.find_by(name: fcf.human_label)
end
```

**Setup tip:** Add one `General` skill field (meta_data: `skill: true, sector: General`) as a catch-all. Add sector-specific fields only for sectors that need custom scoring criteria.

### Setup Flow for Admins

> **FormType naming constraint:** `FormType.name` must be a constantizable model class name. For SupportAgents, always use `name: "SupportAgent"` and use `tag` to differentiate (e.g. `tag: "PortfolioScoringAgent"`).

1. Create a `FormType` with `name: "SupportAgent"`, `tag: "PortfolioScoringAgent"` for the entity
2. Add a `File`-type `FormCustomField` to that FormType: **label = "Generic Portfolio Skill"**, **meta_data = `skill: true, sector: General`**
3. Create a `SupportAgent` with `agent_type: "PortfolioScoringAgent"`, linked to the above FormType
4. Edit the agent → upload the markdown skill file (the "General" skill serves all sectors without a dedicated file)
5. Optionally add sector-specific fields: **label = "D2C Skill"**, **meta_data = `skill: true, sector: D2C`** — upload a D2C-specific markdown; exact match always wins over General

**Rake task for provisioning:** To clone all agents from the reference entity (ID=157) to any new entity:

```sh
rake 'support_agents:clone[TARGET_ENTITY_ID]'
# or specify a different source:
rake 'support_agents:clone[TARGET_ENTITY_ID,SOURCE_ENTITY_ID]'
```

This copies all bitflags, FormTypes, FormCustomFields, SupportAgents, and File documents. Safe to re-run (idempotent).

### Skill File Format (Markdown)

Skills are free-form markdown. The agent injects the data context and instructs the LLM to return JSON in the default schema. A typical skill file looks like:

```markdown
# D2C Scoring Skill

You are evaluating a Direct-to-Consumer (D2C) portfolio company.
Score the company across the following dimensions:

## Dimensions (suggested weights)
- Revenue Growth (30%): YoY and QoQ growth trajectory
- Unit Economics (25%): CAC, LTV, LTV/CAC ratio
- Operational Efficiency (20%): Gross margin trend, burn rate
- Market Position (15%): GMV, repeat purchase rate, NPS
- Team & Execution (10%): Milestone achievement vs plan

## Scoring Scale
Score each dimension 0–100. Overall score is the weighted average.

## Grade Mapping
- 90–100: A+, 80–89: A, 70–79: B+, 60–69: B, 50–59: C, <50: D

## Benchmarks
- D2C revenue growth >40% YoY is strong for early stage
- LTV/CAC >3x is healthy; <1.5x is a concern
- Gross margins >50% for product, >60% for digital goods

Return your assessment as a JSON object following the required schema.
```

---

## 4. Agent Steps Definition

```
initialize_agent → load_sector_skill → gather_portco_data → generate_score → store_score
```

### Step Detail

| Step | Description | Failure Behaviour |
|---|---|---|
| `initialize_agent` | Load `investor` (target) and `support_agent` from context; set up shared ctx | Hard fail |
| `load_sector_skill` | Call `support_agent.skill_for_sector(investor.sector)`; exact sector match → falls back to `General` skill | Sets `ctx[:skill_error]`; always returns `true` so `store_score` still runs and records a failed report |
| `gather_portco_data` | Collect KPIs, KPI report documents (full text), portfolio investments, valuations | Warn on partial data; continue with what is available |
| `generate_score` | Build prompt (skill markdown + gathered data JSON); call LLM; extract and validate JSON block | Fail if JSON cannot be extracted or required keys missing |
| `store_score` | Create new `SupportAgentReport` with `status: :completed` and score in `json_fields["score"]`; on error create with `status: :failed` | Always creates a report record |

### `gather_portco_data` Detail

```
KPI Data:
  - Only "Actual"-tagged kpi_reports (Budget/IC excluded to reduce noise)
  - Approved KPIs per report: {name, value, denomination}
  - denomination comes from investor_kpi_mapping.denomination (Kpi has no .unit column)

KPI Report Documents:
  - Documents from the latest Actual kpi_report only
  - Download each file → extract full text (PDF, DOCX, TXT, XLSX, PPTX, CSV, MD)
  - Supported extensions: SUPPORTED_DOC_EXTENSIONS constant in the service

Portfolio Investments:
  - All portfolio_investments for this investor
  - Fields: investment_instrument, fund, amount, cost, fmv, date, status

Valuations:
  - All valuations for this investor ordered by date desc
  - Fields: valuation_date, valuation, per_share_value, currency

Investor Custom Fields:
  - investor.json_fields (all non-nil values)
```

### `targets(entity_id)` Method

Accepts either a single `Investor` instance (adhoc/widget run) or an `entity_id` integer (batch run). Companies without a sector are excluded because no skill can be matched.

```ruby
def targets(entity_id)
  if entity_id.is_a?(Investor) || entity_id.is_a?(ActiveRecord::Base)
    [entity_id]
  else
    Investor.where(entity_id: entity_id, category: "Portfolio Company")
            .where.not(sector: [nil, ""])
            .includes(:portfolio_kpi_reports, :valuations, :portfolio_investments)
  end
end
```

### Batch Processing

Follows the same pattern as `PortfolioCompanyAgent`:
- Sequential execution (no threading)
- Collects successes/errors per company
- Sends batch summary notification on completion
- `:scheduled` mode suppresses the summary notification

---

## 5. Default Score Schema

The skill prompt instructs the LLM to return a JSON block. The agent validates that the following **required keys** are present before storing:

- `overall_score` (integer, 0–100)
- `grade` (string, e.g. "B+")
- `summary` (string, narrative overview)
- `dimensions` (array, at least one item)

Each dimension must have `name` and `score`. All other fields are optional but encouraged.

### Full Schema

```json
{
  "overall_score": 75,
  "grade": "B+",
  "summary": "Narrative overview of the company's performance and standing...",
  "dimensions": [
    {
      "name": "Revenue Growth",
      "score": 85,
      "weight": 0.30,
      "rationale": "YoY revenue up 42%, exceeding sector median of 30%"
    },
    {
      "name": "Unit Economics",
      "score": 62,
      "weight": 0.25,
      "rationale": "LTV/CAC at 2.1x — improving but below target of 3x"
    }
  ],
  "strengths": [
    "Strong GMV trajectory with 45% YoY growth",
    "Improving gross margins QoQ"
  ],
  "risks": [
    "High CAC relative to LTV in new acquisition channels",
    "Concentrated revenue: top 3 customers = 60% of revenue"
  ],
  "recommendations": [
    "Prioritize retention spend over new acquisition",
    "Diversify revenue channels to reduce concentration"
  ],
  "data_coverage": {
    "kpi_periods": 6,
    "valuations_used": 2,
    "documents_read": 3
  }
}
```

### Score Extraction Logic

The agent tries fenced JSON first (`\`\`\`json … \`\`\``), then a bare JSON fence, then a raw `{…}` match as last resort:

```ruby
REQUIRED_SCORE_KEYS = %w[overall_score grade summary dimensions].freeze

def extract_score_json(raw)
  match = raw.match(/```json\s*(\{.+?\})\s*```/m) ||
          raw.match(/```\s*(\{.+?\})\s*```/m) ||
          raw.match(/(\{.+\})/m)
  raise "No JSON block found in LLM response" unless match

  parsed = JSON.parse(match[1])
  validate_score_keys!(parsed)
  parsed
end

def validate_score_keys!(parsed)
  missing = REQUIRED_SCORE_KEYS.reject { |k| parsed.key?(k) }
  raise "Score JSON missing required keys: #{missing.join(', ')}" if missing.any?
  raise "overall_score must be an integer 0–100" unless parsed["overall_score"].to_i.between?(0, 100)
  raise "dimensions must be a non-empty array" unless parsed["dimensions"].is_a?(Array) && parsed["dimensions"].any?
end
```

---

## 6. UI Design

### Dashboard Widget: "Scoring Report"

Added to `PORTFOLIO_COMPANY_WIDGETS` in `DashboardWidget`:

```ruby
DashboardWidget.new(
  dashboard_name: PORTFOLIO_COMPANY_DASHBOARD,
  widget_name:    "Scoring Report",
  path:           "investors/widgets/scoring_report",
  size:           "XL",
  metadata_help:  "{title: 'Company Score', agent_type: 'PortfolioScoringAgent'}"
)
```

### Widget States

**No score yet:**
```
┌─────────────────────────────────────────────────────┐
│ Company Score                                        │
│                                                      │
│  No scoring data available for this company.         │
│  [Run Scoring Agent]                                 │
└─────────────────────────────────────────────────────┘
```

**Score available:**
```
┌─────────────────────────────────────────────────────┐
│ Company Score                    Scored: 12 May 2026 │
│                                                      │
│  ████████████░░░  75/100  B+                        │
│                                                      │
│  DIMENSIONS                                          │
│  Revenue Growth    ██████████░  85   (30%)           │
│  Unit Economics    ██████░░░░░  62   (25%)           │
│  ...                                                 │
│                                                      │
│  SUMMARY                                             │
│  Strong GMV growth with improving margins...         │
│                                                      │
│  ✓ Strengths  ⚠ Risks  → Recommendations            │
│                                                      │
│  [Run Scoring Agent]  Sector: D2C                   │
└─────────────────────────────────────────────────────┘
```

**Failed run:**
```
┌─────────────────────────────────────────────────────┐
│ Company Score                                        │
│                                                      │
│  ⚠ Last scoring run failed:                         │
│  No skill configured for sector: SaaS               │
│                                                      │
│  [Run Scoring Agent]                                 │
└─────────────────────────────────────────────────────┘
```

### "Run Scoring Agent" Button

Added to the existing dropdown on the portfolio company `show` page (same pattern as the PortfolioCompanyAgent button):

```erb
<%= button_to run_support_agents_path(
      agent_type: "PortfolioScoringAgent",
      target_id: @investor.id,
      method: :post
    ), class: "dropdown-item",
    data: { bs_toggle: "tooltip", bs_title: "Scores this portfolio company using the configured skill for its sector" } do %>
  <i class="ti ti-chart-bar"></i> Run Scoring Agent
<% end %>
```

The button also appears inside the scoring report widget itself when no score exists yet (as a call-to-action).

### SupportAgent Show Page

A **Scoring Reports** tab is added to the SupportAgent show page (visible only for `PortfolioScoringAgent`). It lists all scored companies with their score progress bar, grade badge, status, scored date, and an expandable dimension breakdown. Reports are loaded directly from `SupportAgentReport` — no controller change needed; the tab partial queries them inline.

---

## 7. Technical Architecture

### Component Map

```
Admin Setup:
  FormCustomField (type=File, meta_data="skill: true, sector: D2C")
    └─→ Document (name="D2C Skill", owner=SupportAgent, file=markdown)

Runtime:
  SupportAgentsController#run
    └─→ SupportAgentJob
          └─→ PortfolioScoringAgent (Trailblazer service)
                ├─→ SupportAgent#skill_for_sector(sector) → Document → markdown text
                ├─→ Investor → KpiReports → Kpis
                ├─→ KpiReport → Documents → extracted text
                ├─→ PortfolioInvestments
                ├─→ Valuations
                └─→ LLM call → JSON score → SupportAgentReport.create(json_fields: {score: ...})

Display:
  Portfolio Company Dashboard
    └─→ DashboardWidget "Scoring Report"
          └─→ _scoring_report.html.erb
                └─→ SupportAgentReport (latest, joined to PortfolioScoringAgent)
                      └─→ _score_display.html.erb
```

### SupportAgentReport Usage

Since `WithSupportAgent` adds `has_one :support_agent_report`, but scoring keeps full history, the service always calls `SupportAgentReport.create(...)` (not `find_or_initialize_by`). The widget queries directly:

```ruby
SupportAgentReport
  .joins(:support_agent)
  .where(owner: @investor)
  .where(support_agents: { agent_type: "PortfolioScoringAgent" })
  .order(created_at: :desc)
  .first
```

Score data lives in `json_fields["score"]`. Error message (for failed runs) lives in `json_fields["error"]`.

### LLM Prompt Structure

```
SYSTEM:
  {contents of skill markdown file}

USER:
  Score the following portfolio company.

  Company: {investor_name}
  Sector:  {investor.sector}

  ## KPI Data
  {kpi_reports as JSON}

  ## Portfolio Investments
  {investments as JSON}

  ## Valuations
  {valuations as JSON}

  ## Documents
  {for each document: "=== {name} ({date}) ===\n{extracted_text}\n"}

  ## Company Details (Custom Fields)
  {investor.json_fields as JSON}

  Return your assessment as a JSON object. Required keys:
  overall_score (0–100 integer), grade (string), summary (string),
  dimensions (array of {name, score, weight, rationale}).
```

---

## 8. Files to Create / Modify

### Created

| File | Purpose |
|---|---|
| `app/packs/ai/support_agents/services/portfolio_scoring_agent.rb` | Trailblazer service with 5 steps |
| `app/packs/core/investors/views/investors/widgets/_scoring_report.html.erb` | Widget outer shell: finds latest report, dispatches to state partials |
| `app/packs/core/investors/views/investors/widgets/_score_display.html.erb` | Renders score JSON as styled HTML (progress bars, dimensions table, strengths/risks/recs) |
| `app/packs/ai/support_agents/views/support_agents/_scoring_reports_tab.html.erb` | Tab on SupportAgent show page listing all scored companies with expandable dimension rows |
| `app/packs/ai/support_agents/views/support_agents/_custom_field_rows.html.erb` | Shared partial rendering all custom fields (json_fields types + File-type fields via Documents) |
| `lib/tasks/support_agents.rake` | Rake task to clone agents from entity 157 to any target entity (idempotent) |

### Modified

| File | Change |
|---|---|
| `app/packs/ai/support_agents/models/support_agent.rb` | Added `skill_for_sector(sector)` with General fallback; added `folder_path` (required by WithFolder for Document uploads) |
| `app/packs/core/base/models/dashboard_widget.rb` | Added "Scoring Report" to `PORTFOLIO_COMPANY_WIDGETS` |
| `app/packs/core/investors/views/investors/show.html.erb` | Added "Run Scoring Agent" button to the actions dropdown |
| `app/packs/ai/support_agents/views/support_agents/show.html.erb` | Added "Scoring Reports" tab nav + pane (guarded by `agent_type == "PortfolioScoringAgent"`) |
| `app/packs/ai/support_agents/views/support_agents/_general_tab.html.erb` | Replaced inline File field loop with `render "support_agents/custom_field_rows"` |
| `app/packs/ai/support_agents/views/support_agents/_support_agent_card.html.erb` | Replaced inline File field loop with `render "support_agents/custom_field_rows"` |
| `app/packs/core/entities/models/concerns/entity_enabled.rb` | Added `:portfolio_scoring_agent` to support_agents bitflag list |

### Key Implementation Notes

- **`folder_path` on SupportAgent**: `WithFolder` calls `folder_path` on the document owner. SupportAgent was missing this — added `def folder_path; "Support Agents/#{agent_type}"; end`.
- **Shrine content-type for `.md` files**: `text/markdown` is not in `FileUploader::ALLOWED_TYPES`. Upload `.md` skill files with a `.txt` extension and `content_type: "text/plain"`.
- **Scoring Reports tab vs Execution History**: The Execution History tab reads `AgentExecutionLog` (from scheduled job pipeline). Direct runs create `SupportAgentReport` only — hence the dedicated Scoring Reports tab.
- **`denomination` not `unit`**: `Kpi` has no `unit` column; use `k.investor_kpi_mapping&.denomination` for the KPI unit/denomination.

---

## 9. Implementation Plan

### Phase 1 — Agent Core (backend only)

1. Add `"PortfolioScoringAgent"` to `SupportAgent::AGENT_TYPES`
2. Add `skill_for_sector(sector)` to `SupportAgent` model
3. Create `PortfolioScoringAgent` service with all 5 steps
4. Add `process_batch` class method following PortfolioCompanyAgent pattern
5. Validate JSON extraction and schema enforcement logic

### Phase 2 — Widget & Dashboard

6. Add "Scoring Report" widget to `DashboardWidget::PORTFOLIO_COMPANY_WIDGETS`
7. Create `_scoring_report.html.erb` partial (3 states: no data / failed / scored)
8. Create `_score_display.html.erb` partial (overall score bar, dimensions table, narrative sections)

### Phase 3 — Run Trigger

9. Add "Run Scoring Agent" button to `investors/show.html.erb` dropdown
10. Add inline "Run Scoring Agent" button inside `_scoring_report.html.erb` when no score exists
11. Update `SupportAgentsController#show` to load `@scoring_reports` for `PortfolioScoringAgent` type

### Phase 4 — Testing & Docs

12. Write feature spec: single company scoring, batch run, missing skill, invalid LLM response
13. Test widget renders correctly with mock SupportAgentReport data
14. Document skill file format and setup guide for admins

---

### Open Decisions (Post-MVP)

| Item | Options |
|---|---|
| Scheduled scoring | Add cron support via AgentSchedule (already supported by the job infrastructure) |
| Score comparison widget | Side-by-side view of multiple scoring runs over time |
| Cross-portfolio score table | Aggregate table of all portfolio company scores on the Portfolio Dashboard |
| Score export | PDF / CSV export of latest scores per company |
