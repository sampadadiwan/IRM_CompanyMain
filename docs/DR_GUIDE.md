# Disaster Recovery Guide

The single document for a DR event: how to decide, what to run, what happens
underneath, and what to check before declaring recovery complete.
Companion docs: `lib/tasks/Caphive infra setup.md` (full setup runbook),
`docs/db_backup_system.md` (how backups get credentials/buckets — build to
runtime, newcomer-friendly), `docs/dr_review/` (design rationale per hardening
point), `docs/dr_drills.md` (drill evidence + measured RTO).

**Proven numbers (staging drill, 2026-07-08):** full region rebuild in
**8 minutes** unattended. Design RPO: **30 minutes** (incremental backup
cadence) — *provided the backup freshness alert is green* (see §1).

## Quick card (mid-incident, start here)

```bash
# Am I ready? (30 seconds, read-only)
rake "aws:dr_readiness[production, in, ap-south-2, production.in]"

# The recovery (one command, unattended):
RAILS_ENV=production rake "aws:setup_infra[production, AppServer, DB-Redis-ES, ap-south-2, in, production.in, dr_prod_in_<date>]"

# Go live (only after §6 checks pass; asks confirmation):
rake "aws:dns_cutover[production, ap-south-2, in]"
```

**Drill vs the real thing:** `aws:dr_drill` is a thin *rehearsal wrapper*
around `aws:setup_infra` — same engine, but it uses a throwaway branch, logs
PASS/FAIL + RTO to `docs/dr_drills.md`, and can tear down after. For a real
DR **or a permanent region migration**, call `aws:setup_infra` directly with
a branch name you intend to merge.

---

## 0. Scenario → response

| What broke | Response | DNS change? |
|---|---|---|
| One app server down | No DR. `pulumi up` the stack (recreates it), `cap <stage> deploy` | No |
| DB primary down/corrupt, region fine | Restore in place: §4 single command on the DB box (or promote replica) | No |
| Whole primary region lost (compute) | **Full DR**: §3 one-command rebuild in the backup region | Yes — §5 |
| Primary region's **S3** also unreachable | Full DR + restore from the **replica bucket**: §3 with §4's bucket override | Yes — §5 |
| Bad deploy / app-level data damage | Not this guide — point-in-time restore from a chosen chain: `restore_from_primary <full_key> [incr_key]` on the DB box | No |

Region pairs: **IN** production ap-south-1 → ap-south-2 · **US** us-east-1
(rebuild in place or extend). Staging mirrors IN.

## 1. Always-true readiness — one command

```bash
rake "aws:dr_readiness[<stack>, <variant>, <dr-region>, <env>]"
# e.g. rake "aws:dr_readiness[production, in, ap-south-2, production.in]"
#      rake "aws:dr_readiness"    # defaults: staging, in, $AWS_BACKUP_REGION
```

Read-only, ~30s, prints a ✅/⚠️/❌ scorecard and exits non-zero on any hard
failure (suitable for cron/CI). What each check means and how to fix a ❌:

| Check | Why it must be true | Fix when ❌ |
|---|---|---|
| Backup freshness (primary + replica) | RPO = age of the newest backup — a restore recovers *only* what's in the bucket. Also proves the replica copy exists (region-loss case). *(Lesson: staging backups died silently 2026-06-08; a drill later restored 30-day-old data.)* | Re-arm the cron on the DB primary; backfill the replica once: `aws s3 sync s3://<bucket>-backup-xtra s3://<bucket_replica>-backup-xtra` |
| AMI ×3 in the DR region (⚠️ if >8d old) | DR launches from these; stale AMIs mean slow post-restore catch-up | Weekly bake cron (`aws:create_and_copy_ami`) — check it ran; bake manually if needed |
| SSM backup params in the DR region | The baked backup script reads creds/bucket from the *instance's own region's* SSM | `rake "xtrabackup:seed_ssm_params[<env>, <region>]"` |
| Pulumi stack config complete | `pulumi up` aborts on any missing key — discovered at DR time otherwise | `rake "aws:setup_pulumi_config[...]"` (+ `DOMAIN_NAME`/`AWS_KEY_NAME` for a brand-new region) |
| Key pair in the DR region | Pulumi does **not** create key pairs; instances can't launch without one | EC2 → Key Pairs → create/import, matching the stack file's `key_name` |
| Hosted zone for the domain | ACM cert validation + DNS cutover both need it | Create the zone (one-time, global) |
| Local files (`.env`, credentials pair, sibling `IRM-Infra`) | The orchestration runs from this machine | Restore from your secrets store / clone the repo |
| Drill recency (⚠️ >100d) | An untested DR plan is a hypothesis | `TEARDOWN=true rake "aws:dr_drill[<variant>]"` |

The hourly `DbBackupFreshnessJob` (staging + production) alerts on backup
staleness continuously — the scorecard is the on-demand superset for
everything else. Run it quarterly at minimum, and always before a planned
migration.

## 2. Decide

Declare full DR when the primary region cannot serve traffic and won't soon.
You need: a machine with both repos as siblings, the env's AWS keys, Pulumi
login, and ~30–60 minutes. Everything below is safe to run while the old
region is dead — nothing depends on it except the backup bucket (and §4
covers that being dead too).

## 3. Act — the one command (full DR)

```bash
export AWS_ACCESS_KEY_ID=<env keys> AWS_SECRET_ACCESS_KEY=...
RAILS_ENV=production rake "aws:setup_infra[production, AppServer, DB-Redis-ES, ap-south-2, in, production.in, dr_prod_in_<date>]"
```

