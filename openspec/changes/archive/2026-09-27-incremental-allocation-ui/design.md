## Context

See proposal.md for motivation, and the two specs for behaviour. Current state this design builds on:

- **`AccountEntryAllocation::IncrementalMigration`**
  (`app/packs/allocation_engine/account_entry_allocation/incremental_migration.rb`):
  - `plan` finds formula edits (tracking / combined / feeder), blockers and warnings from formula text.
  - `enable!` computes corrected tracking starting values from a full scratch SQLite copy (seconds to
    minutes), then writes edits, descriptions, starting values and the fund flag in one transaction.
  - `disable!` restores from the audit trail; `describe!` backfills descriptions.
  - It reports by printing (`say`) and returns symbols. `lib/tasks/incremental_allocation.rake`
    drives it; `reseed_carry_forward` lives in the rake file.
- **Run checks:**
  - `FundFormula` rule types `PreRunCheck` / `PostRunCheck`, evaluated by
    `AccountEntryAllocation::RunChecks` in a `CheckContext` with `CheckHelpers`
    (`docs/modules/allocation/allocation_run_checks.md`).
  - `RunChecks` already evaluates unsaved `FundFormula`s. That is how the fund 342 checks were
    tested before import.
- **Formula text is screened by `ApplicationRecord::SAFE_EVAL_REGEX`**, a substring blocklist:
  `select`, `delete`, `update`, `create`, `save`, … anywhere in the text. Hand-written checks trip
  over it easily; e.g. `delete_prefix` and `deleted_at` are both refused.
- **Fund formulas page:** the "Enable All" dropdown in `fund_formulas/_index.html.erb` (Enable All,
  Disable All, Filter). Formula create is support-only (`FundFormulaPolicy#create?`).
- **Existing patterns reused:**
  - background job + a record in `Pending` + a Turbo frame that reloads itself while pending
    (`AllocationRunReport` and `allocation_run_reports/show.html.erb`)
  - `LlmService.ruby_llm_chat(entity:)` for AI
  - `ImportFundFormula` for the xlsx format
- **Constraints:**
  - Test and dev cache stores are `null_store`/unreliable, so anything shown after a job must be persisted.
  - Tests are Cucumber only.
  - CLAUDE.md large-table rules apply: never load `account_entries` rows; aggregate and `distinct.pluck` only.

## Goals / Non-Goals

**Goals:**
- One service layer that both the UI and the rake tasks call. Rake output is a text rendering of the
  same result object the UI renders.
- Suggested checks are short, helper-based formulas: readable, and immune to the blocklist.
- Everything shown to support was test-run first.

**Non-Goals:**
- Entity-wide switching from the UI (the rake `entity` scope remains for that).
- Automatically re-running allocation periods after a switch. Support starts runs as today; the page
  only tracks them.
- A production replacement for the dev-only `allocation_snapshot` diff. The "Since Inception totals
  match history" post-run check is the production verification.
- AI writing anything to the database without support selecting it.

## Decisions

### D1. One table: `fund_formula_operations`

Columns:

| Column | Notes |
| --- | --- |
| `entity_id`, `fund_id` | |
| `operation` | `enable_incremental`, `disable_incremental`, `reseed_carry_forward`, `suggest_checks` |
| `status` | see below |
| `requested_by_id`, `applied_by_id` | |
| `plan` (json) | preview or suggestion set |
| `result` (json) | |
| `params` (json) | e.g. reseed date, AI requested |
| `error` (text) | |
| `previewed_at`, `applied_at`, timestamps | |

Indexed on `[fund_id, created_at]`.

Status flow:
- `previewing` → `previewed` | `blocked` | `failed`
- then `applying` → `applied` | `refused` | `failed`

Suggestions stop at `previewed` (each "Add selected" is recorded in `result`).

- **Why one table, not `incremental_migrations` plus a suggestions table:** all four operations share
  the same lifecycle (background, preview, maybe apply), audit need and UI (history list, polling
  frame). Suggestion sets must persist between generating and adding, because AI output cannot be
  regenerated and the cache is not dependable.
