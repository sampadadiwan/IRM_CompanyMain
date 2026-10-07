# Cucumber Test Performance

Notes on what's been tried to speed up the Cucumber suite, what worked, what didn't,
and how to use what's currently in place. See also `CLAUDE.md` (large-table query
hygiene applies to app code exercised by tests too) and `features/features.md` (writing
new tests).

## Current setup

- 253 feature files, ~1561 scenarios.
- Test DB is SQLite, stored in `/dev/shm` (RAM-backed tmpfs), one file per
  `TEST_ENV_NUMBER` — see `config/database.yml`.
- `parallel_tests` is wired up (`config/cucumber.yml`'s `parallel` profile, the `pcuc`
  shell alias, and `cucumber_dashboard/`). The dashboard defaults to 3 workers on an
  8-core machine — capped low because each worker that drives Playwright also boots a
  full headless Chromium, and more than ~3 concurrent instances risks OOM (see the
  `CHROMIUM_LOW_MEMORY_ARGS` comment in `features/support/env.rb`).

## Applied

### Log noise (`config/environments/test.rb`)

- `Bullet.enable` now requires `BULLET=1`. N+1 instrumentation ran on every request in
  every scenario; opt in only when actively hunting N+1s.
- `config.log_level` defaults to `:warn` (was `:debug`), and
  `verbose_query_logs` only turns on when `LOG_LEVEL=debug` is set. The old defaults
  logged every SQL statement with its call site across all 1561 scenarios.
- `LOGS=<level>` (`debug`/`info`/`warn`/`error`/`fatal`) overrides the level for one run, e.g.
  `LOGS=info TEST_ENV_NUMBER=<n> bundle exec cucumber` for a faster full-suite run. Note that
  without `LOGS`, the per-worker logger built in `features/support/env.rb` (when
  `TEST_ENV_NUMBER` is set) starts at DEBUG and ignores the `:warn` default above. `LOGS`
  is applied after that swap, so it takes effect.
- To get the old verbose behavior back for a debugging session:
  `LOG_LEVEL=debug BULLET=1 TEST_ENV_NUMBER=<n> bundle exec cucumber ...`, then
  `tail -f log/test_<n>.log` (each worker logs to its own `log/test_<TEST_ENV_NUMBER>.log`;
  an unset `TEST_ENV_NUMBER` goes to `log/test.log`).

## Tried and reverted: forcing `rack_test` for non-`@javascript` scenarios

Only 20 of 253 feature files are tagged `@javascript`, yet `Capybara.default_driver`
is `:playwright` globally — every scenario boots a real headless Chromium against a
real Puma server thread, even ones that never touch JS. `capybara/cucumber` (loaded
automatically by `cucumber-rails`) already supports switching driver per-scenario via
tag name, so tagging a feature `@rack_test` runs just that file in-process with no
browser, no real HTTP round trip:

```ruby
# capybara-3.40.0/lib/capybara/cucumber.rb
Before do |scenario|
  scenario.source_tag_names.each do |tag|
    driver_name = tag.sub(/^@/, '').to_sym
    Capybara.current_driver = driver_name if Capybara.drivers[driver_name]
  end
end
```

This was piloted on `features/login/password_reset.feature` and
`features/login/user_registration_edit.feature`. `user_registration_edit` passed
under `rack_test`. `password_reset` **failed** — the "click the link in the emailed
reset-password mail" step landed on what looks like the caphive.com marketing page
instead of the app's reset-password form, while the identical scenario passed cleanly
under Playwright. Likely cause: `lib/middleware/website.rb`'s host-based routing
behaves differently for a request that isn't going through a real
browser/TCP connection. Both tags were reverted — **not currently applied to any
feature file.**

Takeaway: `@rack_test` is a real, low-risk mechanism (tag one file, everything else is
untouched), but each file needs to actually be run and verified before tagging it —
anything that follows an absolute-URL link (emailed links, external redirects,
subdomain-based routing) is a candidate to fail the same way. Don't apply it in bulk
without testing.

## Snapshot-restore DB strategy (default)

`features/support/sqlite_snapshot_database_strategy.rb`. This is now the only DB
cleanup strategy — it always runs, no env var needed.

