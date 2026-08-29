# Disaster Recovery Drill Report

| | |
|---|---|
| **Result** | **FAILED** |
| Stack | production (in) |
| Target region | ap-south-2 |
| Branch deployed | `dr_drill_production_in_2026_08_29_1647` |
| Started | 2026-08-29T11:17:32Z |
| Finished | 2026-08-29T11:19:49Z |
| Measured rebuild time | **2:17** (2.3 min) |
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
| Phase 1/8 · Refresh Pulumi stack configuration | 0:09 |
| Phase 2/8 · Provision infrastructure (pulumi up) | 2:08 |

## Independently verifiable evidence

Each row names a record held outside this repository. Nothing here relies
on trusting this file.

| Claim | Evidence | How to verify independently |
|---|---|---|


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
`docs/dr_runs/dr_drill_production_in_2026_08_29_1647.log`. Read it alongside this report: the report
says what is claimed and how to check it independently, the transcript
says what actually happened, line by line.

---
Generated 2026-08-29T11:19:49Z by `rake aws:dr_drill`.