- **Alternative rejected:** storing state in `fund.json_fields`. No history, and no place for
  multiple-megabyte plans.

### D2. `IncrementalMigration` returns a `Plan`; apply takes the plan

`plan` returns a serialisable `Plan` value:

| Field | Contents |
| --- | --- |
| `edits` | formula_id, sequence, name, pattern, formula_before, formula_after, description_before, description_after |
| `blockers` | message, formula_id |
| `warnings` | |
| `reseeds` | formula_id, date, `{capital_commitment_id => [old_cents, new_cents]}` |
| `fingerprint` | SHA256 of edits (ids + before/after text), reseed formula ids/dates, and the fund flag |

Methods:
- **Preview:** `enable_plan`, `disable_plan` and `reseed_plan(date:, formulas:)` build plans;
  `enable_plan(with_values: true)` fills reseed totals using the full copy.
- **Apply:** `apply!(plan)` re-plans:
  - It compares fingerprints and recomputes reseed totals, refusing if either differs (raises `PlanChanged`).
  - Then it writes in one transaction, as `enable!` does today.
- **Output:** `say` goes away. `IncrementalMigration::TextReport.new(plan).lines` is used by rake.
  The existing `enable!(apply:)` / `disable!` / `describe!` signatures stay as thin compositions
  (plan → print → apply if requested), so rake callers and output are unchanged.
- **`reseed_carry_forward`** logic moves from the rake file into the service (`reseed_plan`); the rake
  task becomes a wrapper.
- **Why recompute totals on apply** (an extra full copy, minutes): uploads can land between preview
  and apply even when no run is active, and a starting value written from stale totals is silently wrong.

### D3. Busy guard: `FundAllocationActivity.busy?(fund)`

A fund is busy if any of these hold:
- `AllocationGroupRun.fund_busy?(fund.id)`, or
- an `AllocationRun` for the fund with status blank or `"Pending"` created in the last
  `STALE_RUN_HOURS` (12), or
- a `fund_formula_operations` row for the fund in `previewing`/`applying`.

Where it is enforced:
- **Operations:** checked when an operation is created (only one active per fund, under a row lock on
  the fund) and again at the start of apply.
- **Allocation runs:** `FundsController#allocate` and the group-run preflight also refuse while an
  operation is `applying`. A run that starts mid-apply would load formulas before the switch, and the
  fund flag after it.
- **Why a 12h window:** a crashed run leaves status `Pending` forever and would block the fund
  permanently. Allocation runs take minutes; 12h is far past any real run.

### D4. Rule-based suggester: `RunCheckSuggestions::Builder`, one private method per rule

`Builder.new(fund).suggestions` runs each rule against a `Context` that loads everything once:
- **Formulas:** all fund formulas (text, rule_type, sequence, name).
- **Custom field forms:** the entity's `FormCustomField`s for `AccountEntry` and `PortfolioInvestment`.
- **Uploaded entries:** `distinct.pluck(:name, :entry_type, :parent_type, capital_commitment_id IS NULL)`
  over `generated: false` rows — a handful of rows, never materialised entries.
- **Folio fields:** folio json_fields keys and unit types (grouped counts).
- **Settings:** unit setting names/keys, tracking currency, portfolio investment currencies.

Each rule returns `Suggestion`s with these fields:
- `key`: a stable rule key; for `allowed_names` it includes the entry type
- `source`: `rule` or `ai`
- `name`, `description`, `rule_type`, `formula`
- `evidence`: `[{formula_id, sequence, name, snippet}]` plus data facts
- `supports_severity`, `severity`

Rules detect patterns in formula text with regexes, the same approach `IncrementalMigration` uses:

