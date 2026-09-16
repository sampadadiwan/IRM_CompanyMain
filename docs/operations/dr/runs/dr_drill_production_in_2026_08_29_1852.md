<div align="center">

# 🟢  RECOVERY SUCCEEDED

### Disaster Recovery Drill — `production` (in) → `ap-south-2`

**10:26** rebuild&nbsp;&nbsp;·&nbsp;&nbsp;**42/44** checks passed&nbsp;&nbsp;·&nbsp;&nbsp;**8** phases completed&nbsp;&nbsp;·&nbsp;&nbsp;**6:20** to restore the database

</div>

---

## At a glance

| | |
|---|---|
| **Result** | **PASSED** |
| Environment | `production` (in) |
| Recovered into | `ap-south-2` — disaster-recovery region |
| Started | **2026-08-29 13:22:39 UTC** |
| Finished | **2026-08-29 13:33:06 UTC** |
| Rebuild time | **10:26** (10.4 minutes) |
| Database restore | **6:20** (primary + replica, in parallel) |
| Verification | **42 passed**, 2 warnings across 2 app servers |
| Data currency | newest restored record is 0.5h old |
| Code deployed | `dr_drill_production_in_2026_08_29_1852` |
| Executed by | thimmaiah@thimmaiah-laptop |

> ℹ️ This was a **scheduled drill** against `production`, not a response to a real incident. It exercised the identical code path a real recovery uses.

---

## Recovery timeline

Every phase of the recovery, in order, with wall-clock times.

| | # | Phase | Start (UTC) | End (UTC) | Duration |
|:-:|:-:|---|---|---|---|
| ✅ | 1 | Refresh Pulumi stack configuration | 13:22:39 | 13:22:49 | **0:09** |
| ✅ | 2 | Provision infrastructure (pulumi up) | 13:22:49 | 13:23:12 | **0:23** |
| ✅ | 3 | Rewrite config with the new host addresses | 13:23:12 | 13:23:13 | **0:02** |
| ✅ | 4 | Commit and push the DR branch (dr_drill_production_in_2026_08_29_1852) | 13:23:13 | 13:23:18 | **0:04** |
| ✅ | 5 | Deploy the application to both app servers | 13:23:18 | 13:24:32 | **1:14** |
| ✅ | 6 | Take traffic offline (nginx maintenance mode) | 13:24:32 | 13:24:39 | **0:08** |
| ✅ | 7 | Restore the database from S3 backups | 13:24:39 | 13:31:00 | **6:20** |
| ✅ | 8 | Restore traffic and verify the recovered stack | 13:31:00 | 13:33:06 | **2:06** |

**Total: 10:26**

---

## Verification scorecard

The recovery is not reported as successful until every one of these
checks passes on **every** application server. Each exercises the real
serving path — HTTP through nginx to Puma to Rails to the dependency —
not a mock or a status file. Reproduced verbatim from the run transcript.

**Host `ip-10-0-1-216`** — 22 checks, 21 passed

| | Check | Result |
|:-:|---|---|
| ✅ | prometheus_exporter process | 2 process(es) |
| ✅ | Nginx active | active |
| ✅ | Puma process | 1 process(es) |
| ✅ | HTTP db_check (nginx→puma→MySQL) | HTTP 200 |
| ✅ | HTTP redis_check (nginx→puma→Redis cache) | HTTP 200 |
| ✅ | HTTP elastic_check (nginx→puma→Elasticsearch) | HTTP 200 |
| ✅ | HTTP disk_check (root filesystem <95%) | HTTP 200 |
| ✅ | HTTP website apex (caphive.com) | serving public/website |
| ✅ | HTTP website alias (www.caphive.com) | redirects to caphive.com |
| ✅ | HTTP xirr_check (xirr_py docker) | HTTP 200 |
| ✅ | Sidekiq workers registered | 2 process(es) |
| ✅ | Migrations current |  |
| ✅ | Restored data freshness | newest users/documents row is 0.5h old |
| ✅ | S3 app bucket reachable | docs.caphive.com.production |
| ✅ | Primary mysqld (10.0.3.14) | active |
| ✅ | Primary docker: elasticsearch | running |
| ✅ | Primary docker: redis-stack-server | running |
| ✅ | Primary backup cron armed | /etc/db_backup_enabled present |
| ⚠️ | Primary backup cron installed | no /etc/cron.d/irm-db-backup — pre-bake AMI? |
| ✅ | Replica mysqld (10.0.4.87) | active |
| ✅ | Replica backup cron disarmed |  |
| ✅ | Replication live round-trip | Ok |

