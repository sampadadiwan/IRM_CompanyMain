# PRD: Fund Ratio Run Templates

**Status:** Draft  
**Date:** 2026-05-19  
**Author:** thimmaiah

---

## Problem

Users currently trigger `FundRatiosScenarioJob` one run at a time from the fund detail page. Each run captures a specific filter combination (fund IDs, portfolio companies, tags, sectors). When a user needs to recompute a standard set of comparisons — e.g., "all our benchmark groups" — at quarter-end, they must manually retrigger each configuration individually with the new date. This is error-prone and slow.

There is also no way to save named filter configurations between sessions; every trigger requires re-selecting the filters from scratch.

---

## Goal

Let users define and persist named `FundRatioRunTemplate` records scoped to their entity. Each template is a saved filter configuration with an optional `tag`. At any time they can supply an `end_date` and trigger all templates, a tagged subset, or a single template — enqueueing `FundRatiosScenarioJob` for each.

There is no separate "set" model. Each entity has exactly one implicit collection of templates, grouped by `tag`.

---

## Concepts

### FundRatioRunTemplate
A saved filter configuration that does not itself hold results. When triggered with an `end_date`, it enqueues `FundRatiosScenarioJob` which creates or reuses a `FundRatioRun` via the existing fingerprint mechanism.

Fields:
- `name` — human label (e.g. "Benchmark Group A"), unique within entity
- `tag` — optional grouping label (e.g. "Cross-fund", "PE", "Q4-pack"); multiple templates share the same tag to form a logical group
- `run_type` — `cross-fund` or `cross-portfolio`
- `anchor_fund_id` — FK → funds (nullable); used for document folder resolution and policy scoping
- `fund_ids` (JSON) — source funds
- `portfolio_company_ids` (JSON) — explicit company overrides
- `portfolio_companies_tags` — tag filter string passed to the job
- `sectors` (JSON) — sector filter
- `currency` — defaults to entity currency at job time if blank
- `position` — integer for display ordering
- `entity_id`, `user_id`, `created_at`, `updated_at`

---

## User Stories

| # | As a… | I want to… | So that… |
|---|-------|-----------|----------|
| 1 | fund manager | create a template with saved filter fields and an optional tag | I define a reusable run configuration once |
| 2 | fund manager | click **Run All** with an end_date | every template for my entity enqueues a job |
| 3 | fund manager | click **Run by Tag**, pick a tag and an end_date | only templates with that tag are triggered |
| 4 | fund manager | click **Run** on a single template with an end_date | one job is enqueued in isolation |
| 5 | fund manager | edit or delete a template | I can update filter configs as my fund structure changes |
| 6 | analyst | see all templates in a table with their tags and last-run date | I can audit what comparison groups exist |

---

## Functional Requirements

### FR-1: Template CRUD
- Create, edit, and delete templates.
- `name` is unique within `entity_id`.
- `tag` is a free-text string; no predefined enum.
- Any entity user can trigger; only the creator or an admin can edit/delete (Pundit policy).

### FR-2: Trigger Actions
Three trigger surfaces, each accepting an `end_date`:

| Action | Scope | Job count |
|--------|-------|-----------|
| **Run All** | all templates for the entity | N |
| **Run by Tag** | templates where `tag == selected_tag` | M ≤ N |
| **Run Single** | one template | 1 |

Each trigger:
1. Validates `end_date` via `ValidationRuleEvaluator` (same path as `generate_fund_ratios`).
2. Calls `FundRatiosScenarioJob.perform_later` once per qualifying template with the stored fields plus the supplied `end_date`.
3. No new job class — reuses `FundRatiosScenarioJob` exactly as today.
4. Pre-trigger flash: "Enqueued N ratio calculations for YYYY-MM-DD."

### FR-3: UI
- **Templates index page** — entity-scoped table; columns: name, tag, run_type, anchor fund, last triggered; actions: Run, Edit, Delete.
- **Tag filter row** — dropdown of distinct tags in the entity's templates; selecting one shows **Run by Tag** button with date picker.
- **Run All** button + date picker at the top of the index.
- Entry point from the existing "Generate Fund Ratios" form: a "Run from Templates" panel with tag selector and date.

### FR-4: Notifications
- Each `FundRatiosScenarioJob` sends its own `UserAlert` completion notification (unchanged behaviour).
- No aggregate "all N jobs done" notification for MVP.

---

## Data Model

```
fund_ratio_run_templates
  id
  entity_id                FK → entities, NOT NULL
  user_id                  FK → users, NOT NULL
  name                     string NOT NULL
  tag                      string (nullable)
  run_type                 string NOT NULL  (cross-fund | cross-portfolio)
  anchor_fund_id           FK → funds (nullable)
  fund_ids                 json NOT NULL default '[]'
  portfolio_company_ids    json NOT NULL default '[]'
  portfolio_companies_tags string (nullable)
  sectors                  json NOT NULL default '[]'
  currency                 string (nullable)
  position                 integer
  created_at, updated_at

  INDEX (entity_id, name) UNIQUE
  INDEX (entity_id, tag)
```

No changes to `fund_ratio_runs` or `fund_ratios`. The existing `FundRatioRun` fingerprint deduplication applies — triggering the same template twice for the same end_date reuses the existing run record.

---

## Out of Scope (MVP)
- Aggregate execution tracking ("3 of 5 jobs done").
- Scheduled / recurring triggers.
- Per-template default end_date.
