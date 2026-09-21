# Killing Long-Running / Slow MySQL Queries

**Context:** Written after a prod disk-full incident (2026-08-10) where two idle
connections each held an ~8.75G InnoDB session temp tablespace file
(`#innodb_temp/temp_N.ibt`) from an earlier unbounded query, pushing `/` to 97% used.
Root cause was an unbounded `DISTINCT` + `JOIN` + `ORDER BY` export query (see
[`account_entries_controller.rb`](../../../app/packs/funds/capital_commitments/controllers/account_entries_controller.rb)
pivot export path) — see also the reporting-date default-window fix applied for pivot
tables as a preventive measure.

---

## 1. Find what's running right now

From inside an interactive `mysql>` prompt:

```sql
SELECT id, user, host, db, command, time, state, LEFT(info, 100)
FROM information_schema.processlist
WHERE command = 'Query' AND time > 10
ORDER BY time DESC;
```

Or as a one-liner from the shell — wrap it in double quotes and pass to `-e`; the inner
single quotes around `'Query'` don't need escaping since they're nested inside the outer
double quotes:

```bash
sudo mysql -uroot -p -e "SELECT id, user, host, db, command, time, state, LEFT(info,100) FROM information_schema.processlist WHERE command = 'Query' AND time > 10 ORDER BY time DESC;"
```

`Empty set` just means nothing matched `time > 10` at that exact instant — not an error.
Lower the threshold or drop the `WHERE` entirely (add `LIMIT 20`) to see everything,
including `Sleep` connections, if you want a fuller picture.

To see all of them use

```sql
SELECT id, user, host, db, command, time, state, LEFT(info,100) FROM information_schema.processlist ORDER BY time DESC LIMIT 20;
```

Read `info` (the query text) before killing anything — some long-running queries are
expected (allocation runs, backups, large legitimate exports). Don't blanket-kill without
looking.

## 2. Kill a specific query

```sql
KILL <id>;
```

`id` is the `id` column from `processlist` / `SHOW PROCESSLIST`, not the OS process id.

## 3. Kill idle connections holding leftover temp tablespace space

If disk is full from `#innodb_temp` (see `df -h` → `du /var/lib/mysql` → `#innodb_temp`
being unexpectedly large), find which session owns which temp file:

```sql
SELECT * FROM information_schema.innodb_session_temp_tablespaces
ORDER BY size DESC LIMIT 20;
```

Cross-check the owning `id` against `processlist` — if it's genuinely idle (`Sleep`, not
actively running), it's safe to kill; the file is released immediately without a mysqld
restart:

```sql
KILL <id>;
```

Note: `STATE = ACTIVE` in `innodb_session_temp_tablespaces` only means the tablespace file
is currently allocated to that session — it does **not** mean a query is actively running.
Always check `processlist.command`, not this table's `STATE` column, to judge if a session
is idle.

If instead the space is one big global `ibtmp1` file (not per-session `temp_N.ibt`), killing
sessions won't help — that only shrinks on `sudo systemctl restart mysql`.

## 4. Ongoing auto-kill for queries over a threshold

Don't hand-roll a cron loop with raw `KILL` — too easy to catch replication threads, the
event scheduler, or a legitimate long job. Use **`pt-kill`** (Percona Toolkit), built for
this. But **don't write kill rules from guesses** — this app has known long-but-legitimate
jobs (nightly backup, allocation runs, the account*entries pivot export can run several
minutes). Identify who/what those are from real data first, \_then* write filters, in this
order: observe → categorize → test offline → enable print-only in prod → enable kill.

```bash
sudo apt install percona-toolkit
```

### 4a. Observe first — don't filter blind

Run `pt-kill` in **print-only** mode (no `--kill`) as a long-lived daemon, logging
everything that _would_ match a broad time threshold. This is the exact tool you'll later
enable killing with, so what it prints here is exactly what it would kill later — treat this
as the ground truth, not a guess about which users are "the app" vs "safe to kill".

```bash
pt-kill --busy-time 10 --match-command Query --print --victims all \
  --interval 5 --log /var/log/pt-kill-observe.log --run-time 48h \
  h=localhost,u=root,p='yourpass'
```

- `--victims all` here (not the default `oldest`) so the observation log captures _every_
  matching query, not just one per class — you want full visibility before you decide
  what's safe to ignore.
- Run it across a **representative window** (at least 24–48h) so it catches the 11 PM
  full backup, incremental backups every 30 min, any scheduled allocation runs, and normal
  office-hours exports — not just a quiet hour.

### 4b. Review the log and categorize by user/host/db/query pattern

```bash
awk '{print $5}' /var/log/pt-kill-observe.log | sort | uniq -c | sort -rn   # by user, adjust field
```

Or re-run pt-kill against the same window grouped by fingerprint to see it bucketed for you:

```bash
pt-kill --busy-time 10 --match-command Query --print --group-by fingerprint \
  --interval 5 h=localhost,u=root,p='yourpass'
```

