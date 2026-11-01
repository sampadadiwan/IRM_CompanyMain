# Report Builder assistant — Low-level design

> **Audience:** Reviewing developer. Additive to [design.md](design.md); worked examples in [business-rules.md](business-rules.md).

## Contents

- [1. Files](#1-files)
- [2. Method contracts](#2-method-contracts)
- [3. Prompts](#3-prompts)
- [4. Routes, policy and controller](#4-routes-policy-and-controller)
- [5. Streams and DOM ids](#5-streams-and-dom-ids)
- [6. Messages](#6-messages)
- [7. Jobs](#7-jobs)
- [8. Tests](#8-tests)
- [Project rules checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

## 1. Files

| File | New / changed | Box |
|---|---|---|
| `app/packs/core/base/controllers/concerns/report_builder/assistant.rb` | New | ①⑦ |
| `app/packs/core/base/services/report_draft_generator.rb` | New | ④ |
| `app/packs/core/base/models/report_spec_pruner.rb` | New | ⑤ |
| `app/packs/core/base/models/report_builder_chart_suggestion.rb` | New | ⑧ |
| `app/packs/core/base/jobs/report_draft_job.rb`, `report_draft_cleanup_job.rb` | New | ③⑨ |
| `app/packs/core/base/models/report_spec_applier.rb` | `replace:` option | ⑥ |
| `app/packs/core/base/policies/report_policy.rb` | Draft privacy in `Scope`, `show?`, `update?` | ② |
| `app/packs/core/base/views/report_builder/describe.html.erb`, `draft.html.erb`, `_draft_state.html.erb`, `_report_chart.html.erb` | New | ①⑦⑧ |
| `app/packs/core/base/views/report_builder/view.html.erb` | Chart above the table | ⑧ |
| `app/packs/core/base/views/reports/_new_report.html.erb`, `_card.html.erb` | Describe it; Draft badge | ①② |
| `config/routes/core.rb`, `config/initializers/sidekiq.rb` | Routes; daily clean-up | ①⑨ |
| `docs/user_guides/report_builder_user_guide.md` | Describe it section + FAQs | — |

**Reviewer checks**
- [ ] `ReportPolicy` is the only existing class whose rules change (flagged in design §Policy).

## 2. Method contracts

| Signature | Returns / raises |
|---|---|
| `ReportDraftGenerator.available?(entity)` | Boolean: `entity.entity_setting&.default_llm_model.present? \|\| ENV["DEFAULT_MODEL"].present?` |
| `ReportDraftGenerator.new(entity:, question:, spec: nil, instruction: nil).call` | `{ "spec" => Hash, "questions" => [], "assumptions" => [], "cannot" => [], "name" => String }`; raises `ReportDraftGenerator::Failed` |
| `ReportSpecPruner.prune(spec, entity:)` | `[Hash clean_spec, Array<String> problems]`; clean spec may have no columns |
| `ReportSpecApplier.apply!(report:, spec:, fund: nil, validate: true, replace: false)` | Report |
| `ReportBuilderChartSuggestion.for(config:, columns:, rows:, formatter:)` | Chart.js config Hash, or nil; `.describe(config)` → "Bar — Committed by Investor" |
| `ReportDraftJob.perform(report_id, user_id, instruction = nil)` | — |

**Reviewer checks**
- [ ] `call` never returns row data and never includes fund or investor names in the prompt.
- [ ] `prune` never raises on a malformed spec (non-Hash parts are dropped with a problem).

## 3. Prompts

| Step | Marker (first line) | Contents | Expected JSON |
|---|---|---|---|
| 1 | `REPORT TABLE` | Question; tables `[{model, label}]` | `{ "root_model": "...", "cannot": [] }` |
| 2 | `REPORT SPEC` | Spec format; rules; 2 template specs as examples; catalog of the table (own columns key/label/type; related data relation/kind/columns); the current spec and instruction when refining | `{ "spec": {...}, "questions": [...], "assumptions": [...], "cannot": [...], "name": "..." }` |
| Chart | (ChartAgentService) | Instruction + 20 rows | Chart.js config |

Retry: one more `chat.ask` with "Answer with the JSON object only." after a non-JSON answer; one more full attempt after an exception.

## 4. Routes, policy and controller

| Route | Action |
|---|---|
| `get 'describe'` / `post 'describe'` | `describe` / `describe_create` |
| `get ':id/draft'` | `draft` |
| `post ':id/draft/refine'`, `post ':id/draft/fund'` | `draft_refine`, `draft_fund` |
| `patch ':id/draft/chart'`, `post ':id/draft/chart'` | `draft_chart`, `draft_describe_chart` |
| `patch ':id/draft/save'`, `delete ':id/draft'` | `draft_save`, `draft_discard` |

Policy: `ReportPolicy#draft_owner_ok?` = `record.category != "AI draft" || record.user_id == user.id`; `show?` and `update?` add it; `Scope#resolve` adds `where("reports.category IS NULL OR reports.category <> ? OR reports.user_id = ?", "AI draft", user.id)`.

**Reviewer checks**
- [ ] NULL categories stay visible (explicit `IS NULL`).

## 5. Streams and DOM ids

| Id | Replaced by |
|---|---|
| `rb_draft_<report id>` | `ReportDraftJob` (stream `user_alert_<user id>`), and every draft action's turbo-stream answer |

## 6. Messages

| Where | Text |
|---|---|
| Not set up | "AI drafting isn't set up for your account" |
| Drafting | "Drafting… this takes 5–20 seconds" |
| Failed | "Couldn't draft this right now — try again in a moment" |
| Ready alert | "Your draft report is ready" (link "Open draft") |
| Not reportable root | "<tables> aren't available in reports for your account" |
| Value matches nothing | "No <table> have <Field> <value> — values: a, b, c" |
| Company filter | "Filters on the company itself can't be used" |
| Describe a chart note | "Sends these 20 rows to your configured AI model" |
| No chart | "No chart suggested" |

## 7. Jobs

| Job | Queue | Retry | Notes |
|---|---|---|---|
| `ReportDraftJob` | default | none (own retry inside the generator) | status guard: returns if the report is gone |
| `ReportDraftCleanupJob` | low | default | `cron: '30 2 * * *'` |

## 8. Tests

| Feature | Scenarios |
|---|---|
| `assistant.feature` | H1–H4, H6, H9, E1–E5, E7–E10, X1–X7 |
| `assistant_chart.feature` | H5, H7, H8, E6, E11, E12 |

## Project rules checklist

| Rule | Applies | How |
|---|---|---|
| Large-table hygiene | Applies | 20-row preview; no value lists on large tables |
| Date formatting | Applies | `l(...)` in the UI |
| Tenant scoping | Applies | Engine entity scope; `entity_id` filters pruned; per-entity catalog |
| MySQL DISTINCT/ORDER | N/A | No new DISTINCT |
| MCP ontology | N/A | — |
| Cucumber only | Applies | Two features, AI stubbed |
| Reuse UI styling | Applies | Wizard summary cards, preview, `_health`, Immediate Actions popup, badges |
| Existing model changes | N/A | Only the policy changes (flagged) |

## Sign-off

| Reviewer | Date | Decision |
|---|---|---|
| | | |
