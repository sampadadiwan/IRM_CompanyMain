<div align="center">

# 🔴  RECOVERY FAILED

### Disaster Recovery Drill — `production` (in) → `ap-south-2`

**14:30** rebuild&nbsp;&nbsp;·&nbsp;&nbsp;**0/0** checks passed&nbsp;&nbsp;·&nbsp;&nbsp;**8** phases completed&nbsp;&nbsp;·&nbsp;&nbsp;**6:45** to restore the database

</div>

---

## At a glance

| | |
|---|---|
| **Result** | **FAILED** |
| Environment | `production` (in) |
| Recovered into | `ap-south-2` — disaster-recovery region |
| Started | **2026-08-29 12:57:35 UTC** |
| Finished | **2026-08-29 13:12:05 UTC** |
| Rebuild time | **14:30** (14.5 minutes) |
| Database restore | **6:45** (primary + replica, in parallel) |
| Verification | **0 passed** across 0 app servers |
| Code deployed | `dr_drill_production_in_2026_08_29_1827` |
| Executed by | thimmaiah@thimmaiah-laptop |

> ℹ️ This was a **scheduled drill** against `production`, not a response to a real incident. It exercised the identical code path a real recovery uses.

---

## Recovery timeline

Every phase of the recovery, in order, with wall-clock times.

| | # | Phase | Start (UTC) | End (UTC) | Duration |
|:-:|:-:|---|---|---|---|
| ✅ | 1 | Refresh Pulumi stack configuration | 12:57:35 | 12:57:44 | **0:09** |
| ✅ | 2 | Provision infrastructure (pulumi up) | 12:57:44 | 13:01:27 | **3:43** |
| ✅ | 3 | Rewrite config with the new host addresses | 13:01:27 | 13:01:29 | **0:02** |
| ✅ | 4 | Commit and push the DR branch (dr_drill_production_in_2026_08_29_1827) | 13:01:29 | 13:01:33 | **0:04** |
| ✅ | 5 | Deploy the application to both app servers | 13:01:33 | 13:05:01 | **3:28** |
| ✅ | 6 | Take traffic offline (nginx maintenance mode) | 13:05:01 | 13:05:13 | **0:13** |
| ✅ | 7 | Restore the database from S3 backups | 13:05:13 | 13:11:58 | **6:45** |
| ⏹ | 8 | Restore traffic and verify the recovered stack | 13:11:58 | 13:12:05 | **0:07** |

**Total: 14:30**

---

## Verification scorecard

The recovery is not reported as successful until every one of these
checks passes on **every** application server. Each exercises the real
serving path — HTTP through nginx to Puma to Rails to the dependency —
not a mock or a status file. Reproduced verbatim from the run transcript.

_No verification scorecard was captured — the run did not reach `recovery:verify`._

---

## Independently verifiable evidence

Each row names a record held **outside this repository**. Nothing here
relies on trusting this document.

| Claim | Evidence | How to verify independently |
|---|---|---|
| Infrastructure provisioned in ap-south-2 | Pulumi update #29 — succeeded, 2026-08-29T12:57:56.000Z → 2026-08-29T13:01:25.000Z | `pulumi stack history --stack production-ap-south-2` (server-side record, Pulumi console) |
| Database instances launched in ap-south-2 | i-0e54c8ac9c6ec75f8 (10.0.4.87, launched 2026-08-29T12:58:29Z); i-0a466afa70421cb10 (10.0.3.14, launched 2026-08-29T12:58:29Z) | CloudTrail `RunInstances` events in ap-south-2; `aws ec2 describe-instances --region ap-south-2` |
| Recovered stack endpoints | app servers 16.112.12.196, 18.60.144.207; DB primary 10.0.3.14, replica 10.0.4.87 | `pulumi stack output --stack production-ap-south-2` |
| Application code deployed | commit `ae1c36158976f202045da743d09073c489131608` on branch `dr_drill_production_in_2026_08_29_1827` (pushed to origin) | `git log -1 ae1c36158`; GitHub branch push timestamp |
| Data restored from real backups | source bucket `docs.caphive.com.production-backup-xtra` (full + incremental chain; keys named in the transcript) | `aws s3 ls s3://docs.caphive.com.production-backup-xtra/` — compare object timestamps against the run window |

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
**`docs/dr_runs/dr_drill_production_in_2026_08_29_1827.log`**. The report says what is claimed and how
to check it; the transcript says what happened, line by line.

Re-run verification against a still-running stack at any time:

```bash
LB=true bundle exec cap production_in recovery:verify
```

---
<div align="center">
<sub>Generated 2026-08-29T13:12:05Z by <code>rake aws:dr_drill</code></sub>
</div>