**Problem:** the default `DatabaseCleaner` strategy (set in `features/support/env.rb`)
is `:truncation` for every scenario, deleting rows from ~160 of the schema's 201
tables (41 are excluded, per env.rb's own comment, "simply to make truncation
faster" — not for correctness). That's a lot of SQL round trips per scenario, times
1561 scenarios.

**Approach:** instead of deleting rows table-by-table, restore the whole SQLite file
from a pristine per-worker snapshot before each scenario, using SQLite's own **Backup
API** (`SQLite3::Backup`) rather than `cp`-ing the file:

- A raw file copy would leave any *other* open connection to the same file (e.g. the
  Playwright server thread's separately-pooled connection) holding a stale file
  handle or cached pages.
- The test DB files were confirmed to have `-wal`/`-shm` companion files during
  validation (WAL mode is active for at least some connections) — a raw `cp` of just
  the main file would silently miss uncheckpointed WAL data. `SQLite3::Backup`
  operates through the live connection API and handles this correctly.
- Because it resets the whole file rather than relying on a shared transaction, it's
  correct for both `rack_test` (single connection) and Playwright (separate
  server-thread connection) scenarios alike — no need for the `@javascript`/
  `rack_test` split that `TruncationStrategy` requires.

**Wiring:** `Cucumber::Rails::Database.javascript_strategy` is replaced with this
class. Note that env.rb's `DatabaseCleaner[:active_record].strategy = :truncation`
runs on its *own*, independent `Before`/`After` hooks (from `database_cleaner-core`)
— replacing just `javascript_strategy` would leave the old per-table truncation
running *in addition to* the restore. So `DatabaseCleaner[:active_record].strategy`
is also unconditionally swapped to `DatabaseCleaner::NullStrategy.new` so the restore
is the only cleanup that happens. (The 41-table exclusion list on the old truncation
config in `env.rb` is now dead code — harmless to leave, since `NullStrategy` means
that config is never consulted, but nothing reads it anymore either.)

**Reset happens in `after`, not `before`.** The first version of this restored the
db in `before_js`/`before_non_js` and left `after` a no-op, reasoning that the next
scenario's `before` hook would reset things anyway. That's true *within* one process,
but the last scenario of any given run then leaves the live db dirty. Since separate
`cucumber`/`parallel_cucumber` invocations reuse the same `/dev/shm/test_<N>.sqlite3`
file across runs (nothing deletes it between invocations), the next run's first
scenario would silently inherit that leftover data — and worse, `ensure_template!`
(which only builds its snapshot once, on the first hook call in a process) would
snapshot that dirty state as if it were pristine, baking the pollution in for every
scenario in the new run. Caught this via a real failure: two @javascript scenarios in
`turbo_session_expiry.feature` ran fine standalone, but adding a third file to the
same invocation produced one failure — root cause was a `TEST_ENV_NUMBER` reused
across several earlier manual runs, one of which left a stale `.template` file and
dirty live data on disk.

Fixed two things:
1. `ensure_template!` no longer checks `File.exist?(path)` before building — it's
   memoized purely in-process (`@template_ready`), so a fresh process always
   (re)builds its own template rather than trusting a leftover file that might
   reflect a different schema or leftover data from a previous invocation.
2. The primary reset moved to `after`, so every scenario — including the last
   one in a process — leaves the db back at the clean baseline for whatever
   runs next, in this process or a future one.

A code review of this file then flagged a follow-up gap: with the reset only in
`after`, a scenario reached via a path where the *previous* scenario's `after`
never ran (a hook exception aborting before `after`, or the process getting
killed mid-scenario — this exact test DB setup has a history of stale-state
issues from interrupted runs, see `project_stale_dev_shm_test_db` in the repo's
AI memory) would have no restore-before guard to catch it. Fixed by keeping a
restore in `before_js`/`before_non_js` too, in addition to `after` — belt and
suspenders. The extra restore is cheap (a page-level copy of a RAM-backed
file), so paying it on both ends of a scenario is worth the robustness.

Verified the fix directly: deleted a test DB file to force a fresh schema load, ran
`turbo_session_expiry.feature` (process A, 3 scenarios, all created id=1 records),
then ran `password_reset.feature` + `user_registration_edit.feature` as a **separate
invocation** against the same `TEST_ENV_NUMBER`. Process B's records also came back
as `id: 1` — proving process A's `after` hook left the file clean for process B to
inherit, rather than continuing A's sequence. All 5 scenarios across both processes
passed.

**Schema changes:** handled by Rails itself, not by this code. `maintain_test_schema!`
runs at process boot (before any Cucumber hook fires) and reloads the live db file if
its recorded schema version doesn't match `db/schema_test.rb`. By the time
`ensure_template!` runs, the live db already reflects the current schema — and since
fix (1) above means the template is always rebuilt fresh per process rather than
reused from disk, there's no path left where a stale-schema template could be served.

**Logging:** two `Rails.logger.info` lines, gated at `:info` so they don't spam the
default `:warn`-level output — visible with `LOG_LEVEL=debug`:
```
[SqliteSnapshotStrategy] snapshot taken -> /dev/shm/test_<n>.sqlite3.template
[SqliteSnapshotStrategy] restored from snapshot <- /dev/shm/test_<n>.sqlite3.template
```
"snapshot taken" logs once per worker process. "restored from snapshot" logs twice per
scenario (once in `before_js`/`before_non_js`, once in `after`).

**Timing** (Playwright driver in both cases; `@rack_test` is not involved):

| Scenario(s) | Strategy | Time |
|---|---|---|
| password_reset + user_registration_edit (2 scenarios) | truncation | 36.2s |
| same | snapshot | 19.6s (~46% faster) |
| turbo_session_expiry, all `@javascript` (3 scenarios, real Puma thread) | truncation | 48.8s |
| same | snapshot | 23.2s (~52% faster) |

The `@javascript` run confirms the restore is visible correctly across the separate
server-thread connection, not just within a single-threaded scenario.

**Isolated DB-operation benchmark.** The timings above are whole-scenario wall-clock,
which include Playwright page loads/HTTP — a real signal since that part is identical
between the two runs, but not a clean measurement of the DB operation alone. Isolated
it directly with a `rails runner` script (`DatabaseCleaner.start`/`.clean` vs.
`SqliteSnapshotStrategy`'s restore, no Capybara/browser/HTTP involved), covering two
cases:

| Case | Truncation | Restore | Advantage |
|---|---|---|---|
| Small scenario (entity+fund+3 rows, avg of 30 cycles) | 245ms/cycle | 121ms/cycle | ~2x |
| Bulk scenario (20,000 `account_entries` rows via `insert_all`) | 110ms | 10ms | ~11x |

Why the advantage *grows* with data volume rather than shrinking: truncation's cost is
dominated by fixed per-table overhead — it issues a DELETE against all ~160
non-excluded tables every time, regardless of whether they hold 0 rows or 20,000
(confirmed by the bulk case's single truncation run being *faster* than the small
case's per-cycle average — the 20,000-row table didn't meaningfully add to a cost
already dominated by ~160 fixed round trips). Restore's cost is instead bounded by the
*template's* size, which is captured right after migration (near-empty, since
`db/seeds.rb` is 8 lines) — restoring a 20,000-row-bloated live file back down to that
small template is cheap because the Backup API copies template-sized data across and
lets the destination's excess pages get deallocated, rather than deleting rows table
by table. That matters here specifically because CLAUDE.md flags exactly this kind of
bulk-import scenario (`account_entries` and friends) as the highest-risk case for this
app.

Caveat: this assumes the template itself stays small. If a future change made the
baseline schema load ship with a large seed/fixture set, restore cost would grow with
*that* — worth re-running this benchmark if `db/seeds.rb` ever stops being trivial.

**Not yet done:**
- Full-suite run (only a handful of files have been exercised so far).
- Removing the now-dead 41-table `DatabaseCleaner` truncation exclusion list in
  `features/support/env.rb` (inert, not currently cleaned up).
- Re-attempting `@rack_test` tagging on more files, one at a time, verified — not in
  bulk (see above — it's unrelated to and unaffected by this strategy).
