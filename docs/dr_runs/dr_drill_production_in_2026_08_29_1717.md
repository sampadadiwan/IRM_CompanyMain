# Disaster Recovery Drill Report

| | |
|---|---|
| **Result** | **FAILED** |
| Stack | production (in) |
| Target region | ap-south-2 |
| Branch deployed | `dr_drill_production_in_2026_08_29_1717` |
| Started | 2026-08-29T11:47:54Z |
| Finished | 2026-08-29T11:55:48Z |
| Measured rebuild time | **7:54** (7.9 min) |
| Executed by | thimmaiah@thimmaiah-laptop |

> This was a **drill** against `production`, not a response to a real incident.

## What the measured time does and does not cover

The figure above is **rebuild time**, not end-to-end RTO. It is measured
from the start of the recovery command to the point where the stack passed
verification.

**Included:** Pulumi provisioning, config rewrite, application deploy to
both app servers, database restore from S3 (primary + replica in
parallel), replication reset, migration replay, and the full
`recovery:verify` health scorecard.

**Excluded:** incident detection, the human decision to declare a disaster
(DR_GUIDE §4), and DNS cutover plus TTL propagation — `aws:dns_cutover` is
manual by design and is never invoked by the recovery sequence (DR_GUIDE
§8). A true incident-to-service-restored RTO is this figure **plus** those
three components.

## Phase timings

| Phase | Duration |
|---|---|
| Phase 1/8 · Refresh Pulumi stack configuration | 0:08 |
| Phase 2/8 · Provision infrastructure (pulumi up) | 0:21 |
| Phase 3/8 · Rewrite config with the new host addresses | 0:02 |
| Phase 4/8 · Commit and push the DR branch (dr_drill_production_in_2026_08_29_1717) | 0:04 |
| Phase 5/8 · Deploy the application to both app servers | 1:13 |
| Phase 6/8 · Take traffic offline (nginx maintenance mode) | 0:07 |
| Phase 7/8 · Restore the database from S3 backups | 5:59 |

## Independently verifiable evidence

Each row names a record held outside this repository. Nothing here relies
on trusting this file.

| Claim | Evidence | How to verify independently |
|---|---|---|
| Infrastructure provisioned in ap-south-2 | Pulumi update #23 — succeeded, 2026-08-29T11:48:12.000Z → 2026-08-29T11:48:22.000Z | `pulumi stack history --stack production-ap-south-2` (server-side record, Pulumi console) |
| Database instances launched in ap-south-2 | i-0eb90e37036dd6c66 (10.0.4.107, launched 2026-08-29T11:22:49Z); i-049a8776fa29ddf48 (10.0.3.210, launched 2026-08-29T11:22:49Z) | CloudTrail `RunInstances` events in ap-south-2; `aws ec2 describe-instances --region ap-south-2` |
| Recovered stack endpoints | app servers 98.130.44.183, 18.61.81.84; DB primary 10.0.3.210, replica 10.0.4.107 | `pulumi stack output --stack production-ap-south-2` |
| Application code deployed | commit `7d17fa8411f68e9d6e1367e01f1c1e27b171ed39` on branch `dr_drill_production_in_2026_08_29_1717` (pushed to origin) | `git log -1 7d17fa841`; GitHub branch push timestamp |

## Verification result

The recovery sequence fails loudly unless `cap production_in recovery:verify`
passes on every app server — it checks nginx, puma, sidekiq registration,
HTTP through the full serving chain to MySQL / Redis / Elasticsearch / S3,
migration currency, restored-data freshness, DB-box daemons, backup cron
arming, and a live replication round-trip. The per-check scorecard is in
the run transcript.

Re-run at any time against a still-running stack:

```bash
LB=true bundle exec cap production_in recovery:verify
```

## Full transcript

The complete console output of this run — every command, its output, and
the verification scorecard — was captured automatically to
`docs/dr_runs/dr_drill_production_in_2026_08_29_1717.log`. Read it alongside this report: the report
says what is claimed and how to check it independently, the transcript
says what actually happened, line by line.

---
Generated 2026-08-29T11:55:48Z by `rake aws:dr_drill`.