Cross-check unfamiliar users/hosts against `information_schema.processlist.user`/`host`
while they're running, and against app config (which DB user does Sidekiq/the allocation
engine/backups connect as?). Sort what you see into:

- **Known-legit, expected to run long**: backup user, allocation engine jobs, pivot/xlsx
  export jobs — these should be _excluded_ via `--ignore-user` / `--ignore-info`, not killed.
- **Everything else that's still slow past your threshold**: candidate for killing.

Don't assume — if a user/query shows up in the log and you don't recognize it, go find out
what it is before adding it to an ignore list.

### 4c. Test candidate filters offline before they touch a live connection

`--test-matching` runs your match/ignore rules against a saved `SHOW PROCESSLIST` snapshot
with **zero risk** — nothing is killed, nothing even needs to be running:

```sql
-- capture a snapshot during a known-busy period (e.g. while the nightly backup runs)
SELECT * FROM information_schema.processlist INTO OUTFILE '/tmp/processlist_backup_window.txt';
```

```bash
pt-kill --busy-time 10 --match-command Query \
  --ignore-user '^(backup_user|repl_user|event_scheduler)$' \
  --ignore-info 'account_entries.*pivot' \
  --test-matching /tmp/processlist_backup_window.txt
```

Confirm the known-legit jobs from step 4b are correctly excluded (don't appear in the
output) before ever pointing filters at a live connection.

### 4d. Roll out print-only in prod, then flip to kill

```bash
pt-kill --busy-time 10 --match-command Query \
  --ignore-user '^(backup_user|repl_user|event_scheduler)$' \
  --ignore-info 'account_entries.*pivot' \
  --print --log /var/log/pt-kill.log --interval 5 \
  h=localhost,u=root,p='yourpass'
```

Watch `/var/log/pt-kill.log` for a full day-night cycle. Only once it's catching _only_
what you intend, add `--kill`:

```bash
pt-kill --busy-time 10 --match-command Query \
  --ignore-user '^(backup_user|repl_user|event_scheduler)$' \
  --ignore-info 'account_entries.*pivot' \
  --kill --print --log /var/log/pt-kill.log --interval 5 \
  h=localhost,u=root,p='yourpass'
```

Keep `--print --log` alongside `--kill` permanently — it's your audit trail of what got
killed and why.

### 4e. Other safety defaults worth knowing

- `--victims oldest` (the default) kills only the single oldest query per matched class —
  it won't mass-kill every connection that happens to match, which protects against
  over-killing a burst of identical/blocked queries. Use `all` only for observation (4a).
- `--ignore-state` defaults to `Locked` — queries merely _waiting_ on another thread's lock
  are not touched by default, only queries actually executing past the threshold.
- `--ignore-self` defaults to yes — pt-kill won't kill its own connection.
- `--replication-threads` is required to let pt-kill touch replication threads at all; by
  default they're always skipped, no filter needed.
- Run as a long-lived process (systemd unit or `nohup ... &`), not cron — `pt-kill` polls
  continuously itself via `--interval`; cron re-invocations would each only see a
  point-in-time snapshot.

**Performance impact of pt-kill itself:** the polling loop (§4a–4d, including `--interval
5`) is negligible — it's a lightweight `processlist` read, cost scales with connection
count not data size, and MySQL 5.7+ backs `SHOW PROCESSLIST` with `performance_schema`
internally so it doesn't take the old global thread-list mutex. `--test-matching` (§4c)
touches the server not at all. The real cost is the `KILL` itself, not pt-kill: killing a
query mid-execution forces InnoDB to roll back whatever it already did, which can briefly
cost real CPU/IO and hold locks while unwinding — worse the further along a runaway query
is (e.g. a temp table already partway to several GB). `--wait-after-kill` exists to give
that rollback room to finish before pt-kill looks for its next victim.

**Pick the threshold carefully.** A blanket cutoff can still catch legitimate long
operations even with user/info filters in place. Prefer either a high threshold
(120–300s) or scope tightly via `--match-info`/`--ignore-info` rather than a flat time
cutoff on all queries.

## 5. `pt-kill` option reference

