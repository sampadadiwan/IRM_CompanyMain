# Obligation Matrix Fixes — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

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

- **Tag splitting uses `String#split(",")` with `map(&:strip).reject(&:blank?)` — see [Method Contracts](#method-contracts)**. Verify that edge cases (trailing comma, empty string, nil) don't produce unexpected results.
- **`resolve_step_ui_target` condition change `count == 1` → `count >= 1` — see [Method Contracts](#method-contracts)**. This is the dispatch fix; confirm the Entity fallback only fires for truly empty results.
- **Dual Turbo Stream replace targets in controller `run` action — see [Controllers, Params and Responses](#controllers-params-and-responses)**. Both `progress_panel_#{report.id}` and `cp_cs_progress_wrapper` must be targeted.
- **Dual form helpers (`legal_category_form_options` vs `legal_category_options`) — see [Method Contracts](#method-contracts)**. Verify form views use the string-key helper, filter views use the integer helper.
- **Subquery-based fund/stakeholder filtering — see [Queries and Indexes](#queries-and-indexes)**. Avoids polymorphic JOIN issues but relies on entity_id scoping for performance.

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① Tag Splitter | `app/packs/ai/support_agents/services/side_letter_obligation_agent.rb` | Modified | `split_investment_doc_tags`, `investment_tag_conditions` methods |
| ② Target Resolver | `app/packs/ai/support_agents/services/side_letter_obligation_agent.rb` | Modified | `portfolio_investment_targets` method |
| ③ Dispatch Router | `app/packs/ai/support_agents/jobs/support_agent_job.rb` | Modified | `resolve_step_ui_target` method |
| ④ Pipeline | `app/packs/ai/support_agents/services/cp_cs_extraction_agent.rb` | Modified | All pipeline steps, `targets`, `config_issues`, `process_batch` |
| ④ Pipeline | `app/packs/ai/support_agents/controllers/support_agents_controller.rb` | Modified | `run` action Turbo Stream response |
| ④ Pipeline | `app/packs/ai/support_agents/views/support_agents/_agent_run_modal.html.erb` | Modified | Estimated closing date field |
| ⑤ Matrix | `app/packs/funds/side_letters/controllers/side_letter_obligations_controller.rb` | Modified | Context-aware scoping, fund/stakeholder subqueries |
| ⑤ Matrix | `app/packs/funds/side_letters/views/side_letter_obligations/index.html.erb` | Modified | Context-driven title, banner, filters, hidden fields |
| ⑤ Matrix | `app/packs/funds/side_letters/views/side_letter_obligations/_matrix.html.erb` | Modified | Legal category column visibility, DataTables wiring |
| ⑤ Matrix | `app/packs/funds/side_letters/views/side_letter_obligations/_side_letter_obligation.html.erb` | Modified | Row partial with context-aware linking |
| ⑤ Matrix | `app/packs/funds/side_letters/views/side_letter_obligations/show.html.erb` | Modified | Portfolio obligation show page linking |
| ⑥ Form Helpers | `app/packs/funds/side_letters/helpers/side_letter_obligations_helper.rb` | Modified | `legal_category_form_options` method added |
| ⑥ Forms | `app/packs/funds/side_letters/views/side_letter_obligations/_form.html.erb` | Modified | Uses `legal_category_form_options`, hides MFN for CP/CS |
| ⑥ Forms | `app/packs/funds/side_letters/views/side_letter_obligations/_inline_edit_row.html.erb` | Modified | Uses `legal_category_form_options` |
| ⑦ Progress Panel | `app/packs/funds/portfolios/views/portfolio_investments/show.html.erb` | Modified | `cp_cs_progress_wrapper` div, Run button |
| ⑦ Progress Panel | `app/packs/ai/support_agents/views/support_agents/_progress_panel.html.erb` | Reused | Panel partial (unchanged) |
| Docs | `app/packs/core/documents/views/documents/_index.html.erb` | Modified | CP/CS agent modal on documents page |
| Docs | `app/packs/core/documents/views/documents/_document.html.erb` | Modified | Per-document Run button |
| Tests | `features/ai/cp_cs_extraction_agent.feature` | New | 10 Cucumber scenarios |
| Tests | `features/step_definitions/cp_cs_extraction_agent_steps.rb` | New | Step definitions for CP/CS agent |
| Design docs | `docs/cp_cs_extraction_agent/business_design.md` | New | Business design document |
| Design docs | `docs/cp_cs_extraction_agent/technical_design.md` | New | Technical design document |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/<domain>/<sub_domain>/...`) and Packwerk boundaries

---

## Schema Detail

N/A — no table or column changes. All fixes are behavioral (code-level).

---

## Method Contracts

**`SideLetterObligationAgent`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#split_investment_doc_tags(agent_record)` | `SupportAgent` | `Array<String>` (trimmed, non-blank tags) | None | None | Yes |
| `#investment_tag_conditions(tags)` | `Array<String>` | Arel OR node | None | None | Yes |
| `#portfolio_investment_targets(entity_id, agent_record)` | `Integer`, `SupportAgent` | `ActiveRecord::Relation<PortfolioInvestment>` | None | None (read-only) | Yes |

**`SupportAgentJob`** (Job)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#resolve_step_ui_target(support_agent, target_id)` | `SupportAgent`, `Integer/String` | `Array` of target records | `ActiveRecord::RecordNotFound` if target_id invalid | None | Yes |

**`SideLetterObligationsHelper`** (Helper)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#legal_category_options` | None | `Array<[String, Integer]>` — humanized label + integer enum value | None | None | Yes |
| `#legal_category_form_options` | None | `Array<[String, String]>` — humanized label + string enum key | None | None | Yes |

**`CpCsExtractionAgent`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#targets(entity_id)` | `Integer`, `PortfolioInvestment`, or `Investor` | `Array` or `Relation` of PortfolioInvestments | None | None (read-only) | Yes |
| `.config_issues(support_agent)` | `SupportAgent` | `Array<String>` of issue messages | None | None | Yes |
| `.process_batch(opts)` | keyword args | `Hash` with `:successes`, `:errors` | None | Creates SideLetterObligations, SupportAgentReports | No — creates records |

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] Anything a retry can repeat is idempotent

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `SideLetterObligationsController#index` | `context` (query param, not strong params), `fund_id`, `stakeholder_id`, Ransack `q` hash | `authorize SideLetterObligation` + `policy_scope` | Rendered index page | N/A (always renders) |
| `SideLetterObligationsController#update` | `side_letter_obligation: [:title, :legal_category, :obligation_type, ...]` | `authorize @obligation` | Turbo Stream replace row | 422 + form errors |
| `SupportAgentsController#run` | `target_id`, `estimated_closing_date` | Existing `authorize` | Turbo Stream with dual replace targets | Flash error |

The `run` action's Turbo Stream response sends two `turbo_stream.replace` calls:
1. `progress_panel_#{@report.id}` — targets the panel by report ID (for re-runs)
2. `cp_cs_progress_wrapper` — targets the fixed wrapper (for first runs and cache restores)

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params can't set `entity_id`, `user_id` or other ownership fields

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `portfolio_investment_targets` | `PortfolioInvestment.joins(:documents).where(entity_id:).where(tag LIKE conditions)` | `documents.owner_type, owner_id` + `entity_id` | ≤ 200 per entity | None (returns relation) |
| `SideLetterObligationsController#index` fund filter | `SideLetterObligation.where(id: commitment_subquery).or(.where(sourceable_type: 'PI', sourceable_id: pi_subquery))` | `side_letter_obligations.id`, `capital_commitments.fund_id`, `portfolio_investments.fund_id` | ≤ 500 per entity | `includes(:owner_user, :tasks, side_letter: ...)`, `preload(:sourceable)` |
| `SideLetterObligationsController#index` stakeholder filter | `.where(sourceable_type: 'PortfolioInvestment', sourceable_id: pi_subquery)` | `portfolio_investments.portfolio_company_id` | ≤ 100 per company | Same as above |
| `SideLetterObligationsController#index` context filter | `.where(legal_category: [:condition_precedent, :condition_subsequent])` | `side_letter_obligations.legal_category` | ≤ 200 per entity | Same as above |

**Reviewer checks**
- [ ] Every query is scoped by `entity_id`, or explains why not
- [ ] No N+1 on list pages. No unbounded loads (use `find_each` / `in_batches`)

---

## Transactions, Locking and Concurrency

N/A — the obligation upsert uses the existing transaction boundary in `upsert_portfolio_obligations` (unchanged). No new multi-row writes or concurrency concerns introduced.

---

## Background Jobs

No new jobs added. The existing `SupportAgentJob` is used unchanged; only the `resolve_step_ui_target` method within it is modified (condition change from `count == 1` to `count >= 1`).

**Reviewer checks**
- [ ] A job that runs twice, or out of order, is harmless — verified: the upsert deduplicates on source_clause, so re-runs are idempotent
- [ ] No new cron entries needed

---

## External Integrations

| Call | Method + path | Auth | Timeouts | Rate limit handling | Error → exception |
|---|---|---|---|---|---|
| LLM extraction | `LlmService.ruby_llm_chat` → OpenAI / Anthropic | API key from credentials | Existing LLM service timeout | N/A (single call per doc) | `StandardError` caught in `extract_obligations` |

No new external integrations. The LLM calls are part of the existing extraction pipeline.

**Reviewer checks**
- [ ] Secrets never logged, and the request/response logging level is appropriate
- [ ] Every non-2xx status maps to a named exception

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `StandardError` (LLM failure) | `CpCsExtractionAgent#extract_obligations` | `rescue` block in same method | Step marked "failed" on progress panel | `Rails.logger.error` with agent name and message |
| `ActiveRecord::RecordNotFound` | `resolve_step_ui_target` Entity.find | Not caught (propagates to job error handler) | Job fails; progress panel shows last known state | Sidekiq retry + Rails logger |
| `ArgumentError` (legal_category) | Rails enum setter | **Fixed by this change** — no longer raised | Previously: 500 error. Now: form saves correctly | No longer occurs |

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors silently
- [ ] Log lines carry the ids needed to debug (entity, record, external id)

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `policy_scope(SideLetterObligation)` on index; `authorize @obligation` on member actions. Entity scoping via policy. |
| Tenant isolation | All queries scoped by `entity_id` via policy scope. `portfolio_investment_targets` explicitly filters by entity_id. |
| Secrets | No new secrets. LLM API keys from existing credentials. |
| Input / output sanitisation | `context` param only accepts `cp_cs`, `side_letter`, or nil. No raw SQL interpolation — uses ActiveRecord parameterized queries and Arel. |
| Mass assignment | No changes to strong params. `legal_category` is in existing permitted params; the fix is in the form helper output, not the controller. |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route, job or MCP tool

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None new |
| Feature flag | None — fixes are behind the existing agent license flag |
| Cron / schedules | None new |
| Deploy order | Code deploy only (no migrations). `bundle exec cap staging deploy` |
| Rollback | Revert the branch merge. No data cleanup needed — obligation records created by the fixed agent are valid and follow the same schema as before. |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused, and safe to roll back

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/ai/cp_cs_extraction_agent.feature` | WebMock for LLM API calls | `:entity`, `:support_agent`, `:portfolio_investment`, `:document` | `cp_cs_extraction_agent_steps.rb` — agent setup, tag config, document tagging, extraction assertions |
| `features/fund/side_letter_matrix.feature` | None | Reuses existing obligation factories | Reuses existing obligation matrix steps |
| `features/fund/side_letter_obligation_e2e.feature` | None | Reuses existing obligation factories | Reuses existing obligation form steps |

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | `split_investment_doc_tags` uses `reject(&:blank?)` on strings (not relations). Controller uses `.present?` only on string params. |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | Target query uses `distinct` implicitly via joins. Batch extraction iterates a bounded array (≤200 PIs). |
| Select only needed columns when loading many records; no speculative `includes` | Applies | Matrix uses `includes` for owner_user, tasks, side_letter chain — all rendered in the view. `preload(:sourceable)` for polymorphic. |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy`; no human-format `strftime` | N/A | No new date rendering. Existing date columns rendered by the unchanged matrix partial. |
| Date inputs use `f.date_field` / `date_field_tag` | Applies | Estimated closing date uses `f.date_field`. |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | `policy_scope` on index; `authorize` on member actions; entity_id in target queries. |
| MCP tool surfaces changed only via the ontology YAML | N/A | No MCP tool changes. |
| Cucumber only (no RSpec) | Applies | All new tests are Cucumber scenarios. |
| `bundle exec rubocop` clean | Applies | No new rubocop violations introduced. |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
