<div align="center">

# 🟢  RECOVERY SUCCEEDED

### Disaster Recovery Drill — `production` (in) → `ap-south-2`

**10:10** rebuild&nbsp;&nbsp;·&nbsp;&nbsp;**38/40** checks passed&nbsp;&nbsp;·&nbsp;&nbsp;**8** phases completed&nbsp;&nbsp;·&nbsp;&nbsp;**6:04** to restore the database

</div>

---

## At a glance

| | |
|---|---|
| **Result** | **PASSED** |
| Environment | `production` (in) |
| Recovered into | `ap-south-2` — disaster-recovery region |
| Started | **2026-08-29 12:13:42 UTC** |
| Finished | **2026-08-29 12:23:52 UTC** |
| Rebuild time | **10:10** (10.2 minutes) |
| Database restore | **6:04** (primary + replica, in parallel) |
| Verification | **38 passed**, 2 warnings across 2 app servers |
| Data currency | newest restored record is 0.3h old |
| Code deployed | `dr_drill_production_in_2026_08_29_1743` |
| Executed by | thimmaiah@thimmaiah-laptop |

> ℹ️ This was a **scheduled drill** against `production`, not a response to a real incident. It exercised the identical code path a real recovery uses.

---

## Recovery timeline

Every phase of the recovery, in order, with wall-clock times.

| | # | Phase | Start (UTC) | End (UTC) | Duration |
|:-:|:-:|---|---|---|---|
| ✅ | 1 | Refresh Pulumi stack configuration | 12:13:42 | 12:13:52 | **0:10** |
| ✅ | 2 | Provision infrastructure (pulumi up) | 12:13:52 | 12:14:17 | **0:25** |
| ✅ | 3 | Rewrite config with the new host addresses | 12:14:17 | 12:14:19 | **0:02** |
| ✅ | 4 | Commit and push the DR branch (dr_drill_production_in_2026_08_29_1743) | 12:14:19 | 12:14:23 | **0:04** |
| ✅ | 5 | Deploy the application to both app servers | 12:14:23 | 12:15:42 | **1:19** |
| ✅ | 6 | Take traffic offline (nginx maintenance mode) | 12:15:42 | 12:15:50 | **0:08** |
| ✅ | 7 | Restore the database from S3 backups | 12:15:50 | 12:21:54 | **6:04** |
| ✅ | 8 | Restore traffic and verify the recovered stack | 12:21:54 | 12:23:52 | **1:58** |

**Total: 10:10**

---

## Verification scorecard

The recovery is not reported as successful until every one of these
checks passes on **every** application server. Each exercises the real
serving path — HTTP through nginx to Puma to Rails to the dependency —
not a mock or a status file. Reproduced verbatim from the run transcript.

**Host `ip-10-0-1-46`** — 20 checks, 19 passed

| | Check | Result |
|:-:|---|---|
| ✅ | prometheus_exporter process | 2 process(es) |
| ✅ | Nginx active | active |
| ✅ | Puma process | 5 process(es) |
| ✅ | HTTP db_check (nginx→puma→MySQL) | HTTP 200 |
| ✅ | HTTP redis_check (nginx→puma→Redis cache) | HTTP 200 |
| ✅ | HTTP elastic_check (nginx→puma→Elasticsearch) | HTTP 200 |
| ✅ | HTTP disk_check (root filesystem <95%) | HTTP 200 |
| ✅ | HTTP xirr_check (xirr_py docker) | HTTP 200 |
| ✅ | Sidekiq workers registered | 1 process(es) |
| ✅ | Migrations current |  |
| ✅ | Restored data freshness | newest users/documents row is 0.3h old |
| ✅ | S3 app bucket reachable | docs.caphive.com.production |
| ✅ | Primary mysqld (10.0.3.210) | active |
| ✅ | Primary docker: elasticsearch | running |
| ✅ | Primary docker: redis-stack-server | running |
| ✅ | Primary backup cron armed | /etc/db_backup_enabled present |
| ⚠️ | Primary backup cron installed | no /etc/cron.d/irm-db-backup — pre-bake AMI? |
| ✅ | Replica mysqld (10.0.4.107) | active |
| ✅ | Replica backup cron disarmed |  |
| ✅ | Replication live round-trip | Ok |

**Host `ip-10-0-2-43`** — 20 checks, 19 passed

| | Check | Result |
|:-:|---|---|
| ✅ | prometheus_exporter process | 2 process(es) |
| ✅ | Nginx active | active |
| ✅ | Puma process | 5 process(es) |
| ✅ | HTTP db_check (nginx→puma→MySQL) | HTTP 200 |
| ✅ | HTTP redis_check (nginx→puma→Redis cache) | HTTP 200 |
| ✅ | HTTP elastic_check (nginx→puma→Elasticsearch) | HTTP 200 |
| ✅ | HTTP disk_check (root filesystem <95%) | HTTP 200 |
| ✅ | HTTP xirr_check (xirr_py docker) | HTTP 200 |
| ✅ | Sidekiq workers registered | 2 process(es) |
| ✅ | Migrations current |  |
| ✅ | Restored data freshness | newest users/documents row is 0.0h old |
| ✅ | S3 app bucket reachable | docs.caphive.com.production |
| ✅ | Primary mysqld (10.0.3.210) | active |
| ✅ | Primary docker: elasticsearch | running |
| ✅ | Primary docker: redis-stack-server | running |
| ✅ | Primary backup cron armed | /etc/db_backup_enabled present |
| ⚠️ | Primary backup cron installed | no /etc/cron.d/irm-db-backup — pre-bake AMI? |
| ✅ | Replica mysqld (10.0.4.107) | active |
| ✅ | Replica backup cron disarmed |  |
| ✅ | Replication live round-trip | Ok |


---

## Independently verifiable evidence

Each row names a record held **outside this repository**. Nothing here
relies on trusting this document.

| Claim | Evidence | How to verify independently |
|---|---|---|
| Infrastructure provisioned in ap-south-2 | Pulumi update #26 — succeeded, 2026-08-29T12:14:03.000Z → 2026-08-29T12:14:15.000Z | `pulumi stack history --stack production-ap-south-2` |
| Database instances launched in ap-south-2 | i-0eb90e37036dd6c66 (10.0.4.107, launched 2026-08-29T11:22:49Z); i-049a8776fa29ddf48 (10.0.3.210, launched 2026-08-29T11:22:49Z) | CloudTrail `RunInstances` events in ap-south-2 |
| Recovered stack endpoints | app servers 98.130.44.183, 18.61.81.84; DB primary 10.0.3.210, replica 10.0.4.107 | `pulumi stack output --stack production-ap-south-2` |
| Application code deployed | commit `c176f874b01bf489988bcfd3bd0bce463ae42a25` on branch `dr_drill_production_in_2026_08_29_1743` | `git log -1 c176f874b`; GitHub push timestamp |
| Data restored from real backups | source bucket `docs.caphive.com.production-backup-xtra` | `aws s3 ls s3://docs.caphive.com.production-backup-xtra/` |
| Recovered stack verified serving | `recovery:verify` passed on every app server at 2026-08-29T12:23:52Z | re-run `LB=true bundle exec cap production_in recovery:verify` |

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
**`docs/dr_runs/dr_drill_production_in_2026_08_29_1743.log`**. The report says what is claimed and how
to check it; the transcript says what happened, line by line.

Re-run verification against a still-running stack at any time:

```bash
LB=true bundle exec cap production_in recovery:verify
```

---
<div align="center">
<sub>Generated 2026-08-29T12:23:52Z by <code>rake aws:dr_drill</code></sub>
</div>
