# Tasks

> Reproduce first; phase gate per group. Every cucumber run: fresh `TEST_ENV_NUMBER`, Redis on 6379, background + `wait $pid`.

## 1. Reproduce

- [x] 1.1 Write `features/misc/dr_backups_locked.feature` + steps for H1–H3, E1–E2, X1–X5 (lock plan, readiness grade, primary refusal, env guard).
- [x] 1.2 Run it; confirm it fails against current code. Record the output.
      - Before the fix: 12 scenarios (12 failed) — `uninitialized constant Dr::BackupLock`.

## 2. Fix — pure logic + helper (report Fix rows 1, 4)

- [x] 2.1 `Dr::BackupLock` (new, `lib/dr/backup_lock.rb`): `plan(current_config, days: 30)`, `grade(current_config, days: 30)`, `replicas_to_lock(primaries:, destinations:)` (replicas come from the primaries' replication rules), `env_allowed?(env, allow_production:)`. Required from `dr_requires.rb`.
- [x] 2.2 `AwsUtils#s3_ensure_object_lock!(client:, bucket:, days: 30)`: reads the current config, applies the plan (`put_object_lock_configuration` with `object_lock_enabled: "Enabled"` + `default_retention: { mode: "COMPLIANCE", days: }`), idempotent, refuses primaries.
- [x] 2.3 Run the feature: all rows pass.

## 3. Fix — task, readiness, provisioning, docs (report Fix rows 2, 3, 5, 6)

- [x] 3.1 `rake "aws:lock_replica_buckets[env]"`: account guard, replica buckets of the env (backup + documents), dry run / `EXECUTE=1`, production refused without `ALLOW_PRODUCTION=1`, irreversibility warning, `PROVE=1` marker check (replicate, read retention, delete-with-bypass using the app key → AccessDenied).
- [x] 3.2 `aws:dr_readiness`: "Replica backups locked".
- [x] 3.3 `aws:provision_s3_buckets`: ensure the lock on replica buckets (only with `LOCK_REPLICAS=1`: permanent, so never a side effect).
- [x] 3.6 Replication role: add `s3:GetObjectRetention` + `s3:GetObjectLegalHold` on the source side (AWS asks for them when replicating into Object Lock buckets; the live staging role lacked them). Both role definitions in code + the task upserts the live inline policy before locking. Scenario E3.
- [x] 3.4 Docs: DR guide, `db_backup_system.md`, gap review G2 (fixed for staging) + new G25 (over-privileged shared app keys).
- [x] 3.5 Run all DR features: green; rubocop clean.
      - 127 scenarios (127 passed) across `features/misc/dr_*.feature`.

## 4. Apply (each step needs the user's go-ahead)

- [x] 4.1 Staging: dry run → `EXECUTE=1` → `PROVE=1`; QA B1, H1–H3, R1, R3.
      - Applied 2026-11-08 ~09:00 UTC. Role gained the two permissions; both replicas COMPLIANCE 30 d, verified. Proof marker `dr-lock-check/20261108085959.txt` replicated, locked until 2026-12-08T09:00:20Z, app key + bypass → AccessDenied. Re-run: nothing to do. Readiness ✅ both. Primaries: not enabled (R3). Pending: R1 (tomorrow's daily report), R2 (next drill).
- [ ] 4.2 Production IN: separate go-ahead, after the staging proof.
- [ ] 4.3 Production US: separate go-ahead.
- [x] 4.4 N+1 / UI checks: not applicable — no queries, no screens.
