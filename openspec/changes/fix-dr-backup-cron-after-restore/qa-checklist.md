# DR restore leaves no backup schedule — Manual QA Checklist

> **Audience:** Whoever runs DR drills, i.e. an operator with staging AWS access. Every row here is
> operator work run from a terminal. There are no app screens, so every row is **(dev)**.
> **Companion document:** [Report](report.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the run log path in Notes. Row IDs match the report's Verification table (H/E/X).

**ID legend:** **B** = the original bug, reproduced · **H** = Happy path · **E** = Edge case ·
**X** = Error case · **R** = Regression (from Blast Radius) · **C** = Cross-cutting check ·
**(dev)** = needs an operator with AWS/SSH access

---

## Contents

- [Test Setup](#test-setup)
- [The Original Bug](#the-original-bug)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [Regression](#regression)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

---

## Test Setup

| Item | Detail |
|---|---|
| Environment | staging.in, drilled into ap-south-2 |
| Accounts | Staging AWS keys, `altxdev.pem`, the S3 Pulumi backend login |
| Before starting | Nobody else running a drill on `staging-ap-south-2` (a lock clash looks like a failure) |
| Run | `TEARDOWN=false rake "aws:dr_drill[in, ap-south-2, staging.in]"`. Keep the boxes up for rows H/E/X, then tear down by hand |
| Drill mode | A drill **never arms** its primary (the live box still writes the same bucket). Every hand-run verify on drill boxes needs `DR_DRILL=true` in front: `DR_DRILL=true LB=true bundle exec cap staging_in recovery:verify` |
| Look at a DR DB box | SSH to a drill app server, then `ssh -i ~/.ssh/altxdev.pem ubuntu@<DB_HOST>`. List with `crontab -l`, `sudo crontab -l`, `ls /etc/cron.d` |
| Tear down afterwards | `cd ../IRM-Infra && pulumi destroy --stack staging-ap-south-2 --yes` |

---

## The Original Bug

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | B1 **(dev)** | The drill no longer passes with backups off | 1. Run the drill (setup). 2. Read the verify scorecard in `docs/operations/dr/runs/<branch>.md` | Result **PASSED**. **No** "⚠️ Primary backup cron installed" row. The primary shows ✅ "Primary backup schedule (single writer)" and ✅ "Primary backup cron NOT armed (drill)" | | |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 **(dev)** | Old jobs removed, docker start-up lines kept | Drill boxes up | 1. On the DR primary, `crontab -l`. 2. Same on the replica | Only the two `@reboot … docker run` lines remain. No `backup_db.sh` line on either box | | |
| ☐ | H2 **(dev)** | Drill primary is scheduled but never writes the live chain | Drill boxes up past the next `:00` or `:30` | 1. On the primary: `ls /etc/cron.d/irm-db-backup /etc/db_backup_enabled /var/lib/xtrabackup/lsndir`. 2. `sudo tail /var/log/db_backup.log`. 3. Check the live bucket has no prefix written at a `:30` | Schedule exists; marker and lsndir **absent**. The log says "Backups not armed on this host — skipping". No `:30` prefix in the live staging bucket (live writes only at `:00`) | | |
| ☐ | H3 **(dev)** | Replica stays silent | Same | 1. On the replica: `ls /etc/db_backup_enabled`. 2. `sudo tail /var/log/db_backup.log` | No marker. The log says "Backups not armed on this host — skipping" | | |
| ☐ | H4 **(dev)** | Schedule identical to the baked one | — | Compare `/etc/cron.d/irm-db-backup` on the primary with the schedule in the Packer recipe | Same lines | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 **(dev)** | Re-running the restore changes nothing extra | Drill boxes up | Run `bundle exec cap staging_in partial:restore_replica` against the drill branch | The log says nothing to strip; the schedule file is unchanged | | |
| ☐ | E5 **(dev)** | Live box is warned, not failed | — | Read the report's E5 row; on staging (live) a developer runs verify only if safe | Old job only → ⚠️ "old unguarded job", not ❌ | | |
| ☐ | E2, E3, E4, E6, E7, E8 | Covered by the automated suite only | — | — | N/A by hand: pure text-handling cases | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message shown) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X6 **(dev)** | Stale checkpoint → verify fails | Drill boxes up | 1. On the primary: `sudo mkdir -p /var/lib/xtrabackup/lsndir && sudo touch -d '2 days ago' /var/lib/xtrabackup/lsndir/xtrabackup_checkpoints`. 2. Drill-mode verify. 3. `sudo rm -rf /var/lib/xtrabackup/lsndir` | ❌ "checkpoint predates the restore" | | |
| ☐ | X1 **(dev)** | No schedule → verify fails | Drill boxes up | 1. On the primary: `sudo mv /etc/cron.d/irm-db-backup /tmp/`. 2. `DR_DRILL=true LB=true bundle exec cap staging_in recovery:verify` (drill branch). 3. Move the file back | ❌ "no backups will run". Verify exits non-zero | | |
| ☐ | X3 **(dev)** | Replica writer → verify fails | Same | 1. On the replica, add `0 * * * * /home/ubuntu/backup_db.sh incr` to `crontab -e`. 2. Run verify. 3. Remove the line | ❌ "replica must never write" | | |
| ☐ | X2 **(dev)** | Two writers on the primary → verify fails | Same | Same as X3, but on the primary | ❌ "two writers" | | |
| ☐ | X4 | Marker missing (real recovery) | — | Covered by the automated suite — a drill cannot arm safely | N/A by hand | | |
| ☐ | X5 **(dev)** | Armed drill primary → verify fails | Drill boxes up | 1. On the primary: `sudo touch /etc/db_backup_enabled`. 2. **Immediately** run the drill-mode verify. 3. `sudo rm /etc/db_backup_enabled` at once — do not let a `:00`/`:30` pass while armed | ❌ "would write into the live backup chain" | | |

---

## Regression

| ☐ | ID | What still has to work | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 **(dev)** | Full drill end to end | B1 run | PASSED; rebuild time in line with ~12 min; teardown destroys everything | | |
| ☐ | R2 **(dev)** | `partial:restore_replica` / `dr:fix:db_replica` on the drill stack | Run `partial:restore_replica` on the drill branch | Restore completes; replication round-trip ✅; replica has no marker and no old job | | |
| ☐ | R3 **(dev)** | `recovery:verify` on the drill stack after R2 | Run verify | All ✅ (no new ❌) | | |
| ☐ | R4 **(dev)** | Live staging backups unaffected | After the drill, check the newest prefix in `docs.altx.com.staging-backup-xtra` | A new hourly incremental from the live box, as before | | |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Dates on screens | N/A: no screens touched | | |
| ☐ | C2 | Dates in emails | N/A: no emails touched | | |
| ☐ | C3 | Narrow / mobile width | N/A: terminal tooling only | | |
| ☐ | C4 | Tenant isolation | N/A: infrastructure, no tenant data paths | | |
| ☐ | C5 | Tools the fix touched | Restore, verify and drill still do everything they did before (R1–R3) | | |
| ☐ | C6 | Looks like CapHive | N/A: no UI | | |
| ☐ | C7 | Speed | DB restore phase within ±1 min of the 2026-11-08 baseline (1:59) | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | staging.in → ap-south-2 | | | |