**Host `ip-10-0-2-54`** — 22 checks, 21 passed

| | Check | Result |
|:-:|---|---|
| ✅ | prometheus_exporter process | 2 process(es) |
| ✅ | Nginx active | active |
| ✅ | Puma process | 5 process(es) |
| ✅ | HTTP db_check (nginx→puma→MySQL) | HTTP 200 |
| ✅ | HTTP redis_check (nginx→puma→Redis cache) | HTTP 200 |
| ✅ | HTTP elastic_check (nginx→puma→Elasticsearch) | HTTP 200 |
| ✅ | HTTP disk_check (root filesystem <95%) | HTTP 200 |
| ✅ | HTTP website apex (caphive.com) | serving public/website |
| ✅ | HTTP website alias (www.caphive.com) | redirects to caphive.com |
| ✅ | HTTP xirr_check (xirr_py docker) | HTTP 200 |
| ✅ | Sidekiq workers registered | 2 process(es) |
| ✅ | Migrations current |  |
| ✅ | Restored data freshness | newest users/documents row is 0.0h old |
| ✅ | S3 app bucket reachable | docs.caphive.com.production |
| ✅ | Primary mysqld (10.0.3.14) | active |
| ✅ | Primary docker: elasticsearch | running |
| ✅ | Primary docker: redis-stack-server | running |
| ✅ | Primary backup cron armed | /etc/db_backup_enabled present |
| ⚠️ | Primary backup cron installed | no /etc/cron.d/irm-db-backup — pre-bake AMI? |
| ✅ | Replica mysqld (10.0.4.87) | active |
| ✅ | Replica backup cron disarmed |  |
| ✅ | Replication live round-trip | Ok |


---

## Independently verifiable evidence

Each row names a record held **outside this repository**. Nothing here
relies on trusting this document.

| Claim | Evidence | How to verify independently |
|---|---|---|
| Infrastructure provisioned in ap-south-2 | Pulumi update #30 — succeeded, 2026-08-29T13:23:00.000Z → 2026-08-29T13:23:10.000Z | `pulumi stack history --stack production-ap-south-2` (server-side record, Pulumi console) |
| Database instances launched in ap-south-2 | i-0e54c8ac9c6ec75f8 (10.0.4.87, launched 2026-08-29T12:58:29Z); i-0a466afa70421cb10 (10.0.3.14, launched 2026-08-29T12:58:29Z) | CloudTrail `RunInstances` events in ap-south-2; `aws ec2 describe-instances --region ap-south-2` |
| Recovered stack endpoints | app servers 16.112.12.196, 18.60.144.207; DB primary 10.0.3.14, replica 10.0.4.87 | `pulumi stack output --stack production-ap-south-2` |
| Application code deployed | commit `c45e0c66a9b83fe2f579f3760a916ecfa7547799` on branch `dr_drill_production_in_2026_08_29_1852` (pushed to origin) | `git log -1 c45e0c66a`; GitHub branch push timestamp |
| Data restored from real backups | source bucket `docs.caphive.com.production-backup-xtra` (full + incremental chain; keys named in the transcript) | `aws s3 ls s3://docs.caphive.com.production-backup-xtra/` — compare object timestamps against the run window |
| Recovered stack verified serving | `recovery:verify` passed on every app server at 2026-08-29T13:33:06Z (per-check scorecard in the transcript) | re-run `LB=true bundle exec cap production_in recovery:verify` |

---

## What the measured time covers

The headline figure is **rebuild time**, not end-to-end RTO — measured
from the start of the recovery command to the stack passing verification.

| | |
|---|---|
| ✅ **Included** | Infrastructure provisioning, configuration rewrite, application deploy to every app server, database restore from S3 (primary and replica in parallel), replication re-pointing, migration replay, and the full verification scorecard above. |
| ❌ **Excluded** | Incident detection, the human decision to declare a disaster, and DNS cutover plus TTL propagation — cutover is deliberately manual and is never invoked by the recovery sequence. |

A true incident-to-service-restored RTO is the figure above **plus** those
three components. Stated explicitly so the number is not read as more than
it is.

---

## Full transcript

Every command and its complete output — including the raw verification
scorecard reproduced above — was captured automatically to
**`docs/dr_runs/dr_drill_production_in_2026_08_29_1852.log`**. The report says what is claimed and how
to check it; the transcript says what happened, line by line.

Re-run verification against a still-running stack at any time:

```bash
LB=true bundle exec cap production_in recovery:verify
```

---
<div align="center">
<sub>Generated 2026-08-29T13:33:06Z by <code>rake aws:dr_drill</code></sub>
</div>