| Rule | Detects | Produces |
| --- | --- | --- |
| allowed_names | `quarterly/year_to_date/since_inception("X"` names and name arrays; uploaded `(name, entry_type)` | `allowed_entry_names(type, names)` per entry type allocated by an `-EntryType` formula |
| required_fields | `fund_account_entry.json_fields['k']`, `portfolio_investment.json_fields['k']` in allocation formulas | `required_custom_fields(:account_entries, labels, fund_level_only: true)` / `(:portfolio_investments, labels)` |
| deal_mapping | entry types allocated by formulas whose uploads have `parent_type = PortfolioInvestment` | `entries_mapped_to_portfolio_investment(types)` |
| folio_shares | `capital_commitment.json_fields[<key expr>]` fed from an entry/investment field | `folio_shares_total(:fund_level_udr_code)` (new helper) |
| unit_settings | `fund_unit_setting.json_fields['k']` / `fund_unit_setting.<column>` | `unit_settings_present(%w[k …])` (new helper) |
| fx_rates | tracking currency or foreign instrument currency | `fx_rates_present(within_days: 5)` |
| valuations | fund has portfolio investments | `valuations_present(within_months: 3, severity: :warning)` |
| entries_allocated | any `AllocateAccountEntry*` formula | `fund_entries_allocated`, `fund_entries_tie_to_folios(tolerance: 1.0)` |
| portfolio_tie | `AllocatePortfolioInvestment` formula reading `portfolio_investment.<col>_cents` with no `* -1` | `portfolio_allocations_tie("<name>" => :<col>_cents, …)` |
| since_inception | single-name `since_inception("X", nil, …)` formulas named "Since Inception X" | `since_inception_matches_history(names)` (new helper); suggested before and after the switch |

