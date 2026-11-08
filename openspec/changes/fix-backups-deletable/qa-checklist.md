# Any app key can delete every backup — Manual QA Checklist

> **Audience:** The operator. Every row is **(dev)**. **Companion:** [Report](report.md)

**ID legend:** **B** = original bug · **H** = Happy · **E** = Edge · **X** = Error · **R** = Regression · **C** = Cross-cutting

## Contents

- [Test Setup](#test-setup) · [The Original Bug](#the-original-bug) · [Happy Path](#happy-path) · [Error Cases](#error-cases) · [Regression](#regression) · [Cross-cutting Checks](#cross-cutting-checks) · [Sign-off](#sign-off)

## Test Setup

| Item | Detail |
|---|---|
| Staging keys | `.env.staging.in` + `config/credentials/staging.in.key` |
| Remember | Turning Object Lock on is permanent; compliance-locked versions stay 30 days |

## The Original Bug

| ☐ | ID | What to check | Steps | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | B1 **(dev)** | The app key can no longer delete a replica backup | `PROVE=1 EXECUTE=1 rake "aws:lock_replica_buckets[staging.in]"` | Marker replicated; retention COMPLIANCE until about +30 d; delete with the app key **and** the bypass header → **AccessDenied** | | |

## Happy Path

| ☐ | ID | What to check | Steps | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | H1 **(dev)** | Dry run first | `rake "aws:lock_replica_buckets[staging.in]"` | Lists the two replica buckets and "enable Object Lock + COMPLIANCE 30 d"; changes nothing | | |
| ☐ | H2 **(dev)** | Documents replica locked too | After apply, read `docs.altx.com.staging-replica`'s Object Lock configuration | COMPLIANCE, 30 days | | |
| ☐ | H3 **(dev)** | Readiness | `rake "aws:dr_readiness[staging, in, ap-south-2, staging.in]"` | "Replica backups locked" ✅ | | |

## Error Cases

| ☐ | ID | What to check | Steps | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | X4 **(dev)** | Production refused | `rake "aws:lock_replica_buckets[production.in]"` | Refused without `ALLOW_PRODUCTION=1`; nothing touched | | |
| ☐ | X1–X3, X5 | Automated suite | — | N/A by hand | | |

## Regression

| ☐ | ID | What still has to work | Steps | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 **(dev)** | Replication keeps flowing | Next day: `rake "s3:backup_daily_report[staging.in]"` | Replica newest backup as recent as the primary | | |
| ☐ | R2 **(dev)** | Restore from the replica still works | Next staging drill with `BUCKET_OVERRIDE` set to the replica, or the normal drill | PASSED | | |
| ☐ | R3 **(dev)** | Primary buckets unchanged | Read the primaries' Object Lock configuration | Not enabled | | |

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Alerts / emails | None changed | | |
| ☐ | C2–C6 | Screens, dates, mobile, tenant, look | N/A | | |

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | staging.in | | | |
