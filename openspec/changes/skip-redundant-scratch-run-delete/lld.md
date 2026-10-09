# Skip Redundant Cleanup in Allocation Data Load — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md): link to its diagrams and
> worked examples rather than repeating them.

> **Scale to the change.** One method changes, so most conditional sections are `N/A`.

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

- The line `AccountEntrySqlite.where(allocation_run_id: ctx[:allocation_run_id]).delete_all` now runs only `if reused || run_id_in_primary?(ctx)`; `delete_existing_scratch_entries` stays `if reused` — see [Method Contracts](#method-contracts).
- A re-run into an existing `AllocationRun` (`rerun!`) must still clean: live rows of a since-disabled formula keep the run id, are copied by the load script and would be migrated twice. `run_id_in_primary?` detects it with an indexed primary-DB lookup — see [design.md Design decisions #1](design.md#design-decisions).
- No index is added (rejected) — see [Queries and Indexes](#queries-and-indexes).
- `WatchdogSec` goes 120 to 600 in the unit template; it applies on the next deploy's restart, and a real hang now takes up to 10 min to recover — see [Configuration and Rollout](#configuration-and-rollout).
- The reused path can only run in development, so its test stubs it and uses a throwaway scratch dir — see [Test Plumbing](#test-plumbing).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ②③ Reuse check and cleanup | `app/packs/allocation_engine/account_entry_allocation/run_formulas.rb` (`load_sqlite_db`, inside the `with_scratch_sqlite` block) | Modified | Run the run-id delete only when `reused || run_id_in_primary?`; add the small private helper `run_id_in_primary?` |
| Tests | `features/fund/allocation_scratch_cleanup.feature` | Subscribe to `sql.active_record` and look for the run-id DELETE (H1, E1, E2). Stub `reuse_scratch_db?` for E1 and use `Dir.mktmpdir` as `ALLOCATION_SCRATCH_DIR` so the real `tmp/allocation/*_dev.sqlite3*` copies are never touched. E2/E3 call `AllocationRun#rerun!(now: true)` and compare the fund's entry count and sum with those recorded after the first run | Existing allocation fixtures (`allocate_account_entries_2`) | Steps live in `features/step_definitions/allocation_scratch_cleanup_steps.rb` (SQL recording, reuse stub, record/compare entries, disable first/last formula, re-run) |
| Tests | `features/step_definitions/allocation_scratch_cleanup_steps.rb` | New (only if existing steps do not cover it) | SQL capture and reuse stub |
| Docs | `app/packs/allocation_engine/account_entry_allocation/run_formulas.md` | Modified, only if it describes the delete | Keep the doc in line with behaviour |
| Config | `config/deploy/services/sidekiq_IRM_env.service.erb` | Modified | `WatchdogSec=120` to `WatchdogSec=600`, and update the comment above it |
| Docs | `docs/operations/process_supervision.md` | Modified | Update the `WatchdogSec` row (120s to 600s, ping every 300s) |

**Reviewer checks**
- [ ] No other file under `app/` or `script/` changes (in particular, not `load_sqlite3_from_mysql.sh`)
- [ ] The file sits in its pack (`app/packs/allocation_engine/...`), nothing placed in `app/models` or `app/controllers`

---

## Schema Detail

N/A — no tables, columns or indexes change (index rejected: [design.md Design decisions #2](design.md#design-decisions)).

---

## Method Contracts

**`AccountEntryAllocation::RunFormulas#load_sqlite_db`** (Operation step)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `load_sqlite_db(ctx, fund:, **)` | Trailblazer ctx, `Fund` | `true`, or the result of `load_failed` | Nothing new; `rescue StandardError` around the block still maps to `load_failed` | Builds scratch DB; when `reused` or the run already owns rows in the primary DB, deletes this run id's rows from it | Yes: re-running rebuilds the scratch DB (or re-deletes in the reused case) |

Shape of the change (not code to paste):

| Today, inside `with_scratch_sqlite` | After |
|---|---|
| `AccountEntrySqlite.where(allocation_run_id: …).delete_all` unconditionally, then `delete_existing_scratch_entries(ctx) if reused` | The run-id delete gets `if reused \|\| run_id_in_primary?(ctx)`; `delete_existing_scratch_entries(ctx) if reused` is unchanged and still follows it. The counts and notifications after them stay unconditional |

**`RunFormulas#run_id_in_primary?(ctx)`** (private helper): `AccountEntry.exists?(allocation_run_id: ctx[:allocation_run_id])`. Returns a boolean, raises nothing new, no side effects, idempotent. Uses `index_account_entries_on_allocation_run_id` (db/schema.rb). `AccountEntry` hides soft-deleted rows, matching the load script, which never copies them (`deleted_at IS NULL`).

**Reviewer checks**
- [ ] Order is unchanged for the reused case: run-id delete, then `delete_existing_scratch_entries`, then counts
- [ ] `entry_count`, `commitment_count`, `db_size_mb` and both notifications still run on every path
- [ ] The code comment states the two cases (reused copy, re-run into an existing run) and the 2026-10-05 reason
- [ ] `run_id_in_primary?` runs after `delete_existing_entries` (it is a load_sqlite_db step, so it does), otherwise it would always be true on a re-run

---

## Controllers, Params and Responses

N/A — no controller action changes.

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| Removed on fresh load: `load_sqlite_db` | `DELETE FROM account_entries WHERE allocation_run_id = ?` | None (full scan, the problem) | about 1.05M scanned, 0 deleted on fresh copy | n/a |
| Unchanged: migration step, per formula (`run_formulas.rb` near the "Migrating N entries" log) | `generated`, `fund_id`, `allocation_run_id`, `fund_formula_id`, `migrated = false` (`migrated` is scratch-only and 0 for every loaded row, so it does not narrow) | `index_account_entries_on_fund_formula_id` (planner choice, checked with `EXPLAIN QUERY PLAN`) | that formula's rows across runs | n/a |
| Unchanged: migration step, final catch-all (no formula) | same without `fund_formula_id` | `idx_ae_fund_gen_date_formula` (fund_id, generated): reads the fund's generated rows and filters by run id | the fund's generated rows (about 30% of a table in the synthetic check) | once per run |
| Unchanged: counts | `where(fund_id:)` | `idx_fund_id_and_entry_type_and_reporting_date` and siblings | scan cost already accepted today | n/a |

No index is added on `allocation_run_id` — reasons in [design.md Design decisions #2](design.md#design-decisions).

**Reviewer checks**
- [x] Migration queries checked with `EXPLAIN QUERY PLAN` on a synthetic table built from the load script's schema and indexes (see Queries table); re-check on a real scratch DB if the final catch-all ever shows slow gaps
- [ ] No new query is introduced

---

## Transactions, Locking and Concurrency

N/A — a delete is removed, nothing is added. Scratch DBs are per process or run, so no new contention.

---

## Background Jobs

N/A — no job added or changed. `AccountEntryAllocationJob` is the caller and is unchanged. A dedicated Sidekiq process for allocation is a deferred follow-up ([design.md Risks](design.md#risks-and-open-questions)).

---

## External Integrations

N/A — none.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| Any `StandardError` reading the scratch DB | the `with_scratch_sqlite` block | existing `rescue StandardError` then `load_failed` | "Failed to read loaded data for fund …" | `Rails.logger.error` with backtrace (unchanged) |

**Reviewer checks**
- [ ] The `rescue` still wraps the whole block, including the new guard
- [ ] The "loaded N account_entries" log line still prints on both paths (it is the signal for confirming the fix in production)

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | N/A, no user-facing action |
| Tenant isolation | Unchanged; scratch DB is built per fund (and entity) |
| Secrets | Unchanged; the script env is untouched |
| Input / output sanitisation | N/A |
| Mass assignment | N/A |

**Reviewer checks**
- [ ] No change to what is written to logs or notifications

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None new. `ALLOCATION_FRESH_SCRATCH_DB` behaviour unchanged |
| `WatchdogSec` | 120 to 600 in the unit template. `sidekiq:install_service` rewrites `/etc/systemd/system/sidekiq_IRM_<stage>.service` and runs `daemon-reload` on every deploy when the file differs; the deploy's stop/start of the unit then makes it take effect. Check afterwards with `systemctl show sidekiq_IRM_production -p WatchdogUSec` (expect `10min`) |
| Feature flag | None |
| Cron / schedules | None |
| Deploy order | Code only; Sidekiq restart as in a normal deploy |
| Rollback | Revert the commit; no data to clean up |
| Post-release check | In the Sidekiq log, "loaded N account_entries …" appears after each large-fund load, and `journalctl -u sidekiq_IRM_production` shows no `Failed with result 'watchdog'` |

**Reviewer checks**
- [ ] Safe to deploy with an allocation run in flight (restart policy as usual)

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/fund/allocation_scratch_cleanup.feature` | Subscribe to `sql.active_record` for DELETEs against `allocation_run_id` (H1). Stub `reuse_scratch_db?` to true for E1 and make sure the scratch dir and `.complete` marker are cleaned up afterwards | Fund, commitments, account entries via the existing steps used by `features/fund/account_entries.feature` | Prefer reusing the step at `features/step_definitions/account_entries.rb` that calls `AccountEntryAllocationJob.perform_now`; add only an SQL-capture step and a reuse-stub step |

**Reviewer checks**
- [x] E1 is built by stubbing `reuse_scratch_db?`, with `ALLOCATION_SCRATCH_DIR` pointed at a throwaway directory (never the real `tmp/allocation`)
- [ ] The stub is scoped to the scenario and removed afterwards

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations | N/A | no relation checks added |
| Dedup in SQL, batch bulk operations | N/A | a delete is removed |
| Select only needed columns when loading many `account_entries`; no speculative `includes` | Applies | the change removes a pass over `account_entries`; nothing added |
| Screen dates via `l(...)` / email dates | N/A | no dates shown |
| Date inputs / JS dates | N/A | no UI |
| Every query entity-scoped; Pundit | N/A | no controller; scratch DB is per fund |
| MCP tool surfaces / ontology YAML | N/A | untouched |
| Cucumber only; `TEST_ENV_NUMBER=$RANDOM` | Applies | tasks use Cucumber with a random `TEST_ENV_NUMBER`; Redis up on 6379 |
| `bundle exec rubocop` clean, incl. `IRM/RelationBlankPresent` | Applies | run on `run_formulas.rb` and the new step file |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
