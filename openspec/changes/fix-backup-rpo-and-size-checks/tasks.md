# Tasks

> Reproduce first; phase gate per group. Every cucumber run: fresh `TEST_ENV_NUMBER`, Redis on 6379, background + `wait $pid`.

## 1. Reproduce

- [x] 1.1 Write `features/misc/dr_backup_rpo.feature` + steps for H1–H2, E1–E3, X1–X4. "ID — …" comments.
- [x] 1.2 Run it; confirm it fails against current code. Record the output.
      - Recorded 2026-11-08: `11 scenarios (11 failed)`: undefined `thirty_minute_cadence` / `cadence_env_allowed?` / `grade_full_size`. Read-only proof after: size check 100% of usual on staging and prod IN; `[production.in]` refused; staging dry run showed the one-line change on ip-10-0-3-138 (account 174852986003).

## 2. Fix — pure logic + size check (report Fix rows 1, 3)

- [x] 2.1 `Dr::BackupSchedule`: `cadence_env_allowed?`, `thirty_minute_cadence`, `grade_full_size` (thresholds 70% / 40%, median of three). Inline comments. Verify: `ruby -c`.
- [x] 2.2 `DbBackupFreshnessJob#check_bucket`: list once; on the primary bucket, size the newest full older than 2 h and the three before it; fail → failures, warn → log. Verify: `rake "s3:backup_daily_report[staging.in]"` and `[production.in]` still pass (read-only).
- [x] 2.3 Run the feature: all rows pass.

## 3. Fix — the cadence task, docs (report Fix rows 2, 4)

- [x] 3.1 `lib/tasks/dr_backup_cadence.rake` `dr:set_backup_cadence[env]`: env guard, account guard, timing and running-backup guards, dry run by default, save, write, re-read, rollback hint. Verify: dry run against staging prints the one-line change and touches nothing; `[production.in]` is refused.
- [x] 3.2 Docs: `db_backup_system.md` §11 implemented; DR guide; gap review (RPO staging, G9).
- [x] 3.3 Run all DR features: green.

## 4. Apply and regression

- [x] 4.1 **With the user's go-ahead:** `EXECUTE=1 rake "dr:set_backup_cadence[staging.in]"`; next day the report shows 46 incrementals.
      - Applied 2026-11-08 08:45 UTC on ip-10-0-3-138: verified `0,30 0-22 * * * /home/ubuntu/backup_db.sh incr`; saved `~/crontab.before-30min.20261108084541`; a re-run reports "Already every 30 minutes". Pending: the first :30 incremental (09:30 UTC) and tomorrow's report (46 incrementals).
- [x] 4.2 Rubocop on new and changed lines: clean.
- [x] 4.3 N+1 check: not applicable — no queries.
- [x] 4.4 UI check: not applicable — no screens.