The 7th arg (branch) makes it fully unattended. What happens, in order:

```mermaid
sequenceDiagram
    autonumber
    actor Op as Operator (one command)
    participant Rake as aws:setup_infra
    participant AWS as DR region
    participant Git as origin
    participant App as New app servers
    participant DB as New DB primary + replica

    Rake->>AWS: pulumi up (VPC, 2 app servers, DB+replica, obs, ALB, cert)
    Rake->>Rake: rewrite credentials (DB_HOST/REPLICA), .env, deploy IPs
    Rake->>Git: commit ONLY those 3 files to <branch>, push
    Rake->>App: cap: clean assets, IRM:setup, deploy <branch> (both servers)
    Rake->>App: nginx maintenance mode (puma/sidekiq stopped)
    App->>DB: restore primary from S3 (baked script; streams live)
    Note over DB: success arms the backup cron — backups resume automatically
    App->>DB: restore replica (disarmed) + reset replication
    Rake->>App: rake db:migrate (replays migrations newer than the backup)
    Rake->>App: nginx: traffic on (no users until DNS flips — §5)
```

Watch for: the restore stream is the long step (minutes–hours scaling with DB
size). Any failure aborts loudly with the step named; infra stays up for
diagnosis; re-running the same command **converges** (Pulumi no-ops existing
resources, commit no-ops if unchanged).

## 4. Database restore — variants

Runs automatically inside §3. Manual forms (on the DB box, via an app server —
DB boxes accept SSH only from app servers):

```bash
# Standard (backup bucket reachable):
sudo /usr/local/bin/db_backup_xtra.sh restore_primary

# Primary region's S3 dead — read the DR-region replica bucket instead:
rake "db:restore_primary_remote[<bucket>-replica-backup-xtra, <dr-region>]"     # from app server
# or on the DB box:
sudo env BUCKET_OVERRIDE=<bucket>-replica-backup-xtra AWS_REGION_OVERRIDE=<dr-region> \
     /usr/local/bin/db_backup_xtra.sh restore_primary
```

Safety built in: the old datadir is **parked** (`<datadir>.bak.<timestamp>`),
never deleted — the script prints the rollback one-liner if MySQL fails to
start, and the cleanup command to run after you've verified the restore.

## 5. DNS cutover — deliberate, manual, last

Only after §6's checks pass. Never automatic (drills have no DNS; going live
is a human decision):

```bash
rake "aws:dns_cutover[production, <dr-region>, in]"
# shows the current record, requires typing "yes", then aliases app.<domain> to the new ALB
```

Traffic shifts as TTLs expire. Verify: `dig app.<domain>` → new ALB.

## 6. Verify — before and after cutover

**Before DNS (the new stack, direct):**
- [ ] App responds via an app server's public IP / the ALB DNS name (cert may
  warn pre-DNS — that's expected)
- [ ] `rake s3:check_backup_freshness` on the new app server — proves the
  restored primary is armed and the first backup landed
- [ ] Replica in sync: `SHOW REPLICA STATUS\G` → `Replica_IO_Running: Yes`,
  `Replica_SQL_Running: Yes`, `Seconds_Behind_Source` falling
- [ ] Migrations current: `rails db:migrate:status | grep -c down` → 0
- [ ] Sidekiq processing (Sidekiq dashboard / `ps`), no crash loops in
  `log/production.log`
- [ ] Data sanity: latest records match RPO expectation (newest backup time —
  check `docs/dr_drills.md`-style: what timestamp did the restore print?)

**After DNS:**
- [ ] Logins + a critical business flow work end-to-end on the real domain
- [ ] ALB target group: both app servers healthy
- [ ] Emails deliver (if SES not yet set up in this region:
  `pulumi config set manage_ses true && pulumi up`, plus sandbox exit if new region)
- [ ] Grafana/Prometheus repointed: `rake aws:generate_prometheus_yml`, `rake grafana:provision`

## 7. Aftermath (first days)

- **Re-establish DR for the NEW primary**: run
  `rake "aws:provision_s3_buckets[<env>]"` (replication now flows the other
  way), re-seed SSM in the *new* backup region, verify the weekly AMI cron
  targets it (`AWS_BACKUP_REGION`)
- Old region, when it returns: `pulumi destroy` its stack (or keep as the new
  standby); rotate anything the incident exposed
- Merge the DR branch (`dr_prod_in_<date>`) — it holds the credential/IP state
  that is now production reality
- Log the event + measured RTO in `docs/dr_drills.md`; schedule a
  retro against this guide and update it where reality diverged

## 8. Known limits (be honest with yourself mid-incident)

- **RPO = time since the newest backup**, not the design's 30 minutes, if the
  freshness alert was firing and ignored. Check the alert channel FIRST.
- **A new environment built WITHOUT a restore never arms backups** — arming is
  a `restore_primary` side effect. Empty-DB setups must arm manually:
  `sudo touch /etc/db_backup_enabled` on the primary.
- Instances from **pre-2026-07 AMIs** lack the baked backup script — the rake
  restore tasks fall back to uploading a generated script automatically; the
  manual on-box command won't exist at `/usr/local/bin` on such instances.
- **SES sandbox** in a never-used region needs an AWS support request (days) —
  transactional email may need a temporary region/relay.
- Pulumi state currently lives in Pulumi Cloud under a personal account —
  migration script ready (`IRM-Infra/migrate_state_to_s3.sh`), pending the
  per-account design decision. Until then, that login is a DR dependency.
