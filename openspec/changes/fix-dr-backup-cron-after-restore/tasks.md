# Tasks

> **Reproduce first.** Phase 1 writes the Cucumber scenarios from the report's Verification
> table that fail against the CURRENT code, and runs them to watch them fail. A bug fix that
> was never seen failing might be fixing nothing.

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens.

> **Every cucumber run needs a fresh `TEST_ENV_NUMBER`** (unset, runs share one sqlite DB and
> corrupt each other) and **local Redis up on 6379**. Launch runs in the background and `wait $pid`.

## 1. Reproduce

- [x] 1.1 Write `features/misc/dr_backup_schedule.feature` + `features/step_definitions/dr_backup_schedule_steps.rb` covering H1–H4, E1–E6 and X1–X4 from the report's Verification table. Steps call `Dr::BackupSchedule` (crontab split, primary/replica grading, script classification, Packer drift guard). Scenario comments carry "ID — Edge case: …".
- [x] 1.2 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/misc/dr_backup_schedule.feature` and confirm it fails against current code: `Dr::BackupSchedule` does not exist, so X1/X2/X3 cannot produce ❌. Record the failure output.
      - Recorded 2026-11-08: `15 scenarios (15 failed)`, every one `uninitialized constant Dr` (41 steps: 15 failed, 21 skipped, 5 passed).

## 2. Fix — pure logic and verification (report: Fix rows 1, 5)

- [x] 2.1 Create `lib/dr/backup_schedule.rb` (report Fix row 1). It holds: `CRON_PATH`, `CRON_CONTENT` (byte-identical lines to `db_redis_es.ami.pkr.hcl:309`), `LOGROTATE_PATH`/`LOGROTATE_CONTENT`, the old-job pattern (`backup_db*.sh`, `db_backup_xtra.sh` on active lines only), `split_crontab(text) → {kept:, removed:}`, `grade_primary(schedule:, armed:, legacy:)`, `grade_replica(legacy:)`, `baked_script?(head)`. Inline comments on every step. Verify: `bin/rails runner 'p Dr::BackupSchedule::CRON_PATH'` prints the path.
- [x] 2.2 `lib/tasks/dr_verify.rake` (report Fix row 5): read the `ubuntu` + root crontabs on the primary and the replica. Replace the `:warn` schedule check (`:257-259`) with `grade_primary`, and add `grade_replica` in the replica block. Verify: `ruby -c` passes, and the check names match the qa-checklist wording.
- [x] 2.3 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/misc/dr_backup_schedule.feature` and confirm H1–H4, E1–E6, X1–X4 pass before starting phase 3.

## 3. Fix — restore path, early strip, messages (report: Fix rows 2, 3, 4, 6, 7)

- [x] 3.1 `lib/tasks/backup_db.rake` `run_baked_restore` (Fix row 2): right after the stale `/tmp/xb_*` cleanup, strip old jobs from the `ubuntu` and root crontabs using `split_crontab`. Rewrite a crontab only when something was removed, and print each removed line. Verify: `ruby -c`; the code reads the crontab, filters in Ruby and writes back with `crontab -`; it never runs `crontab -r`.
- [x] 3.2 Same method (Fix row 3): baked iff `/usr/local/bin/db_backup_xtra.sh` exists and still contains `__BUCKET__`. Otherwise upload the generated script, `sudo install -m 0700 -o root -g root` it to `/usr/local/bin`, and always replace a stale generated copy. Write `CRON_CONTENT` / `LOGROTATE_CONTENT` when they differ (via a temp file + `sudo install -m 0644`). Run the restore from `/usr/local/bin`. Verify: `ruby -c`; replica disarm unchanged.
- [x] 3.3 `lib/tasks/aws_utils.rb` `setup_infra` (Fix row 4): after the phase-3 config rewrite, a best-effort strip of old jobs on `DB_HOST` and `DB_HOST_REPLICA` through the first app server (`ssh app 'ssh -i ~/.ssh/$KEYNAME.pem ubuntu@db …'`). Retry while SSH is not ready (~3 min cap); on any failure `puts` a warning and continue. No new phase number (keeps the report renderer unchanged). Verify: `ruby -c`; the code path cannot raise.
- [x] 3.4 `lib/tasks/db_backup_xtra.sh` restore branches (`:693-695`, `:731-733`) (Fix row 6): print "schedule is now live" only if `/etc/cron.d/irm-db-backup` exists, otherwise a loud `WARNING: armed but no backup schedule`. Verify: `bash -n lib/tasks/db_backup_xtra.sh`.
- [x] 3.5 Docs (Fix row 7): `docs/operations/dr/dr_guide.md` §10 and `docs/operations/dr/db_backup_system.md` §9. Explain the clone/old-job behaviour, the new verify grading and the residual early-boot window, with a mermaid diagram. Update `gap_review_2026_11.md` G19 to "fixed in code; awaiting drill".
- [x] 3.7 (found in review) `lib/tasks/db_backup_xtra.sh` `reset_lsn_state`: both restore branches clear `LSNDIR`/`LSNDIR_INCR` before arming (report Fix row 8). Verify: `bash -n`.
- [x] 3.8 (found in review) Replica schedule install warns instead of failing the DR. Verify: `ruby -c lib/tasks/backup_db.rake`.
- [x] 3.9 (found in review) Drill mode (report Fix row 9): `aws:dr_drill` sets/clears `DR_DRILL`; `config/deploy.rb` forwards it on `recovery:load_db_from_backups` and `recovery:verify`; `run_baked_restore` passes `DB_BACKUP_NO_ARM=1` and removes the marker on a drill primary; the script's `arm_backups` honours the flag; `dr:verify` grades with `grade_armed(drill:)`. Feature rows E7, E8, X5 added. Verify: `ruby -c` on all, `bash -n`.
- [x] 3.10 (added on review) Checkpoint reset + `restored_at` after every restore; `Dr::BackupSchedule.grade_checkpoint`; `dr:verify` "Backup checkpoint fresh" (report Fix row 10). Feature rows H4b, E9, E10, X6.
- [x] 3.6 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/misc/dr_backup_schedule.feature` and confirm all IDs are still green before starting phase 4.

## 4. Regression and cleanup

- [x] 4.1 Run the feature the fix touches: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/misc/dr_backup_schedule.feature`. The rest of `features/core` exercises no DR code, so running it would prove nothing about this fix.
- [ ] 4.2 Blast-radius callers (restore tasks, `partial:*`, `dr:fix:db_*`, `setup_infra`, `recovery:verify`) have no Cucumber coverage: they need AWS/SSH. They are covered by the staging drill (qa-checklist B1, R1–R3): `TEARDOWN=false rake "aws:dr_drill[in, ap-south-2, staging.in]"`, after checking that no other drill holds the Pulumi lock. Run the X1–X3 manual rows on the kept boxes (verify with `DR_DRILL=true`), then `pulumi destroy`.
- [x] 4.3 Run `bundle exec rubocop lib/dr/backup_schedule.rb lib/tasks/backup_db.rake lib/tasks/dr_verify.rake lib/tasks/aws_utils.rb features/step_definitions/dr_backup_schedule_steps.rb` and confirm it is clean, including `IRM/RelationBlankPresent`.
- [x] 4.4 N+1 check: not applicable — no ActiveRecord query, list page or job touched.
- [x] 4.5 UI check: not applicable — no screens touched (operator tooling only).
