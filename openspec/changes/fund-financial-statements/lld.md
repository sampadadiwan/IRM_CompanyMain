# Fund Financial Statements from Account Entries — Low-Level Design

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

- **Engine footprint is four touches**: a `TYPES` entry, one `when` in `RunFormula`, an exclusion in `RunFormulas#formulas_in_scope`, and a new always-true step `refresh_financial_statements` after `generate_soa` — see [File Map](#file-map) ④. Check none of them alters a run that has no statement formula.
- **Calculator takes a `base:` relation** (`AccountEntry` vs `AccountEntrySqlite`) and must use only ActiveRecord grouping that works on both MySQL and SQLite — see [Queries and Indexes](#queries-and-indexes).
- **"Latest cumulative value at date"** uses a max-date-per-pair subquery joined back; this is the only non-trivial SQL — see Q4.
- **Generate concurrency** relies on "no Pending run" + unique `[fund_id, start_date, end_date]` + a row lock on the statement — see [Transactions](#transactions-locking-and-concurrency).
- **Unlock path** is the only change to an existing controller; when no locked statement overlaps it must be byte-identical — see [Controllers](#controllers-params-and-responses).

---

## File Map

Pack: `app/packs/funds/financial_statements/` (new sub-domain of the `funds` pack; no new package.yml).

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `.../financial_statements/models/financial_statement_definition.rb` | New | Core + schedule statements; `core?`, `columns` |
| ① | `.../models/financial_statement_account.rb` | New | Typed account; delete guard |
| ① | `.../models/financial_statement_mapping_rule.rb` | New | (entry_type, name) → account / excluded |
| ① | `.../models/financial_statement_layout_row.rb` | New | Ordered rows; `subtotal_value` |
| ① | `.../models/financial_statement_setting.rb` | New | Fiscal year, NAV/capital entries |
| ① | `.../services/financial_statement_setup.rb` | New | Ensure setting, core definitions, formula exist |
| ① | `.../controllers/financial_statement_mappings_controller.rb` | New | Mapping tab, unmapped, preview |
| ① | `.../controllers/financial_statement_accounts_controller.rb` | New | Account CRUD |
| ① | `.../controllers/financial_statement_mapping_rules_controller.rb` | New | Rule CRUD |
| ① | `.../controllers/financial_statement_definitions_controller.rb` | New | Statement/schedule CRUD |
| ① | `.../controllers/financial_statement_layouts_controller.rb` | New | Layout edit + reorder |
| ① | `.../controllers/financial_statement_settings_controller.rb` | New | Settings update |
| ①⑥ | `.../views/financial_statement_*/**` | New | Tabs, tables, forms, frames |
| ①⑤⑥ | `.../policies/financial_statement_*_policy.rb` (one per model) | New | Delegates to `FundPolicy#show?/#update?`, `entity_id` scope |
| ② | `.../models/financial_statement_mapping_suggestion.rb` | New | Lifecycle, `approve!`, `discard!` |
| ② | `.../jobs/financial_statement_mapping_suggest_job.rb` | New | LLM extraction + reconciliation |
| ② | `.../services/financial_statement_mapping_prompt.rb` | New | Prompt + JSON schema + parser |
| ② | `.../controllers/financial_statement_mapping_suggestions_controller.rb` | New | Upload, show, approve, discard, retry |
| ③ | `.../services/financial_statement_calculator.rb` | New | Figures, checks, unmapped (pure) |
| ④ | `app/packs/funds/funds/models/fund_formula.rb` | Modified | `TYPES` += `GenerateFinancialStatementLines`; constant `FINANCIAL_STATEMENTS_TAG` |
| ④ | `app/packs/allocation_engine/account_entry_allocation/run_formula.rb` | Modified | `when "GenerateFinancialStatementLines"` |
| ④ | `app/packs/allocation_engine/account_entry_allocation/generate_financial_statement_lines.rb` | New | Op: calculator → `AccountEntrySqlite` rows |
| ④ | `app/packs/allocation_engine/account_entry_allocation/run_formulas.rb` | Modified | `formulas_in_scope` exclusion; step `refresh_financial_statements` |
| ④ | `app/packs/allocation_engine/account_entry_allocation/run_formulas.md` | Modified | Document the rule type, exclusion and step |
| ⑤ | `.../models/financial_statement.rb` | New | Record, `lockable?`, `comparative_for`, `drift` |
| ⑤ | `.../services/financial_statement_generate.rb` | New | Guards, run creation, enqueue |
| ⑤ | `.../services/financial_statement_lock.rb` | New | Lock + `frozen_data` |
| ⑤ | `.../jobs/financial_statement_refresh_job.rb` | New | Checks/unmapped after run |
| ⑥ | `.../controllers/financial_statements_controller.rb` | New | index/show/create/regenerate/lock/export |
| ⑥ | `.../services/financial_statement_xlsx.rb` | New | caxlsx workbook, one sheet per definition |
| ⑥ | `.../services/financial_statement_pdf.rb` + `views/financial_statements/pdf.html.erb` | New | wicked_pdf, DRAFT watermark |
| ⑦ | `app/packs/funds/funds/controllers/allocation_runs_controller.rb` | Modified | `#unlock`, `#unlock_all` call guard |
| ⑦ | `app/packs/funds/funds/views/funds/_allocation_runs.html.erb` | Modified | Action-summary popup when locked statements overlap |
| ⑦ | `.../services/financial_statement_unlock_guard.rb` | New | `affected`, `demote!` |
| ⑦ | `.../mailers/financial_statement_notifier.rb`, `financial_statement_mailer.rb` + view | New | Noticed event + email |
| UI | fund Actions menu partial (closed-end and evergreen) | Modified | "Financial Statements" link |
| Routes | `config/routes/fund.rb` | Modified | Nested resources |
| DB | `db/migrate/*_create_financial_statement_tables.rb`, `db/schema.rb`, `db/schema_test.rb` | New / Modified | Six tables |
| Tests | `features/funds/financial_statements/*.feature`, `features/step_definitions/financial_statement_steps.rb`, `spec/factories/financial_statement*.rb` | New | See [Test Plumbing](#test-plumbing) |
| Docs | `docs/user_guides/financial_statements.md` | New | User guide with FAQ |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/<domain>/<sub_domain>/...`) and Packwerk boundaries
- [ ] `allocation_engine` only references `FinancialStatementCalculator` and `FinancialStatementRefreshJob` (two constants) from the new sub-domain

---

## Schema Detail

All six tables are new; nothing existing changes. Every table carries `entity_id` (NOT NULL, FK, indexed) and `fund_id` (NOT NULL, FK, indexed) for tenant scoping and `Fund has_many … dependent: :destroy`.

**`financial_statement_settings`** (new): per-fund settings for YTD and checks.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `fund_id` | Added | bigint | — | no | — | unique | One settings row per fund |
| `fiscal_year_start_month` | Added | integer | — | no | 1 | — | YTD start; integer 1–12 validated |
| `nav_entry_type` / `nav_entry_name` | Added | string | 60 / 125 | yes | nil | — | Match `account_entries.entry_type` (60) / `name` (125) limits |
| `capital_entry_type` / `capital_entry_name` | Added | string | 60 / 125 | yes | nil | — | Same limits; blank skips the check |

**`financial_statement_definitions`** (new): the fund's statements.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `name` | Added | string | 100 | no | — | unique `[fund_id, name]` | Title; renamable |
| `kind` | Added | string | 20 | no | "schedule" | unique `[fund_id, kind]` where kind ≠ schedule (validated in model; MySQL has no partial index) | Finds core statements |
| `column_style` | Added | string | 12 | no | "for_period" | — | at_date / for_period |
| `position` | Added | integer | — | no | 0 | — | Order |

**`financial_statement_accounts`** (new)

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `name` | Added | string | 100 | no | — | unique `[fund_id, name]` | FS entry `name` is "YTD " + name ≤ 104 < 125 |
| `account_type` | Added | string | 12 | no | — | — | asset/liability/capital/income/expense/gain_loss |
| `behaviour` | Added | string | 10 | no | — | — | balance/movement (default set in model by type) |
| `flip_sign` | Added | boolean | — | no | false | — | Sign normalisation |

**`financial_statement_mapping_rules`** (new)

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `entry_type` | Added | string | 60 | no | — | unique `[fund_id, entry_type, name]` | Match key |
| `name` | Added | string | 125 | no | "" | (in unique) | "" = any name; NOT NULL so the unique index works (MySQL allows duplicate NULLs) |
| `financial_statement_account_id` | Added | bigint | — | yes | nil | FK + index | Target; null iff excluded (model validation) |
| `excluded` | Added | boolean | — | no | false | — | Explicit exclusion |

**`financial_statement_layout_rows`** (new)

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `financial_statement_definition_id` | Added | bigint | — | no | — | FK; index `[definition_id, position]` | Statement it belongs to |
| `position` | Added | integer | — | no | 0 | (in index) | Order |
| `row_type` | Added | string | 10 | no | — | — | heading/account/subtotal |
| `label` | Added | string | 150 | yes | nil | — | Heading/subtotal text; account rows use account name |
| `financial_statement_account_id` | Added | bigint | — | yes | nil | FK + index | Account rows; enables delete guard |
| `subtotal_of` | Added | json | — | yes | nil | — | Array of layout row ids (same definition, validated) |

**`financial_statements`** (new)

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `start_date`, `end_date` | Added | date | — | no | — | unique `[fund_id, start_date, end_date]` | One set per period |
| `status` | Added | string | 10 | no | "draft" | — | draft/locked |
| `accounting_allocation_run_id` | Added | bigint | — | yes | nil | FK `allocation_runs` | Source run |
| `statements_allocation_run_id` | Added | bigint | — | yes | nil | FK + index | Refresh lookup; nullify on run destroy |
| `checks` | Added | json | — | yes | nil | — | `[{key, status, diff}]` |
| `unmapped_count` | Added | integer | — | no | 0 | — | Lock gate |
| `refreshed_at` | Added | datetime | — | yes | nil | — | Refresh done for current run |
| `frozen_data` | Added | json | — | yes | nil | — | Locked figures + mapping/layout snapshot |
| `locked_at` / `locked_by_id` | Added | datetime / bigint | — | yes | nil | FK `users` | Audit |

**`financial_statement_mapping_suggestions`** (new)

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `user_id` | Added | bigint | — | no | — | FK | Uploader / toast recipient |
| `as_at_date` | Added | date | — | no | — | — | Reconciliation date |
| `status` | Added | string | 12 | no | "processing" | — | Lifecycle |
| `proposal` | Added | json | — | yes | nil | — | Draft lines/rules + match |
| `error` | Added | text | — | yes | nil | — | Failure reason |

**Migration safety:** new tables only; no lock on existing tables; reversible (`create_table`). Per the repo memory, after `db:migrate` restore `schema.rb`/`schema_test.rb` and hand-insert the six tables, then `db:clean_schema`.

**Reviewer checks**
- [ ] Every new column and index has a "why", and none is unjustified
- [ ] Every foreign key has an index, and every uniqueness rule is enforced by a unique index
- [ ] Column limits match validation limits (name 100, entry_type 60, entry name 125)
- [ ] Migration is reversible and touches no existing table

---

## Method Contracts

**`FinancialStatementCalculator`** (Service, pure)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(fund:, start_date:, end_date:, base: AccountEntry, mapping: nil)` | `mapping` = nil (load from DB) or a `Mapping` value object (draft) | `Result(lines: {account_id => {period:, ytd:, balance:}}, checks: [Check], unmapped: [{entry_type, name, amount}], warnings: [])` | `ArgumentError` if `start_date > end_date` | none | Yes |

**`FinancialStatementSetup`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.ensure!(fund)` | Fund | setting | — | creates setting, 3 core definitions, statement `FundFormula` (tag, sequence = max+1, `formula: "true"`, `entry_type: "Financial Statement"`) if missing | Yes — find_or_create on unique keys |

**`FinancialStatementGenerate`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(fund:, start_date:, end_date:, user:)` | dates, user | `FinancialStatement` | `FinancialStatementGenerate::Refused(message)` for each guard (X1, X2, X3, X15, X16) | creates/updates statement, creates `AllocationRun`, enqueues `AccountEntryAllocationJob` | No-op duplicate prevented by Pending guard (E25) |

**`FinancialStatementLock`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(statement, user:)` | statement, user | statement | `Refused` when not `lockable?` (X8, X9) | writes `frozen_data`, status, audit cols; `statements_allocation_run.update!(locked: true)` | Second call refused (already locked) |

**`FinancialStatement`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#lockable?` | — | Boolean + reason | — | none | Yes |
| `#lines_for(definition)` | definition | rows with column values (draft: FS entries; locked: `frozen_data`) | — | none | Yes |
| `#comparative_for(definition, column)` | | `{values, source: :locked/:computed, drifted:}` | — | calculator call when not locked | Yes |
| `#drift` | — | `[{account, locked, current}]` (locked only) | — | calculator call | Yes |

**`FinancialStatementUnlockGuard`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.affected(fund, start_date = nil, end_date = nil)` | nil dates = whole fund | relation of locked statements | — | none | Yes |
| `.demote!(statements, user:)` | relation | count | — | `update_all(status: "draft")`; one notifier delivery when count > 0 | Yes — second call finds none locked |

**`FinancialStatementMappingSuggestion`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#approve!(user)` | user | true | `ActiveRecord::RecordInvalid`; refused unless `ready` | one transaction: `FinancialStatementSetup.ensure!`, upsert definitions/accounts by name, replace layout rows of touched definitions, upsert rules by key; status `approved` | Refused when not ready |
| `#discard!` | — | true | — | status `discarded` | Yes |

**`AccountEntryAllocation::GenerateFinancialStatementLines`** (Operation)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `generate(ctx)` | ctx with fund, dates, fund_formula, scratch DB | true | re-raises with formula name (existing pattern) | `bulk_insert_records` of `AccountEntrySqlite` rows | Yes — engine deletes this formula's entries first |

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] Anything a retry can repeat is idempotent

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `FinancialStatementsController#index` | `fund_id` | `FundPolicy#show?` + `policy_scope(FinancialStatement)` | HTML | 404 outside entity |
| `#show` (html/xlsx/pdf) | `id`, `definition_id` | `show?` | HTML / file | 404 |
| `#create` | `financial_statement: [:start_date, :end_date]` | `create?` (fund `update?`) | Turbo Stream prepend row | flash alert with `Refused#message` |
| `#regenerate` | `id` | `update?` | Turbo Stream replace | flash alert |
| `#lock` | `id` | `lock?` (fund `update?`) | Turbo Stream replace | flash alert |
| `FinancialStatementMappingsController#show` | `fund_id`, `period_start`, `period_end` | fund `show?` | HTML | 404 |
| `FinancialStatementAccountsController#create/update/destroy` | `financial_statement_account: [:name, :account_type, :behaviour, :flip_sign]` | fund `update?` | Turbo Stream | 422 form / alert (in use) |
| `FinancialStatementMappingRulesController#create/update/destroy` | `financial_statement_mapping_rule: [:entry_type, :name, :financial_statement_account_id, :excluded]` | fund `update?` | Turbo Stream (rules + preview + unmapped frames) | 422 |
| `FinancialStatementDefinitionsController#create/update/destroy` | `financial_statement_definition: [:name, :column_style, :position]` (`kind` never permitted) | fund `update?` | Turbo Stream | 422 / alert (core) |
| `FinancialStatementLayoutsController#update` / `#sort` | `rows: [:id, :position, :row_type, :label, :financial_statement_account_id, subtotal_of: []]` | fund `update?` | Turbo Stream | 422 |
| `FinancialStatementSettingsController#update` | `financial_statement_setting: [:fiscal_year_start_month, :nav_entry_type, :nav_entry_name, :capital_entry_type, :capital_entry_name]` | fund `update?` | Turbo Stream | 422 |
| `FinancialStatementMappingSuggestionsController#create` | `file`, `as_at_date` | fund `update?` | redirect to suggestion | 422 (type/size) |
| `…#approve` / `#discard` / `#retry` | `id` | fund `update?` | redirect to Mapping / suggestion | alert |
| `AllocationRunsController#unlock` (modified) | unchanged | unchanged | unchanged + `demote!` | unchanged |
| `AllocationRunsController#unlock_all` (modified) | unchanged | unchanged | unchanged + `demote!` | unchanged |

`fund_id`, `entity_id`, `user_id`, `status`, `kind`, `frozen_data` are always set server-side.

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params can't set `entity_id`, `user_id`, `status`, `kind` or `frozen_data`
- [ ] `unlock`/`unlock_all` produce identical flash/redirect when `affected` is empty

---

## Queries and Indexes

Fund-level filter everywhere: `fund_id = ? AND capital_commitment_id IS NULL AND deleted_at IS NULL AND entry_type <> 'Financial Statement'`. Existing indexes: `fund_id`, `[entity_id, deleted_at, name]`, `[capital_commitment_id, name, reporting_date]`.

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| Calc Q1/Q2/Q3 | `base.where(fund filter, cumulative: false, reporting_date: a..b).group(:entry_type, :name).sum(:amount_cents)` | `fund_id` | ≤ 500 groups | aggregate only |
| Calc Q4 | `SELECT entry_type, name, SUM(amount_cents) FROM base JOIN (SELECT entry_type, name, MAX(reporting_date) d FROM base WHERE fund filter AND cumulative AND reporting_date <= :date GROUP BY entry_type, name) m USING (entry_type, name) WHERE reporting_date = m.d …` (×3 dates) | `fund_id` | ≤ 500 groups | aggregate only |
| Calc Q5 | as Q4 but `capital_commitment_id IS NOT NULL`, `entry_type/name = capital setting`, grouped by `capital_commitment_id` then summed | `[capital_commitment_id, name, reporting_date]` | ≤ folios count | aggregate only |
| Calc Q6 | latest NAV entry ≤ end, fund-level | `fund_id` | 1 | `pick(:amount_cents)` |
| Calc rules | `FinancialStatementMappingRule.where(fund_id:)`, accounts, definitions, layout rows | `fund_id` | ≤ 300 | loaded once |
| Draft display | `AccountEntry.where(fund_id:, fund_formula_id: fs_formula, reporting_date: end).select(:name, :amount_cents, :json_fields)` | `fund_id` | ≤ 2 × accounts | select only needed columns |
| Index list | `FinancialStatement.where(fund_id:).order(end_date: :desc)` | unique idx | ≤ 100 | `includes(:statements_allocation_run, :locked_by)` |
| Unlock popup | `FinancialStatement.where(fund_id:, status: "locked").pluck(:start_date, :end_date)` once per page | unique idx | ≤ 100 | in-memory overlap per row |
| Generate guards | `AllocationRun.where(fund_id:).pending.exists?`; covering Success run `where("start_date <= ? AND end_date >= ?")`, `tag_list` ≠ FS tag | `fund_id` | small | `exists?` / `order(created_at: :desc).first` |

**Reviewer checks**
- [ ] Every query is scoped by `fund_id` (and through it `entity_id`), or explains why not
- [ ] No `account_entries` row load anywhere except the draft display, which selects three columns
- [ ] Q4 SQL is valid on both MySQL and SQLite (no window functions, no MySQL-only syntax)

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Generate | statement find_or_create + AllocationRun create | `fund.with_lock` around guards + create | Double-click / two users (E25) | Pending-run guard + unique `[fund_id, start, end]` |
| Lock | statement + statements run | `statement.lock!` | Lock vs regenerate race | status check inside lock |
| Approve draft | setting, definitions, accounts, layout, rules, suggestion | `suggestion.lock!` | Double approve | status `ready` check |
| Unlock + demote | existing `update_all` then `demote!` (no shared txn) | none | — | demote is idempotent |
| Refresh job | single `update!` | none | Stale refresh overwriting newer run | job ignores runs ≠ `statements_allocation_run_id` |

Notifications are delivered after commit (`deliver_later`), never inside a transaction.

**Reviewer checks**
- [ ] No external HTTP call or email inside a transaction (LLM call is in the job, outside any txn)
- [ ] Lock order is consistent: fund → statement

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `FinancialStatementRefreshJob` | `default` | `RunFormulas#refresh_financial_statements` step | 3, polynomial | `ActiveRecord::RecordNotFound` | ignores non-current run | — |
| `FinancialStatementMappingSuggestJob` | `default` | upload / retry | 0 (user Retry) | — | status must be `processing` | LLM client default |
| `AccountEntryAllocationJob` (existing) | existing | `FinancialStatementGenerate` | existing | existing | Pending-run guard | existing |

**Reviewer checks**
- [ ] A job that runs twice, or out of order, is harmless
- [ ] No cron entries are added

---

## External Integrations

| Call | Method + path | Auth | Timeouts | Rate limit handling | Error → exception |
|---|---|---|---|---|---|
| LLM extraction | `LlmService.ruby_llm_chat(entity:)` via `DocLlmContext` (existing) | Entity keys, else credentials (existing) | RubyLLM defaults | none (single call per upload) | any `RubyLLM::Error` / JSON parse error → suggestion `failed` with message |

**Reviewer checks**
- [ ] Secrets never logged; the prompt contains only the document and entry type/name/amount list
- [ ] Every failure maps to `failed` with a stored, user-readable error

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `FinancialStatementGenerate::Refused` | Generate | controller `rescue` → flash | Guard message (X1, X2, X3, X15, X16) | info log with fund id |
| `FinancialStatementLock::Refused` | Lock | controller → flash | "Map or exclude N entries…" / "Checks must pass" | info |
| `ActiveRecord::RecordInvalid` | CRUD | controller → 422 form | field errors | — |
| `ActiveRecord::DeleteRestrictionError` | account / core definition destroy | controller → flash | in-use / core message (X6, X17) | — |
| Formula error in `GenerateFinancialStatementLines` | engine | existing run failure handling | statement "Failed" + run link (X11) | existing run notification + `AllocationRunReport` |
| LLM / parse error | Suggest job | job `rescue StandardError` → `failed` + toast | Failed + Retry (X12) | error log with suggestion id |
| Refresh job error | Refresh job | retry, then exception notifier | statement stays Generating | error log with run id |

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors silently (the Suggest job stores and logs)
- [ ] Log lines carry fund id, statement id or run id

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | Every controller action `authorize`s; policies delegate to `FundPolicy#show?` (read) / `#update?` (write) of the record's fund |
| Tenant isolation | `policy_scope` = `where(entity_id: user.entity_id)` + fund visibility; records found through `@fund.financial_statements` etc. |
| Secrets | None new; LLM keys via existing `LlmService` |
| Input / output sanitisation | Upload content type and extension whitelisted (pdf, xlsx, xls) ≤ 20 MB; LLM output parsed as JSON and validated against the schema before storing; labels rendered escaped |
| Mass assignment | See permitted params; ownership and status columns never permitted |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route, job or MCP tool (no MCP tools added)

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None new |
| Feature flag | None — inert until a fund saves its first account (no formula, no menu effect beyond the link) |
| Cron / schedules | None |
| Deploy order | Migrations → code |
| Rollback | Revert code; tables can stay. The statement formula rows, if any, are disabled formulas of an unknown type — delete them with the fund's formulas page before rollback |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused, and safe to roll back

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/funds/financial_statements/financial_statement_mapping.feature` | — | `:financial_statement_account`, `_rule`, `_definition`, `_layout_row`, `_setting`, `:account_entry` | `Given Alpha Fund I has statement accounts:` (table), `Given fund-level entries:` (table), `Then the preview of "…" is …` |
| `.../financial_statement_calculator.feature` | — | same | `When I preview the period … to …`, `Then the check "…" is …` |
| `.../financial_statement_ai_draft.feature` | `LlmService.ruby_llm_chat` stubbed to return fixture JSON (`features/support/fixtures/fs_draft.json`) | `:financial_statement_mapping_suggestion` | `When I upload "fs_2025.pdf" as at …` |
| `.../financial_statement_generation.feature` | allocation job run inline (`perform_now`) | `:allocation_run` (Success, locked) | `Given accounting run for … is locked`, `When I generate statements for …` |
| `.../financial_statements.feature` | wicked_pdf output inspected via text | — | `Then the statement shows …`, `When I lock the statements` |
| `.../financial_statement_unlock_guard.feature` | Noticed deliveries checked via existing email steps | users tagged FundAccounting | reuse existing allocation-run unlock steps |

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | Guards use `exists?`; `affected` checked with `exists?` |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | Grouped SQL only; no Ruby dedup |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | Applies | Calculator aggregates; draft display selects `name, amount_cents, json_fields` |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | Applies | Views/exports use `l`; notifier email uses bare `l(date)` |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | Applies | Generate form and as-at date use `f.date_field` |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | See Security Review |
| MCP tool surfaces changed only via the ontology YAML | N/A | No MCP tool added |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | Six feature files |
| `bundle exec rubocop` clean, including `IRM/RelationBlankPresent` | Applies | Run before completion |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