**Names for allowed_names:**
- **A name in allocation or reporting formula text** is assigned an entry type from its uploads.
- **A name that was never uploaded** takes the entry type of other names in the same array literal
  (e.g. formula 235's expense list).
- **A name uploaded but not totalled by any formula** is deliberately *not* allowed. Flagging it is
  the point of the check.

**New helpers** in `CheckHelpers` (`folio_shares_total`, `unit_settings_present`,
`since_inception_matches_history`):
- **Why helpers, not generated Ruby:** the fund 342 versions were 10-line custom formulas that hit
  the blocklist twice. As helpers they are one-line, reviewable, Cucumber-tested once, and detectable
  by name for the "recommended steps" tick (D8).
- **Scope:** they follow the existing helper rules (SQL aggregation only, `CheckFailed` with rows,
  `severity:`).
- **Docs:** documented in `allocation_run_checks.md`.

**Alternative rejected:** AI for everything. Output varies between runs, it can invent entry names
that make runs fail, and it can't be tested.

### D5. AI suggester: `RunCheckSuggestions::AiSuggester`

- **Prompt:**
  - the helper catalogue: signatures and one-line purpose, extracted from `CheckHelpers` doc comments
    into a constant so the prompt and docs stay in step
  - the blocked words
  - the fund's non-reporting formulas (sequence, name, rule_type, text truncated to 600 chars)
  - the rule suggestions already made, to avoid duplicates
  - distinct uploaded `(name, entry_type)`
- **Output:** a JSON array of `{name, description, rule_type, formula, evidence}` via
  `LlmService.ruby_llm_chat(entity:).ask` (the non-deprecated client, with the entity's own API keys), parsed as JSON.
- **Validation:** each item is built as an unsaved `FundFormula` and run through `valid?`, which
  covers syntax, blocklist and run-check validations. Invalid items go to `plan["rejected"]` with the
  error.
- **Errors:** an LLM error sets `plan["ai_error"]`; rule suggestions are unaffected.
- **Tests:** Cucumber stubs `LlmService.ruby_llm_chat`.

### D6. Test runs use `RunChecks` on unsaved formulas

- **Which run:** the latest run of the fund with status `Success` (by `end_date`, then `id`).
- **How:** pre and post suggestions are evaluated separately with that run's dates and the run as
  `allocation_run`. Results are stored per suggestion (result, summary, columns, rows, truncated,
  duration_ms).
- **No successful run:** results are `not_tested`.
- **AI text is not evaluated unread:** the prompt quotes entry names uploaded by the entity's users,
  so a returned formula is whatever such a name talked the model into. An AI suggestion is test-run
  only when it is one helper call whose arguments are literals (`Suggestion#safe_to_test?`); any
  other text is shown `not_tested` until a person adds it.
- **Timing:** runs inside the suggestion job. Per-check duration is stored, so slow checks on large
  funds are visible.

### D7. One attribute builder for Add and import

- **Extraction:** `FundFormulaAttributes.from_row(row_hash)` is pulled out of
  `ImportFundFormula#read_row_data`/`save_row`; `FundFormulaAttributes.to_row(attrs)` is its inverse.
- **Add selected:** `to_row` then `from_row` then `fund.fund_formulas.create!`.
- **Download:** `to_row` rows written with `ImportFundFormula::STANDARD_HEADERS`.
- **Guarantee:** the round trip is identical by construction, and a Cucumber scenario asserts it
  through the real importer.

### D8. Controller, views, polling

- **Model methods, not controller logic:** `FundFormulaOperation.start!`, `#start_apply!`, `#add_suggestions!` and `#suggestions_xlsx` hold the lock, busy and duplicate rules, so Cucumber tests them without a browser.
- **Controller:** `FundFormulaOperationsController`, a thin wrapper:
  - `index`: the incremental allocation page, i.e. status, recommended steps, history
  - `show`: plan/result with a polling frame while active
  - `create`: operation + params
  - `apply`
  - `add_suggestions`
  - `download_suggestions`
- **Policy:** `FundFormulaOperationPolicy`, where every action is `support?`.
- **Autoloading:** `config/application.rb` treats directories inside `account_entry_allocation/` as namespaces (`IncrementalMigration::Plan`, `RunCheckSuggestions::Builder`), not autoload roots.
- **Job:** `FundFormulaOperationJob(id, step)`, `retry: 0`.
- **Views:** Turbo frame reload while status is `previewing`/`applying`, as on `allocation_run_reports/show`.
- **Menu:** the "Enable All" button label becomes "Actions" and gains two support-only links.
- **Recommended steps** are derived, not stored:
  1. a `PostRunCheck` formula starting `since_inception_matches_history` exists
  2. a `Success` run finished before the latest applied `enable_incremental`
  3. that operation exists
  4. a `Success` run was created after it

## Risks / Trade-offs

- [Regex rules miss a formula written in an unusual style] → evidence lists what matched, so gaps are
  visible; the AI step covers the rest; rules are extended as funds show new shapes.
- [Test runs on very large funds are slow (post-run tie-outs aggregate over `account_entries`)] →
  run in the job, sequentially, with durations shown; no request-time evaluation.
- [Preview's full copy uses disk/memory like an allocation run] → the busy guard stops it overlapping
  a run on the same fund; the scratch directory checks in `load_sqlite_db` still apply.
- [Refactor changes rake output that someone scripts against] → `TextReport` reproduces the current
  lines; a Cucumber scenario compares the rake dry run with the UI plan.
- [AI prompt size on 300+ formula funds] → reporting formulas excluded and text truncated; the prompt
  size is logged.
- [A crashed job leaves an operation `previewing`/`applying` and blocks the fund] → rows in those
  states older than `STALE_RUN_HOURS` are treated as failed when the next operation is requested.
- [Apply's second full copy doubles wall time] → accepted for correctness (D2).

## Migration Plan

1. **Deploy:**
   - the table migration
   - the service refactor with rake wrappers (verify the dry-run output on a dev fund is unchanged)
   - the new helpers
   - the suggester, controller and views (support-only)
2. **Rollback:** revert the code and drop `fund_formula_operations`. Formula edits and flags made
   through the UI remain as they are, the same as when done by rake, and `allocation:disable_incremental`
   still reverses them.
3. **Fund 342's hand-written checks** (seq 316, 317, 323) can be replaced with the new one-line
   helpers by running suggestions again; not required.

## Open Questions

- Whether `STALE_RUN_HOURS` (12) should be configurable per environment. It can change later without
  affecting behaviour or tasks.
