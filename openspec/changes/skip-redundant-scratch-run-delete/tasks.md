# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> Prerequisites for every Cucumber run: Redis up on 6379, and a fresh `TEST_ENV_NUMBER=$RANDOM`.
> LLD section references are to [lld.md](lld.md).

## 1. Guard the run-id cleanup (LLD: Method Contracts, File Map)

- [x] 1.1 Before editing, run `grep -rn "allocation_run_id" app/packs/allocation_engine` and check whether anything pre-populates the scratch DB with the new run id (the design's no-op assumption). Finding: normal runs create a new `AllocationRun` each time (funds_controller.rb:308, allocation_group_run_job.rb:59) so the id is new; but the load script copies the `allocation_run_id` column from MySQL, and manual console re-runs can reuse an id. Decision after review: do NOT accept it. `AllocationRun#rerun!` is a supported ops path and a re-run after a formula was disabled duplicated entries; guard with `run_id_in_primary?` instead.
- [x] 1.2 (Revised after review: guard is `reused || run_id_in_primary?`, not `reused` alone; first version duplicated entries on a `rerun!` after a formula was disabled.) In `app/packs/allocation_engine/account_entry_allocation/run_formulas.rb` (`load_sqlite_db`), put the `AccountEntrySqlite.where(allocation_run_id: ctx[:allocation_run_id]).delete_all` under `if reused || run_id_in_primary?(ctx)` (new private helper using `AccountEntry.exists?(allocation_run_id:)`), keeping `delete_existing_scratch_entries(ctx) if reused` after it. Keep the counts, the log line and both notifications unconditional. Verify by reading the diff: only the guard moved.
- [x] 1.3 Add a comment above the guarded cleanup stating the two cases that need it (reused copy; re-run into an existing run) and the 2026-10-05 reason, and update `run_formulas.md` only if it describes this delete. Verify with `git diff --stat`.
- [x] 1.4 Run `bundle exec rubocop app/packs/allocation_engine/account_entry_allocation/run_formulas.rb` and confirm it is clean. (One pre-existing Layout/ArgumentAlignment offense at the `display_generated_links` button, present on `main` without this change, left untouched.)
- [x] 1.5 Write `features/fund/allocation_scratch_cleanup.feature` covering design.md worked examples H1 (new run issues no run-id delete), H2 (results unchanged), E1 (reused copy still cleaned, scratch dir isolated), E2 (re-run after the last / first formula was disabled: cleanup issued, no duplicated entries), E3 (re-run, nothing changed) and X1 (load-script failure still reports `load_failed`). Verified E2 fails against the `reused`-only guard. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/allocation_scratch_cleanup.feature` until green.
- [x] 1.6 Regression: run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/account_entries.feature` and `features/fund/fund_formula_multiple.feature` and confirm both still pass.

## 2. Verify the "no index" decision and ship checks (LLD: Queries and Indexes, Configuration and Rollout)

- [x] 2.1 (Done on a synthetic 500k-row table built from the script's schema and indexes, with `migrated = 0` for all rows as the script loads them: per-formula query uses `index_account_entries_on_fund_formula_id`; the final catch-all uses `idx_ae_fund_gen_date_formula` and reads the fund's generated rows, once per run. Accepted; re-check on a real scratch DB if needed.) On a developer machine with a loaded scratch DB (or a staging copy), run `EXPLAIN QUERY PLAN` for the migration query (`generated`, `fund_id`, `allocation_run_id`, `migrated = 0`) and confirm it uses `idx_ae_fund_gen_date_formula`. Record the plan in the PR description. If it does not, stop and revisit [design.md Design decisions #2](design.md#design-decisions) before shipping.
- [x] 2.2 Confirm `git diff --stat` shows no controller or data-handling files, so `bundle exec brakeman` is not needed for this change.
- [ ] 2.3 Write the PR description: link this change, state that the index was considered and rejected and why, note C (dedicated allocation Sidekiq process) as a deferred follow-up, and give the post-release check from lld.md (Configuration and Rollout).
- [x] 2.4 In `config/deploy/services/sidekiq_IRM_env.service.erb` change `WatchdogSec=120` to `WatchdogSec=600` and update the comment above it (it should say why 600: a long GVL-holding native call, and the 5-minute ping). Also update the `WatchdogSec` row in `docs/operations/process_supervision.md`. Verify: `grep -n WatchdogSec config/deploy/services/sidekiq_IRM_env.service.erb docs/operations/process_supervision.md` shows 600 in both.
- [ ] 2.5 After deploy, confirm `systemctl show sidekiq_IRM_production -p WatchdogUSec` prints `10min`.
- [ ] 2.6 After deploy, run `qa-checklist.md` on a deployed build and record the sign-off, in particular C6 (no watchdog restart during a large-fund load). This task is for QA, not for the apply agent.