| Option                                 | Default                              | Purpose                                                                                           |
| -------------------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------- |
| `--match-user` / `--ignore-user`       | —                                    | Match/ignore by `User` (Perl regex)                                                               |
| `--match-command` / `--ignore-command` | —                                    | Match/ignore by `Command` (Query, Sleep, Binlog Dump, Connect, Execute, ...)                      |
| `--match-db` / `--ignore-db`           | —                                    | Match/ignore by database (Perl regex)                                                             |
| `--match-host` / `--ignore-host`       | —                                    | Match/ignore by `Host` (may include `:port`)                                                      |
| `--match-info` / `--ignore-info`       | —                                    | Match/ignore by query text (Perl regex)                                                           |
| `--match-state` / `--ignore-state`     | ignore default: `Locked`             | Match/ignore by `State`; default protects lock-waiters                                            |
| `--match-all`                          | —                                    | Match everything not explicitly ignored                                                           |
| `--busy-time`                          | —                                    | Match `Command=Query` running longer than this (maps to processlist `Time`)                       |
| `--idle-time`                          | —                                    | Match `Command=Sleep` idle longer than this                                                       |
| `--any-busy-time` / `--each-busy-time` | —                                    | Class-level: match if _any_/_every_ query in the class exceeds this time (used with `--group-by`) |
| `--query-count`                        | —                                    | Class-level: match only classes with at least N queries (used with `--group-by`)                  |
| `--group-by`                           | —                                    | Bucket matches by a processlist column, or `fingerprint` for normalized query shape               |
| `--victims`                            | `oldest`                             | Which matches in a class to kill: `oldest`, `all`, `all-but-oldest`                               |
| `--print`                              | —                                    | Print the `KILL` that would run; kills nothing                                                    |
| `--kill`                               | —                                    | Kill the connection (`KILL <id>`)                                                                 |
| `--kill-query`                         | —                                    | Kill only the query, not the connection (MySQL 5.0+)                                              |
| `--kill-busy-commands`                 | `Query`                              | Comma list of commands eligible for `--busy-time` killing                                         |
| `--execute-command`                    | —                                    | Run an arbitrary command on match instead of/alongside killing                                    |
| `--test-matching`                      | —                                    | Test match/ignore rules against a saved processlist snapshot file — no live connection needed     |
| `--wait-before-kill`                   | —                                    | Delay before killing, to let `--execute-command` gather info first                                |
| `--wait-after-kill`                    | —                                    | Delay after a kill before looking for more, so blocked queries get a chance to run                |
| `--interval`                           | 30s, or half of `--busy-time` if set | How often to re-check the processlist                                                             |
| `--run-time`                           | forever                              | How long to run before exiting                                                                    |
| `--ignore-self`                        | yes                                  | Never kill pt-kill's own connection                                                               |
| `--replication-threads`                | off                                  | Must be set explicitly to allow matching replication threads (skipped by default)                 |
| `--verbose` / `-v`                     | —                                    | Print what's happening to STDOUT                                                                  |

Full docs: https://docs.percona.com/percona-toolkit/pt-kill.html

## 6. Finding the exact query text after the fact

None of this needs `slow_query_log` — `pt-kill` (§4) and the manual `processlist` check
(§1) both read live query text straight off `processlist.info`/`SHOW PROCESSLIST`, no
logging required. `slow_query_log` only matters if you want a durable record of query text
_after_ a session has already ended.

### If you can't/don't want to restart mysqld

`slow_query_log`, `long_query_time`, and `log_output` are all **dynamic** global variables —
`SET GLOBAL slow_query_log = 'ON'` takes effect immediately, no restart needed, on a normal
self-managed instance. (Only matters if you're on something like RDS where some parameter
changes force a reboot depending on the parameter group — check there first if unsure.)

```sql
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 1;
SET GLOBAL log_output = 'FILE';
```

Then tail the slow log file (see `SHOW VARIABLES LIKE 'slow_query_log_file'`). Turn it back
off once you've caught a sample — leaving a low threshold on in prod adds log volume.

**Performance impact:** with `log_output = 'FILE'`, each qualifying query just appends a
line to disk — negligible CPU/latency per query. The real cost is disk I/O/space from
volume, not per-query slowdown, and at `long_query_time = 1` every known-legit long job
(pivot export, allocation runs) will get logged too — expect meaningful log growth, not a
slow database. Given this app's disk headroom was already thin during the incident, capture
a short window (minutes) and turn it back off rather than leaving it on. `log_output =
'TABLE'` would be worse (writes go through a MyISAM table) — stick with `FILE`.

### Restart-free alternative: catch a session before it's gone

For a query that's _still running right now_, skip the slow log entirely —
`performance_schema` is on by default and needs no restart. Get the full (if
`performance_schema_max_sql_text_length`-truncated) text directly:

```sql
SELECT thread_id, sql_text, timer_wait
FROM performance_schema.events_statements_current
WHERE thread_id = (SELECT thread_id FROM performance_schema.threads WHERE processlist_id = <id>);
```

This only helps for a thread that hasn't been killed yet — once it's gone, its
`events_statements_current`/`events_statements_history` rows go with it, and you're back to
the normalized `events_statements_summary_by_digest` below or a proper slow log.

To find which query _pattern_ creates the most disk temp tables (works retroactively,
survives killed sessions):

```sql
SELECT digest_text, count_star, sum_created_tmp_disk_tables,
       sum_rows_examined, ROUND(sum_timer_wait/1000000000000, 2) AS total_sec,
       ROUND(max_timer_wait/1000000000000, 2) AS max_sec
FROM performance_schema.events_statements_summary_by_digest
ORDER BY sum_created_tmp_disk_tables DESC
LIMIT 10;
```
