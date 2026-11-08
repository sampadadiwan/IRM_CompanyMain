# Staging RPO + backup size check — Manual QA Checklist

> **Audience:** The operator. Every row is **(dev)**. **Companion:** [Report](report.md)

**ID legend:** **B** = original bug · **H** = Happy · **E** = Edge · **X** = Error · **R** = Regression · **C** = Cross-cutting

## Contents

- [Test Setup](#test-setup) · [The Original Bug](#the-original-bug) · [Happy Path](#happy-path) · [Error Cases](#error-cases) · [Regression](#regression) · [Cross-cutting Checks](#cross-cutting-checks) · [Sign-off](#sign-off)

## Test Setup

| Item | Detail |
|---|---|
| Staging keys | `.env.staging.in` + `config/credentials/staging.in.key`; `altxdev.pem` |
| Timing | Not within 5 min of :00 or :30 |

## The Original Bug

| ☐ | ID | What to check | Steps | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | B1 **(dev)** | Staging backs up every 30 min | 1. `rake "dr:set_backup_cadence[staging.in]"` (dry run). 2. Same with `EXECUTE=1`. 3. Next day: `rake "s3:backup_daily_report[staging.in]"` | Dry run shows the one-line change; apply shows "verified"; report shows **46** incrementals in 24 h | | |
| ☐ | B2 **(dev)** | Next drill meets RPO | Run a staging drill | "Recovery point (RPO)" ✅ (≤30 min) | | |

## Happy Path

| ☐ | ID | What to check | Steps | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | H2 **(dev)** | Size check silent on healthy backups | `rake "aws:dr_readiness[staging, in, ap-south-2, staging.in]"` | Backup freshness ✅, no size warning | | |

## Error Cases

| ☐ | ID | What to check | Steps | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | X1 **(dev)** | Production refused | `rake "dr:set_backup_cadence[production.in]"` | Refused: staging only; nothing touched | | |
| ☐ | X3 | Truncated full alerts | Automated suite | N/A by hand | | |

## Regression

| ☐ | ID | What still has to work | Steps | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 **(dev)** | Staging backups keep landing | `rake "s3:backup_daily_report[staging.in]"` an hour after applying | New incrementals at :00 and :30; chain unbroken | | |
| ☐ | R2 **(dev)** | Rollback works | (only if needed) `crontab ~/crontab.before-30min.<ts>` on the DB server | Old schedule back | | |

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Alerts | A size failure alerts through the existing freshness alert email | | |
| ☐ | C2–C6 | Screens, dates, mobile, tenant, look | N/A: no screens | | |

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | staging.in | | | |
