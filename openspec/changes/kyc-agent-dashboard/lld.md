# KYC Agent Dashboard — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/kyc/agent-dashboard/spec.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md): link to its diagrams and
> worked examples rather than repeating them.

---

## Contents

- [Review Summary](#review-summary)
- [File Map](#file-map)
- [Schema Detail](#schema-detail)
- [Method Contracts](#method-contracts)
- [Controllers, Params and Responses](#controllers-params-and-responses)
- [Queries and Indexes](#queries-and-indexes)
- [Transactions, Locking and Concurrency](#transactions-locking-and-concurrency)
- [Background Jobs](#background-jobs)
- [External Integrations](#external-integrations)
- [Error Mapping and Logging](#error-mapping-and-logging)
- [Security Review](#security-review)
- [Configuration and Rollout](#configuration-and-rollout)
- [Test Plumbing](#test-plumbing)
- [Project Rules Checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

- **JSON_SEARCH queries for "Partially Failed" classification** — uses `JSON_SEARCH(json_fields, 'one', 'success', NULL, '$**.severity')` on `support_agent_reports.json_fields`. Works on MySQL's binary JSON storage (LIKE fails on native JSON columns). Not indexable but acceptable at current scale (<5000 reports per entity). See [Queries and Indexes](#queries-and-indexes).
- **No migration** — all data exists in `investor_kycs` and `support_agent_reports`. Dashboard is read-only over existing tables.
- **Single new controller action** (`kyc_run_output`) for the detail panel — all other actions reuse existing endpoints. See [Controllers, Params and Responses](#controllers-params-and-responses).
- **Half-donut chart via Highcharts startAngle/endAngle** — `plotOptions.pie.startAngle: -90, endAngle: 90` renders a native semicircle. Previous CSS `overflow: hidden` approach caused proportional distortion. See [File Map](#file-map).
- **Merged per-type query** — `kyc_stat_counts` and `kyc_chart_data` merged into single `kyc_type_stats` with `GROUP BY type`. One SQL query returns both stat card counts and chart data per type.
- **Fund filter subquery** — `WHERE id IN (SELECT investor_kyc_id FROM capital_commitments WHERE fund_id = ?)`. Uses existing index on `capital_commitments.fund_id`. See [Queries and Indexes](#queries-and-indexes).
- **Docs column with tooltip** — `kyc_doc_ratios` enhanced to return doc names (required, uploaded, missing) alongside counts. Tooltip on hover shows the names. Agent validation results shown in detail panel's "Documents" tab instead. See [Method Contracts](#method-contracts).
- **"Documents" tab in run output panel** — `kyc_run_output_items` now tags each item with `source: :field` or `source: :document`. A new "Documents" tab in the panel filters by `data-source="document"`. See [Method Contracts](#method-contracts).
- **Grouped run output by pipeline step** — issues are grouped by `step:` tag (set by `KycOnboardingAgent` on each issue hash). `kyc_run_output_items` returns items with a `step:` key; the panel partial renders collapsible sections per step (Field Completeness, Document Presence, Document Validity, Consistency, Expiry Status). Tab filters apply across groups.

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① Query | `app/packs/ai/support_agents/services/agent_reports_query.rb` | Modified | Add `kyc_dashboard_data`, `kyc_basic_stats`, `kyc_type_stats`, `kyc_top_failures`, `kyc_filtered_records`, `kyc_doc_ratios` (enhanced with doc names for tooltip), `kyc_pending_ids` |
| ② Tab | `app/packs/ai/support_agents/views/support_agents/show.html.erb` | Modified | Add KYC Dashboard tab link + tab pane |
| ② Tab | `app/packs/ai/support_agents/views/support_agents/_kyc_dashboard_tab.html.erb` | New | Dashboard layout: basic stats + two-column agent stats + table + run button |
| ② Tab | `app/packs/ai/support_agents/controllers/support_agents_controller.rb` | Modified | Load `kyc_dashboard_data` in `show`, add `kyc_run_output` action |
| ③a Basic Stats | `app/packs/ai/support_agents/views/support_agents/_kyc_dashboard_basic_stats.html.erb` | New | 6 cards for KYC form status (Verified, Unverified, Completed, Expired, Individual, Non Individual) with Ransack links to normal KYC page |
| ③+④ Type Columns | `app/packs/ai/support_agents/views/support_agents/_kyc_dashboard_type_columns.html.erb` | New | Two-column layout: Individual / Non-Individual, each with 6 stat cards + half-donut chart. Top failures full-width below. |
| ⑤ Table | `app/packs/ai/support_agents/views/support_agents/_kyc_dashboard_table.html.erb` | New | Filterable table with Turbo Frame + Pagy + per-row inline detail frames |
| ⑥ Panel | `app/packs/ai/support_agents/views/support_agents/_kyc_run_output_panel.html.erb` | New | Inline expand below row with per-KYC turbo frame |
| ⑦ Actions | `app/packs/ai/support_agents/helpers/kyc_dashboard_helper.rb` | New | Status classification, result summary, action visibility |
| Stimulus | `app/javascript/controllers/kyc_dashboard_filter_controller.js` | New | Stat card toggle + dual-param filter (status + kyc_type) |
| Stimulus | `app/javascript/controllers/kyc_run_output_controller.js` | New | Show/hide inline detail row, item tab filtering |
| Routes | `config/routes/ai.rb` | Modified | Add `kyc_run_output` member route to support_agents |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/<domain>/<sub_domain>/...`) and Packwerk boundaries
- [ ] New partials are in the `support_agents` views directory (same pack as other agent tabs)
- [ ] Helper is in the `support_agents` helpers directory

---

## Schema Detail

N/A — no database migrations. The dashboard reads existing tables only. No columns or indexes added.

**Reviewer checks**
- [ ] Confirmed: no migration file needed

---

## Method Contracts

**`AgentReportsQuery`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#kyc_dashboard_data(params)` | `params: {status:, kyc_type:, q:, fund_id:, date_from:, date_to:, page:}` | `{basic_stats: Hash, type_stats: Hash, records: Array<InvestorKyc>, pagy: Pagy, top_failures: Array, doc_ratios: Hash, pending_ids: Array<Integer>}` | None | None (read-only) | Yes |
| `#kyc_basic_stats` | none | `{verified: Integer, unverified: Integer, completed: Integer, expired: Integer, individual: Integer, non_individual: Integer}` | None | None | Yes |
| `#kyc_type_stats` | none | `{individual: {validated:, pending:, successful:, failed:, partial:, expired:}, non_individual: {same}}` | None | None | Yes |
| `#kyc_top_failures(limit: 5)` | `limit: Integer` | `[{message: String, count: Integer, affected: [{kyc_id: Integer, kyc_name: String}]}]` | None | None | Yes |
| `#kyc_filtered_records(params)` | filter params | `[Pagy, Array<InvestorKyc>]` | None | None | Yes |
| `#kyc_doc_ratios(records)` | `Array<InvestorKyc>` (already loaded) | `Hash<Integer, {uploaded: Integer, required: Integer, required_names: Array, uploaded_names: Array, missing_names: Array}>` | None | None | Yes |
| `#kyc_pending_ids` | none | `Array<Integer>` — IDs of completed KYCs with no latest report from this agent | None | None | Yes |

**`KycDashboardHelper`** (Helper)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#kyc_agent_status(kyc, report)` | InvestorKyc, SupportAgentReport or nil | `String` — "pending", "successful", "failed", "partial", "expired" | None | None | Yes |
| `#kyc_result_summary(report)` | SupportAgentReport or nil | `String` — "X of Y items matched" or "—" | None | None | Yes |
| `#kyc_doc_ratio(kyc, doc_ratios)` | InvestorKyc, Hash | `String` — "X / Y" (uploaded / required) or "—" | None | None | Yes |
| `#kyc_doc_ratio_color(uploaded, required)` | Integer, Integer | `String` — "text-success", "text-warning", or "text-danger" | None | None | Yes |
| `#kyc_doc_tooltip(ratio)` | Hash or nil | `String` — multiline tooltip with required/uploaded/missing doc names | None | None | Yes |
| `#kyc_run_output_items(report)` | SupportAgentReport | `Array<Hash>` — `[{item:, detail:, status:, source:, step:}]` — source is `:field` or `:document`; step is the pipeline step name (e.g., `"field_completeness"`, `"document_presence"`, `"document_validity"`, `"consistency"`, `"expiry_status"`) | None | None | Yes |
| `#kyc_run_output_counts(items)` | Array<Hash> | `Hash` — `{"all" => N, "matched" => N, "failed" => N, "warning" => N, "documents" => N}` | None | None | Yes |
| `#show_mark_verified?(kyc, report)` | InvestorKyc, SupportAgentReport | `Boolean` | None | None | Yes |

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] Anything a retry can repeat is idempotent
- [ ] `kyc_dashboard_data` returns empty/zero stats when no KYCs exist, not nil

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `SupportAgentsController#show` (modified) | existing + `status`, `kyc_type`, `q`, `fund_id`, `date_from`, `date_to`, `page` | `show?` (existing) | HTML render with @kyc_dashboard hash | N/A |
| `SupportAgentsController#kyc_run_output` | `report_id` | `show?` (same agent auth) | Turbo Frame `kyc_run_output_<kyc_id>` with panel partial. Each KYC row has its own inline turbo frame for the detail panel. | 404 if report not found or wrong agent |
| `SupportAgentsController#run_with_steps` (existing) | `target_type`, `target_id` | `authorize @support_agent` | HTML: redirect back with flash. turbo_stream: replaces `progress_panel_new` (not present on dashboard — use HTML format via `data-turbo="false"`). | target not found → 404 |
| `InvestorKycsController#toggle_verified` (existing) | *(implicit from `set_investor_kyc` callback)* | controller's own before_action | HTML: redirect to `investor_kyc_url`. To return to dashboard, use `button_to ... data: { turbo: false }` so the redirect navigates naturally. | 422 render :edit |
| ~~CSV export~~ | ~~Removed — not in product design~~ | — | — | — |

**New route:**

| Verb | Path | Action |
|---|---|---|
| GET | `/support_agents/:id/kyc_run_output` | `support_agents#kyc_run_output` |

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params can't set `entity_id`, `user_id` or other ownership fields
- [ ] `kyc_run_output` verifies report belongs to the agent's entity (not just any report_id)

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `kyc_type_stats` | `InvestorKyc.where(entity_id:, completed_by_investor: true).left_joins(latest_report).select("COUNT(*), SUM(CASE...)").group("investor_kycs.type")` — merged stat counts + chart data into single query | `investor_kycs` `[entity_id, completed_by_investor]` | 2 rows max (one per type) | N/A |
| `kyc_top_failures` | `SupportAgentReport.where(support_agent_id:, owner_type: 'InvestorKyc', latest: true).where("JSON_SEARCH(json_fields, 'one', 'blocking', NULL, '$**.severity') IS NOT NULL")`. Plucks `owner_id` + `json_fields`, aggregates in Ruby. Batch-loads investor names via single `InvestorKyc.joins(:investor).pluck` to avoid N+1. | `support_agent_reports` `[support_agent_id, owner_type, latest]` (needs verification) | ≤ 5000 | Ruby aggregation after pluck; includes affected list per failure |
| `kyc_filtered_records` | `InvestorKyc.where(entity_id:, completed_by_investor: true).includes(:investor, :support_agent_report)` | `investor_kycs` `[entity_id]` | ≤ 5000, paginated to 10 | `includes(:investor)` |
| Fund filter | `WHERE id IN (SELECT investor_kyc_id FROM capital_commitments WHERE fund_id = ?)` | `capital_commitments` `[fund_id]` (existing) | Subset | Subquery, not join |
| `kyc_doc_ratios` (required names) | `FormCustomField.where(form_type_id:, field_type: 'File', required: true).pluck(:form_type_id, :label, :name)` | `form_custom_fields` `[form_type_id]` | ≤ 10 per form type | Grouped by form_type_id |
| `kyc_doc_ratios` (uploaded names) | `Document.where(owner_type: 'InvestorKyc', owner_id: kyc_ids).pluck(:owner_id, :name)` | `documents` `[owner_type, owner_id]` | ≤ page size × docs per KYC | Grouped by owner_id |
| `kyc_run_output` | `SupportAgentReport.find(report_id)` | PK | 1 | None |

**LEFT JOIN for stats:** The `support_agent_reports` join uses `latest = true AND support_agent_id = @support_agent.id AND owner_type = 'InvestorKyc'`. Verify there is a composite index on `[owner_type, owner_id, support_agent_id, latest]` or at minimum `[support_agent_id, latest]`.

**"Partially Failed" classification in SQL:**

```sql
-- Uses SUM(CASE WHEN ... THEN 1 ELSE 0 END) per bucket, not a single CASE.
-- Expired is mutually exclusive: all other buckets include AND NOT expired.
-- JSON_SEARCH used instead of LIKE (LIKE fails on MySQL's binary JSON storage).

SUM(CASE WHEN expiry_date < CURDATE() THEN 1 ELSE 0 END) AS expired,
SUM(CASE WHEN sar.id IS NULL AND NOT_EXPIRED THEN 1 ELSE 0 END) AS pending,
SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(sar.json_fields, '$.final_status')) = 'ready'
          AND NOT_EXPIRED THEN 1 ELSE 0 END) AS successful,
SUM(CASE WHEN ((JSON_UNQUOTE(JSON_EXTRACT(sar.json_fields, '$.final_status')) = 'blocked'
               AND JSON_SEARCH(sar.json_fields, 'one', 'success', NULL, '$**.severity') IS NULL
               AND JSON_SEARCH(sar.json_fields, 'one', 'info', NULL, '$**.type') IS NULL)
              OR JSON_UNQUOTE(JSON_EXTRACT(sar.json_fields, '$.final_status')) = 'error')
          AND NOT_EXPIRED THEN 1 ELSE 0 END) AS failed,
SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(sar.json_fields, '$.final_status')) = 'blocked'
          AND (JSON_SEARCH(sar.json_fields, 'one', 'success', NULL, '$**.severity') IS NOT NULL
               OR JSON_SEARCH(sar.json_fields, 'one', 'info', NULL, '$**.type') IS NOT NULL)
          AND NOT_EXPIRED THEN 1 ELSE 0 END) AS partial
```

> **Note:** `final_status = "error"` (agent runtime errors) is classified as Failed. Expired takes priority — checked via separate SUM, and all other buckets exclude expired KYCs. Uses `JSON_SEARCH` (not `LIKE`) because MySQL stores JSON in binary format; `LIKE` operates on the raw bytes and fails to match reliably.

**Reviewer checks**
- [ ] Every query is scoped by `entity_id`, or explains why not
- [ ] No N+1 on list pages. No unbounded loads (use `find_each` / `in_batches`)
- [ ] Confirm composite index exists on `support_agent_reports` for the LEFT JOIN
- [ ] JSON_SEARCH queries on json_fields are acceptable at current scale but should be flagged if entity exceeds 10,000 reports

---

## Transactions, Locking and Concurrency

N/A — the dashboard is read-only. Inline actions (Mark Verified) use existing controller actions that handle their own transactions. Batch "Run All Pending" uses existing `SupportAgentJob` concurrency handling.

**Reviewer checks**
- [ ] Confirmed: no new write paths introduced by the dashboard itself

---

## Background Jobs

N/A — no new jobs. "Run Agent on All Pending" uses existing `SupportAgentJob` in `:adhoc_batch` mode. "Re-run Agent" uses existing `SupportAgentJob` in `:single_company_with_steps` mode.

**Reviewer checks**
- [ ] Confirmed: no new job classes or cron entries

---

## External Integrations

N/A — no external API calls. The KYC agent's LLM calls are handled by the existing agent pipeline, not by the dashboard.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `ActiveRecord::RecordNotFound` | `kyc_run_output` when `report_id` invalid | Rails default 404 handler | 404 page | Standard Rails log |
| Query timeout | `kyc_type_stats` on very large entity | Rails default 500 handler | Generic error page | Rails error log |

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors silently
- [ ] Log lines carry the ids needed to debug (entity, record, external id)
- [ ] `kyc_run_output` handles missing report gracefully (404, not 500)

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `SupportAgentPolicy#show?` gates the dashboard tab (same as all other tabs). `kyc_run_output` reuses the same policy. Inline actions use their respective policies (`InvestorKycPolicy` for verify). |
| Tenant isolation | Every query scoped by `@support_agent.entity_id`. The agent itself is scoped by `policy_scope` in the controller. Report lookup in `kyc_run_output` additionally verifies `report.support_agent_id == @support_agent.id`. |
| Secrets | N/A — no secrets handled by dashboard. |
| Input / output sanitisation | Filter params are allowlisted (dropdowns with fixed values) or parameterized (search, dates). No raw SQL interpolation. All output is ERB-escaped. |
| Mass assignment | No write to `InvestorKyc` or `SupportAgentReport` from dashboard. Inline actions use existing strong params. |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route, job or MCP tool
- [ ] `kyc_run_output` cannot be used to read reports from other entities

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None new |
| Feature flag | None — the tab appears automatically for KycOnboardingAgent type. To disable, the agent type check in `show.html.erb` is the gate. |
| Cron / schedules | None new |
| Deploy order | Code deploy only — no migrations |
| Rollback | Revert the commits. No data cleanup needed (dashboard is read-only). |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused, and safe to roll back
- [ ] No migration ordering concerns

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/ai/support_agents/kyc_agent_dashboard.feature` | None (uses real DB, no external calls) | `:entity`, `:support_agent` (type: KycOnboardingAgent), `:investor_kyc` (individual + non_individual), `:support_agent_report` with json_fields fixtures, `:capital_commitment` (for fund filter), `:investor`, `:document` (for doc tracking), `:form_custom_field` (File type, required) | `kyc_agent_dashboard_steps.rb`: "I see {int} stat cards", "the {string} card shows {int}", "the table shows {int} rows", "I click the {string} stat card", "I see the run output panel", "I see {int} matched items", "the Docs column shows {string}" |

Reuses existing step defs from `support_agents_steps.rb` (agent creation, batch run) and `investor_kycs_steps.rb` (KYC creation).

---

### Product feedback #12: Show KYC name instead of investor name

**`kyc_top_failures`** (AgentReportsQuery) — change pluck to include `investor_kycs.full_name`:

**Current:** `InvestorKyc.where(id:).joins(:investor).pluck(:id, "investors.investor_name").to_h`
**New:** `InvestorKyc.where(id:).left_joins(:investor).pluck(:id, :full_name, "investors.investor_name")` → build hash as `{ id => full_name.presence || investor_name || "Unknown" }`

Uses `left_joins` (not `joins`) so KYCs without an investor record don't disappear from results.

Hash key renamed from `investor_name` to `kyc_name` in the returned data structure.

**Views:** Both `_kyc_dashboard_charts.html.erb` (line 111) and `_kyc_dashboard_type_columns.html.erb` (line 139) change `inv[:investor_name]` → `inv[:kyc_name]`. Comment headers updated accordingly.

**Reviewer checks:**
- [ ] `full_name.presence` used (not just `full_name`) — blank string should fall back to investor name
- [ ] `left_joins` used so KYCs without investor association still appear
- [ ] Both ERB files updated to use `kyc_name` key

---

### Product feedback (call 2026-11-09): Use submission_status for Agent Metrics

**`kyc_type_stats`** (AgentReportsQuery) — change scope from `.completed` to `.where(submission_status: "completed")`:

**Current:** `InvestorKyc.where(entity_id:).completed.where(type: "IndividualKyc").count`
**New:** `InvestorKyc.where(entity_id:, submission_status: "completed", type: "IndividualKyc").count`

Same change in `kyc_base_scope` (used for the table query) and `kyc_pending_ids` (used for the "Run Agent on All Pending" button).

**Reviewer checks:**
- [ ] All three methods updated: `kyc_type_stats`, `kyc_base_scope`, `kyc_pending_ids`
- [ ] Row 1 (KYC Form Status) scopes are NOT changed — they use their own independent scopes
- [ ] `submission_status` column is indexed (check schema)

---

### Product feedback (call 2026-11-09): Remove ID column, hyperlink KYC name

**`_kyc_dashboard_table.html.erb`:**
- Remove `<th>` for ID column from table header
- Remove `<td><%= link_to kyc.id, investor_kyc_path(kyc) %></td>` from table body
- Change name column from plain text to: `<td><%= link_to (kyc.full_name.presence || kyc.investor&.investor_name || "—"), investor_kyc_path(kyc), data: { turbo: false } %></td>`
- Remove KYC ID reference from search placeholder text (if any)

**Reviewer checks:**
- [ ] ID column fully removed (both `<th>` and `<td>`)
- [ ] Name column is now a link with `data: { turbo: false }` for full-page navigation
- [ ] Fallback chain preserved: `full_name → investor_name → "—"`

---

### Product feedback (call 2026-11-09): Color consistency

**Iteration 1:** Standardized badge hex values to `#198754` / `#dc3545` and blue headers to white text.

**Iteration 2 (2026-11-11):** Product feedback that solid dark badges are too dark. Item row badges now use Bootstrap opacity classes (`bg-success bg-opacity-10 text-success` etc.) matching step header badges. Both badge levels use the same light style.

**`_kyc_run_output_panel.html.erb`:**
- Step header badges: `bg-success bg-opacity-10 text-success` (unchanged)
- Item row badges: switched from solid `background: #198754; color: #fff` to `bg-success bg-opacity-10 text-success` (Passed), `bg-danger bg-opacity-10 text-danger` (Failed), `bg-warning bg-opacity-10 text-warning` (Warning)
- Inner table headers: blue `#0d6efd` with white text (unchanged)

**`_kyc_dashboard_tab.html.erb`:**
- Added info message next to Agent Metrics heading: "KYCs with submitted status as complete are considered for agent run"

**Reviewer checks:**
- [ ] Item row badges use `bg-opacity-10` classes, not inline color styles
- [ ] Step header and item row badges use the same visual style
- [ ] All blue headers use white text (`color: #fff`)
- [ ] Info message visible next to Agent Metrics heading

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | `kyc_dashboard_data` uses SQL COUNT, not Ruby `present?` on relations |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | Stats use SQL aggregation. Table uses Pagy (LIMIT/OFFSET). No Ruby-side dedup. |
| Select only needed columns when loading many records; no speculative `includes` | Applies | Table query uses `includes(:investor)` (needed for name column) and `:support_agent_report` (needed for status). No speculative includes. |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` | Applies | Submitted On and Agent Run On columns use `l(date, format:)` |
| Date inputs use `f.date_field` / `date_field_tag` | Applies | Date range filter uses `date_field_tag` |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | All queries scoped by `entity_id`. `show` and `kyc_run_output` both call `authorize`. |
| MCP tool surfaces changed only via the ontology YAML | N/A | No MCP tools affected |
| Cucumber only (no RSpec) | Applies | All tests in Cucumber feature file |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | Applies | Will run rubocop on all new/modified files |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
