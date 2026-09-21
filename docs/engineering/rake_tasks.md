# Rake Task Reference

This is a complete index of every `lib/tasks/*.rake` file and every
`lib/capistrano/tasks/*.rake` file in this repository, grouped by what they're for.

**Running a rake task**: `bin/rails <task>` or `bundle exec rake <task>`. Tasks that take
positional arguments are invoked with brackets, which almost always need quoting in zsh:

```
bundle exec rake "aws:cost_audit[production.in]"
bin/rails "portfolio_report:seed[157]"
```

**Running a capistrano task**: files under `lib/capistrano/tasks/` are **not** rake tasks in
the normal sense — they're loaded by the `Capfile` and only make sense in the context of a
Capistrano deploy/recovery run against a real host. Invoke them with `cap`, not `rake`:

```
bundle exec cap production_in partial:restore_replica
bundle exec cap production_in website:deploy
```

Many ENV-var-driven tasks below default to a **dry run** and require an explicit
`EXECUTE=1` / `CONFIRM=1` / `CONFIRM_PRODUCTION=true` (the flag name varies per task) to
actually mutate anything. Read the ENV var column carefully before running one of these
against production — the safe default is always "print what would happen."

---

## Database backup & restore

Tasks that create, verify, or restore the xtrabackup-based MySQL backup chain, and
schema/test-DB housekeeping tasks that ride alongside `db:*`.

### `lib/tasks/backup_db.rake` — namespace `db`

The **DR restore path** — SSHes from the app server into the DB box and runs the backup
script baked into the DB AMI (`/usr/local/bin/db_backup_xtra.sh`). Falls back to
generating+uploading the script on pre-bake-AMI instances. Clears stale `/tmp/xb_*` staging
left by a previous failed restore before starting (a known disk-fill failure mode found
during DR drills). Must run **on an app server** — the DB boxes only accept SSH from there.

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `db:restore_primary_remote[bucket, bucket_region]` | Restores the **real primary** via the baked script. Optional args override the source S3 bucket/region (e.g. restoring from the DR-region replica bucket during a true region loss). Re-arms the backup cron on the primary as a side effect. | ⚠️ **Destructive** — overwrites the primary's MySQL datadir. ⚠️ **Production** | `xtrabackup:generate_backup_script` (fallback only) |
| `db:restore_replica_remote[bucket, bucket_region]` | Restores the replica via the baked script, disarms the backup cron on it afterward (replica must never write to the backup chain — one writer per chain), then calls `AwsUtils.reset_replication('2')` to re-point replication. | ⚠️ **Destructive** — overwrites the replica's MySQL datadir. ⚠️ **Production** | `xtrabackup:generate_backup_script` (fallback only) |
| `db:restore_all_remote[bucket, bucket_region]` | Restores **primary AND replica in parallel** (two threads; each restore is independent, only the final `reset_replication` waits for both), then re-points replication. Safe only because traffic is off (nginx maintenance mode). | ⚠️ **Destructive**. ⚠️ **Production** | same as above |
| `db:reset_replication[server_id]` | Points the replica at the primary and restarts the replication stream from the primary's current binlog position. `server_id` defaults to `'2'`. | ⚠️ Production-sensitive (changes live replication topology) | — |
| `db:restore_primary_db` | **Legacy.** Restores the primary via `DbRestoreService` (the backup *verifier* service, not the DR path). Kept for pre-baked-AMI-era instances. | ⚠️ Destructive; prefer `db:restore_primary_remote` | — |
| `db:restore_replica_db` | **Legacy** replica equivalent of the above. | ⚠️ Destructive; prefer `db:restore_replica_remote` | — |

### `lib/tasks/backup_db_xtra.rake` — namespace `xtrabackup`

Generates the DB-host backup/restore shell script from a template, seeds its runtime
config into SSM, and enforces S3 retention on the resulting backup chain.

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `xtrabackup:generate_backup_script` | Reads `lib/tasks/db_backup_xtra.sh`, substitutes `__BUCKET__`/`__AWS_REGION__`/credentials/`__DATABASE_NAME__` placeholders from Rails credentials/`.env`, and writes the result to `tmp/db_backup_xtra_<env>.sh`. Database name is read from **config**, not a live connection — during DR this can run against a virgin MySQL with no database yet. | Contains secrets in the generated file (0755, should be treated as sensitive) | — |
| `xtrabackup:setup_env` | Exports `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_REGION` into `ENV` from Rails credentials. | — | — |
| `xtrabackup:seed_ssm_params[env_name, region]` | Seeds `/irm/<rails_env>/db_backup/*` SSM SecureString parameters (mysql user/pass, bucket, bucket_region, database_name) that the baked backup script reads at boot. SSM is regional — must be run once per region that can host a DB instance, **including the DR region**, so a recovered box finds its config without manual seeding mid-DR. Idempotent (`--overwrite`). | ⚠️ Writes secrets to AWS SSM in the target account/region | `aws:environment` |
| `xtrabackup:cleanup_old_backups[env_name]` | Deletes xtrabackup S3 objects (full + incremental) older than the retention window, **including all versions** (the buckets are versioned, so a plain delete would only add delete markers and keep billing for noncurrent versions). Always keeps every full inside the window **plus** the newest full at-or-before the cutoff (the "straddle" full, base for the oldest in-window incrementals), and never drops below `DB_BACKUP_MIN_KEEP_FULLS`. Cross-checks the bucket's S3 lifecycle rule and warns if it expires backups *sooner* than this task's retention. Cleans both primary and replica buckets unless `SKIP_REPLICA=1`. | **Dry run by default** — set `CONFIRM=1` to actually delete. ⚠️ Destructive when confirmed. ENV: `DB_BACKUP_RETENTION_DAYS` (default 180), `DB_BACKUP_MIN_KEEP_FULLS` (default 60), `VERBOSE=1`, `SKIP_REPLICA=1` | `aws:environment` |

### `lib/tasks/backup_s3.rake` — namespace `s3`

Backup-freshness verification and reporting, run manually or by the hourly/daily cron jobs
in `config/initializers/sidekiq.rb`.

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `s3:check_latest_file[env_name]` | Runs `S3CheckJob` to confirm the latest file in the source bucket made it to the destination bucket. `env_name` lets this run from a laptop against a specific deployed env instead of local `.env`/credentials. | Read-only | `aws:environment` (if `env_name` given) |
| `s3:check_backup_freshness[env_name]` | Runs `DbBackupFreshnessJob` — the manual/DR-verification entry point for the hourly backup-freshness cron. Alerts if primary/replica xtrabackup buckets are stale. Pass `env_name` to check a specific deployment (`production.in`/`production.us`) directly, using that env's own credentials file rather than the booted Rails env's. | Read-only, but exits non-zero on stale backups | — |
| `s3:backup_daily_report[env_name]` | The morning-report counterpart driven by `bin/check_db_backup_freshness`'s `daily` mode: prints what happened in the last 24h (did the nightly full land, chain gaps) per bucket, plus `HISTORY|`/`SUMMARY|` delimited lines the calling script parses, then the pass/fail verdict. | Read-only | — |

### `lib/tasks/load_test_schema.rake` — namespace `db:test`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `db:test:load_schema` | Overrides Rails' built-in `load_schema` task to load `db/schema_test.rb` (a SQLite-portable schema) instead of `db/schema.rb`, falling back to the normal `db:schema:load` if the file doesn't exist. | Test-only | — |
| `db:test:dump_test_schema` | In the test env, dumps the current schema to `db/schema_test.rb`; otherwise delegates to `db:schema:dump`. | — | — |
| `db:test:migrate` | Runs `db:migrate`, then in the test env also runs `db:dump_test_schema` to keep the SQLite-portable dump in sync. | — | `db:migrate`, `db:dump_test_schema` |

### `lib/tasks/clean_schema.rake` — namespace `db`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `db:clean_schema` | Post-migration cleanup of `db/schema.rb`/`db/schema_test.rb`: strips MySQL-only syntax (`_utf8mb4` charset introducers, backtick-quoted identifiers in `check_constraint`, `charset:`/`collation:`/`size:`/`type: :fulltext`/`options:`/`auto_increment:`) so `schema_test.rb` stays loadable by the SQLite test DB. Also rewrites composite-PK partitioned tables (e.g. `account_entries`, whose real MySQL PK is `["id", "reporting_date"]`) back to a plain autoincrementing `id` PK in the test schema, since SQLite can't autoincrement inside a composite primary key. | Rewrites `db/schema.rb` and `db/schema_test.rb` in place | — |

### `lib/tasks/partitions.rake` — namespace `partitions`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `partitions:ensure_account_entries` | Ensures next calendar year's MySQL partition exists on the (very large) `account_entries` table, and emails a PASSED/FAILED/SKIPPED status via `EntityMailer` on every outcome. Intended to run on a schedule well ahead of year-end so the partition is never missing when rows for the new year start arriving. | ⚠️ Sends real email (`.deliver_now`) on every run — not just failures. ⚠️ Touches a very-large-table DDL | — |

---

## Disaster recovery

The DR toolchain answers three different questions at three different times — see the
in-repo design doc `docs/operations/dr/dr_component_recovery.md` for the full picture:

- `aws:dr_readiness` — **before** a disaster: "could we recover if we had to?"
- `dr:assess` — **during** an incident: "which component is broken, and what's the cheapest fix?"
- `dr:verify` / `dr:verify_data_tier` — **after** a recovery: "is the stack actually serving?"

`dr:fix:*` executes one rung of the repair ladder that `dr:assess` names. All of it is
documented in far more depth in `docs/operations/dr/dr_guide.md` and `docs/operations/dr/dr_component_recovery.md` —
this table is a pointer, not a replacement for those runbooks.

### `lib/tasks/dr_assess.rake` — namespace `dr`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `dr:assess[env_name]` | Walks every component of a live environment (`production.in`, `production.us`, or `staging.in`) and recommends the smallest repair. **Read-only, with one exception**: it auto-fixes "trivial rung" issues in place — a dead ES/Redis container or a stopped Sidekiq process on an otherwise healthy host gets restarted. Set `ASSESS_READ_ONLY=true` to suppress even that. Exits non-zero if any component is DOWN. | ⚠️ Auto-restarts services unless `ASSESS_READ_ONLY=true`. ⚠️ Production-capable | — |

### `lib/tasks/dr_verify.rake` — namespace `dr`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `dr:verify` | Post-recovery smoke test proving a recovered (or freshly deployed) app server + its DB box are actually **serving** — checks nginx, puma, sidekiq, MySQL, Redis, ES, S3, backup-cron arming, and replication. Runs on an app server; `aws:setup_infra` calls it as its final step so a full DR run only "succeeds" if the stack verifies. Starts `prometheus_exporter` if it's down (rather than only reporting it) since a downed exporter otherwise jams the rest of the scorecard's output with connection errors. Prints a ✅/⚠️/❌ scorecard and exits non-zero on any ❌. | ⚠️ Starts a downed prometheus_exporter as a side effect | — |

### `lib/tasks/dr_verify_data_tier.rake` — namespace `dr`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `dr:verify_data_tier` | Verifies Redis, Sidekiq and Elasticsearch **from inside the app process**, using the app's own `REDIS_URL`/`ELASTIC_SEARCH_URL`. Exists because `dr:verify`'s "redis_check" only exercises `Rails.cache`, which is backed by `:solid_cache_store` (MySQL) — so it can pass green while Sidekiq/ActionCable point at a dead Redis after a repair moves Redis to a new address. Must run on an app server. Exits non-zero on any ❌. | Read-only | — |

### `lib/tasks/dr_fix.rake` — namespace `dr:fix`

Repairs exactly ONE component and touches nothing else. Pulumi steps are print-only (a
human runs the printed command); Capistrano steps are host-filtered (`HOSTS=<ip>`) so a
healthy neighbor server is never restarted.

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `dr:fix:app_server[env_name, host]` | Repairs ONE app server: restarts its services in place, or rebuilds the box from AMI (isolated to that instance's exact Pulumi URN + its ALB target-group attachment — a preview containing any other resource change aborts). | ⚠️ Production-capable, but scoped to one host | `dr:assess` (run first) |
| `dr:fix:prometheus_config[env_name]` | Regenerates the Prometheus scrape config from live instance IPs and pushes it to the observability box. | — | — |
| `dr:fix:observability[env_name]` | Repairs the observability box: restarts Grafana/Prometheus in place, or rebuilds it from AMI. | ⚠️ Production-capable | — |
| `dr:fix:nat[env_name]` | Diagnoses and repairs the NAT gateway that private-subnet DB boxes depend on for outbound internet. | ⚠️ Production-capable | — |

### `lib/tasks/dr_fix_db.rake` — namespace `dr:fix`

Database-tier repair — the most consequential set of tasks in the DR toolchain, because
choosing between "promote the replica" and "rebuild from S3" decides how much data is lost.

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `dr:fix:db_replica[env_name]` | Repairs the DB replica: restart it, reset replication, or rebuild the box and restore it from the backup chain — while the primary stays untouched. | ⚠️ **Destructive** on the replica box. ⚠️ Production | — |
| `dr:fix:promote_replica[env_name]` | Promotes the healthy replica to primary when the primary is gone. RPO ≈ 0 — the preferred path whenever the replica is usable. Guarded by `CONFIRM_OUTAGE=true` before proceeding, since this redirects every app server's DB connection. | ⚠️ **Destructive/topology-changing**. ⚠️ Production. Requires `CONFIRM_OUTAGE=true` | — |
| `dr:fix:db_primary[env_name]` | Rebuilds the DB primary from AMI and restores it (and the replica) from the S3 backup chain — used only when the replica is also unusable. RPO ≈ 1h (whatever's newest in the backup chain). Guarded by `CONFIRM_DATA_LOSS=true` since a restore **DELETES the target box's MySQL data directory** and discards anything written since the last incremental. | ⚠️ **Highly destructive** — deletes the primary's data directory. ⚠️ Production. Requires `CONFIRM_DATA_LOSS=true` | — |

Every task in this file also guards against shipping unreleased work mid-incident: it
compares the locally checked-out `git rev-parse HEAD` against the revision actually
deployed on the target host (read over SSH) and refuses to proceed on a mismatch.

### `lib/capistrano/tasks/dr_partial.rake` — namespace `partial`

Thin Capistrano wrappers over the `db:restore_primary_remote`/`restore_replica_remote` rake
tasks above, so a single-box restore is a one-line `cap` invocation from a laptop instead of
SSHing to an app server and running rake by hand mid-incident. Adds no recovery logic of its
own.

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `partial:restore_primary` | Restores ONLY the DB primary from the backup chain (replica untouched). Accepts `BUCKET`/`BUCKET_REGION` env vars to override the source bucket. | ⚠️ **Destructive** — deletes the existing MySQL data directory on the target box. ⚠️ Production | wraps `db:restore_primary_remote` |
| `partial:restore_replica` | Restores ONLY the DB replica from the backup chain, then re-points replication at the primary. | ⚠️ **Destructive**. ⚠️ Production | wraps `db:restore_replica_remote` |
| `partial:verify_data_tier` | Runs `dr:verify_data_tier` on the target box via cap. | Read-only | wraps `dr:verify_data_tier` |
| `partial:reset_replication` | Re-points the replica at the primary and restarts the replication stream — no restore involved. | ⚠️ Changes live replication topology | wraps `db:reset_replication` |

---

## AWS infrastructure & cost management

Provisioning, hardening, and cost hygiene across the two AWS accounts (staging:
`174852986003`, production: `825199636520`). Almost every mutating task here defaults to a
**dry run** and requires an explicit `EXECUTE=1` (or task-specific confirm flag).

### `lib/tasks/aws.rake` — namespace `aws` (the largest file — core DR/infra entry points)

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `aws:grow_disk` | Runs `growpart`/`resize2fs` on the local box's root volume to pick up an EBS size increase. Meant to be run **on the instance itself**. | ⚠️ Modifies local disk partitioning (in-place, non-destructive if used correctly) | — |
| `aws:setup_infra[stack, web_server_name, db_server_name, region, env_variant, env_name, branch]` | The full DR entry point: pulumi config + `pulumi up` + rewrite credentials/env/deploy IPs + `cap deploy` + DB restore, ending with `dr:verify`. Non-interactive when a `branch` (7th arg) is given — auto-commits rewritten config to that branch, pushes, and runs the entire recovery unattended. Omitting `branch` falls back to the legacy interactive flow (manual DB restore + manual commit + a prompt for the branch name). | ⚠️⚠️ **Full-region rebuild** — the most impactful task in the repo. ⚠️ Production-capable | `aws:setup_pulumi_config`, ends with `dr:verify` |
| `aws:setup_pulumi_config[stack, web_server_name, db_server_name, region, env_variant, env_name]` | Refreshes Pulumi stack config (AMIs, region, domain, key name) without deploying. | Config-only, no deploy | — |
| `aws:dr_readiness[stack, env_variant, region, env_name]` | Read-only DR-readiness scorecard: backups, AMIs, SSM config, stack config, key pair, hosted zone, drill recency. Answers "could we recover right now?" | Read-only | — |
| `aws:dr_drill[env_variant, region, env_name, stack]` | Runs an unattended DR drill and reports RTO. Staging by default; **refuses to run against `production` unless `CONFIRM_PRODUCTION=true`** is also set, with `TEARDOWN=true` as a documented option to tear the drilled stack back down after. | ⚠️ Spins up (and can tear down) real infrastructure. ⚠️ Production requires `CONFIRM_PRODUCTION=true` | `aws:setup_infra` |
| `aws:dns_cutover[stack, region, env_variant, record_name]` | **MANUAL** — points the app DNS A-record (Route53 alias) at a recovered stack's ALB. Prints the current record and the proposed change, then requires the operator to type `yes` at a terminal prompt before applying. | ⚠️ **Destructive/user-facing** — repoints live production DNS. Interactive confirmation required, no non-interactive override | — |
| `aws:mailchimp_dns[env_name, mode, domain]` | Adds Mailchimp DKIM (k2/k3 CNAMEs) + DMARC TXT records to the `caphive.com` Route53 zone. `mode` is `plan` (default, read-only) or `apply` (UPSERTs the records). Run once per AWS account. | `plan` is read-only; `apply` is ⚠️ production DNS-mutating | — |
| `aws:dr_verify_edge[stack, region]` | Curls the recovered stack's ALB **directly** (bypassing DNS) — meant to run before `aws:dns_cutover` to confirm the target is actually healthy before flipping DNS at it. | Read-only | — |
| `aws:get_latest_ami[name_tag, region, env_name]` | Looks up the most recent AMI matching a name tag in a region. | Read-only | `aws:environment` |
| `aws:copy_ami[ami_id, destination_region, env_name]` | Copies an AMI to a different region. | ⚠️ Creates AWS resources (billable) | `aws:environment` |
| `aws:create_and_copy_ami[instance_name, destination_region, env_name]` | Creates an AMI from a named instance and copies it to another region — the core of the weekly AMI bake. | ⚠️ Creates AWS resources | `aws:environment` |
| `aws:create_all_amis[env_name]` | Creates+copies AMIs for every weekly-baked instance type. `INSTANCES=comma,separated` overrides the default set. | ⚠️ Creates AWS resources across regions | `aws:environment` |
| `aws:delete_old_amis[name_tag, region, env_name]` | Deletes old AMIs matching a name pattern, keeping the newest per the `AwsUtils::AMI_KEEP_DEFAULT` retention. | ⚠️ **Destructive** — deregisters AMIs | `aws:environment` |
| `aws:create_ami[instance_name, env_name]` | Creates an AMI from a named EC2 instance. | ⚠️ Creates AWS resources | `aws:environment` |
| `aws:environment[env_name]` | Internal helper task (not user-facing): loads `.env.<env_name>` + the matching `config/credentials/<env_name>.yml.enc` into `Aws.config` and `ENV`. Nearly every other `aws:*`/`xtrabackup:*` task re-enables and invokes this to target a specific account/region from a laptop. | — | — |
| `aws:provision_s3_buckets[env_name]` | Provisions and cross-region-replicates the S3 bucket pair (primary + DR-region replica) for an environment, including lifecycle rules. `ensure_lifecycle!` **never overwrites** an existing lifecycle config on a bucket — a deliberate "don't clobber" design that means a bucket provisioned under an old retention default keeps that default until manually fixed. | ⚠️ Creates/modifies AWS S3 infrastructure | `aws:environment` |
| `aws:generate_prometheus_yml[env_name]` | Generates `prometheus.yml` with live EC2 instance IPs for the observability box's scrape config. | Read-only against AWS; writes local file | `aws:environment` |
| `aws:cleanup_unused_security_groups[env_name]` | Finds (and optionally deletes) unused security groups. | ⚠️ Can delete AWS resources (gated internally) | `aws:environment` |
| `aws:cleanup_unused_vpcs_and_subnets[env_name]` | Finds (and optionally deletes) unused VPCs/subnets. | ⚠️ Can delete AWS resources | `aws:environment` |
| `aws:manage_ssh[action, env_name, force]` | Manages SSH (port 22) exposure across security groups. `action` is `list` (find groups with 0.0.0.0/0:22), `suspend` (move SSH to port 22222), or `resume`. Prompts for `y/N` confirmation unless `force=true`. | ⚠️ **Production-sensitive** — can lock out SSH access if misused; `force=true` skips confirmation | `aws:environment` |

### `lib/tasks/aws_ebs.rake` — namespace `aws`

EBS encryption rollout + AMI/snapshot retention hygiene, added after a 2026-09-01 audit
found production.in fully encrypted but staging and production.us running entirely
unencrypted volumes/snapshots/AMIs. Every mutating call routes through a shared `.act`
helper so dry-run mode genuinely cannot mutate anything.

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `aws:ebs_status[env_name]` | Read-only per-region EBS encryption status audit. | Read-only. ENV: `REGIONS` | — |
| `aws:ebs_default_encryption[env_name]` | Enables encryption-by-default per region/account (affects only newly created volumes and snapshot/AMI copies — zero impact on anything running). | **Dry run by default.** ENV: `EXECUTE`, `REGIONS`, `KMS_KEY_ID` | — |
| `aws:ebs_cleanup[env_name]` | Expires old AMIs (and their backing snapshots) + deletes orphaned snapshots not referenced by any registered AMI or tagged `Retain=true`. | **Dry run by default.** ⚠️ Destructive when executed. ENV: `EXECUTE`, `KEEP`, `DAYS`, `REGIONS` | — |
| `aws:ebs_purge_superseded[env_name]` | Deletes unencrypted AMIs/snapshots once a newer encrypted equivalent exists. | **Dry run by default.** ⚠️ Destructive when executed. ENV: `EXECUTE`, `REGIONS` | — |
| `aws:ebs_encrypt_plan[env_name]` | Read-only: lists which instances the encryption rollout would need to restart. | Read-only. ENV: `REGIONS` | — |
| `aws:ebs_encrypt_instance[instance_name, env_name]` | Encrypts an instance's EBS volumes via stop → snapshot → encrypted copy → new volume → swap → start. **Stops the instance.** Refuses to touch a `production`-named env unless `ALLOW_STOP=1` is also set. | ⚠️ **Destructive/disruptive** — stops the running instance. ENV: `EXECUTE`, `ALLOW_STOP`, `KMS_KEY_ID`, `INSTANCE_ID` | — |
| `aws:ebs_delete_replaced[env_name]` | Deletes the old unencrypted volumes left detached (tagged `DeleteAfterVerify=true`) by `ebs_encrypt_instance`, but only after confirming the source instance is running again with every attached volume encrypted. | **Dry run by default.** ⚠️ Destructive when executed. ENV: `EXECUTE`, `REGIONS`, `ALLOW_STOPPED` | — |

### `lib/tasks/aws_tls_policy.rake` — namespace `aws`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `aws:tls_policy[env_name]` | Pins ALB HTTPS listener TLS policy to TLS 1.2/1.3 (`ELBSecurityPolicy-TLS13-1-2-2021-06` by default), replacing AWS's default `ELBSecurityPolicy-2016-08` (which negotiates down to TLS 1.0). `modify_listener` on `ssl_policy` is in-place and non-disruptive to existing connections; reversible by re-running with `POLICY=<old value>`. | **Dry run by default.** ENV: `EXECUTE`, `REGIONS`, `POLICY`. ⚠️ Production-capable | — |

### `lib/tasks/aws_cost_audit.rake` — namespace `aws`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `aws:cost_audit[env_name]` | **Strictly read-only** cost & optimization audit — only `Describe*`/`Get*`/`List*` calls, no remediation is ever executed (only printed). Produces: Cost Explorer totals/MoM deltas/spend-by-region, active EC2 reservation inventory (flagging unused/soon-expiring), a findings list with estimated $/month + remediation commands, and (unless `NO_LLM=1`) an LLM-generated prioritized plan via Gemini/RubyLLM. Writes a self-contained HTML report to `docs/operations/costs/aws_cost_audit_<env>_<date>.html` in addition to stdout markdown. | Read-only. ENV: `MONTHS`, `REGIONS`, `NO_LLM`, `LLM_MODEL`, `OUTPUT`. Cost Explorer calls cost $0.01 each (~4/run) | `aws:environment` |

### `lib/tasks/aws_cost_cleanup.rake` — namespace `aws`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `aws:cost_cleanup[env_name]` | **Staging-only** remediation of `aws:cost_audit` findings: deletes non-AMI-backed snapshots older than `SNAPSHOT_DAYS` (180d default), releases unassociated Elastic IPs, adds a conservative S3 lifecycle to buckets lacking one, optionally deletes near-zero-traffic NAT gateways (`DELETE_NAT=1`), and optionally terminates specific stopped instances by id (`TERMINATE_IDS=i-abc,i-def`, each gets an AMI backup first). Refuses to run unless `env_name` starts with `staging`, the STS account matches the whitelisted staging account, and `Rails.env` is not production — **three separate guards**, checked before any AWS call. | **Dry run by default.** ENV: `EXECUTE`, `DELETE_NAT`, `TERMINATE_IDS`, `SNAPSHOT_DAYS`. ⚠️ Destructive when executed | — |

### `lib/tasks/aws_cost_cleanup_prod.rake` — namespace `aws`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `aws:cost_cleanup_prod[env_name]` | **Production-scoped, safe-actions-only** cost cleanup: non-AMI-backed snapshots older than `SNAPSHOT_DAYS`, CloudTrail/VPC-flow-log bucket lifecycle (180d expiry), MPU-abort-only lifecycle on other buckets (never touches document version expiry, and skips `*-backup-xtra` buckets entirely — those belong to the xtrabackup retention task), and CloudWatch log-group retention set to 90d where currently `Never`. Deliberately excludes NAT gateways, stopped `DbCheckInstance` boxes, instance termination, and EIPs. Same triple-guard pattern as `aws:cost_cleanup` but for production. | **Dry run by default.** ⚠️ **Production**. ENV: `EXECUTE`, `SNAPSHOT_DAYS` | — |

### `lib/tasks/aws_cleanup.rake` — namespace `aws`

Older, simpler cleanup tasks predating `aws_cost_cleanup*.rake` — no account/env guard rails,
so use with more care.

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `aws:cleanup_snapshots[env_name]` | Deletes EBS snapshots older than `RETENTION_DAYS` (default 30). | `DRY_RUN=true` to list only. ⚠️ Destructive otherwise, **no account guard** | `aws:environment` |
| `aws:cleanup_elastic_ips[env_name]` | Releases unassociated Elastic IPs. | `DRY_RUN=true` to list only. ⚠️ Destructive otherwise | `aws:environment` |
| `aws:cleanup_unattached_volumes[env_name]` | Deletes unattached EBS volumes. | `DRY_RUN=true` to list only. ⚠️ Destructive otherwise | `aws:environment` |
| `aws:cleanup_stopped_instances[env_name]` | **Terminates** stopped EC2 instances. | `DRY_RUN=true` to list only. ⚠️⚠️ Destructive/irreversible otherwise | `aws:environment` |
| `aws:list_nat_gateways[env_name]` | Lists NAT gateways and flags redundancy. | Read-only | `aws:environment` |
| `aws:setup_s3_glacier[env_name]` | Sets up S3 Glacier lifecycle rules for backup buckets. | Modifies bucket lifecycle | `aws:environment` |
| `aws:run_all_cleanup[env_name]` | Runs all of the above "safe" cleanups (snapshots, EIPs, unattached volumes, NAT advice) in sequence. | Inherits `DRY_RUN` behavior of each sub-task | the tasks above |

### `lib/tasks/nat_gateway.rake` — namespace `aws:nat`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `aws:nat:status[env_name]` | Shows current NAT Gateway + private-route-table status. | Read-only | `aws:environment` |
| `aws:nat:delete[env_name]` | Deletes the NAT Gateway and releases its EIP. **Instances routed through it lose outbound internet** (including OS package updates) until a new one is created. | ⚠️ **Destructive/disruptive** | `aws:environment` |
| `aws:nat:create[env_name]` | Creates a new NAT Gateway in the public subnet and repoints the private route table at it. | ⚠️ Creates billable AWS resources | `aws:environment` |

### `lib/tasks/nginx.rake` — namespace `nginx`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `nginx:switch[nginx_profile]` | Switches the live nginx config between `maintenance` and `IRM_<Rails.env>` by re-symlinking `sites-enabled`, then reloads nginx. Meant to run **on the app server itself**. | ⚠️ **Production-sensitive** — puts the site into/out of maintenance mode | — |

### `lib/tasks/pulumi_state.rake` — namespace `aws`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `aws:provision_pulumi_state_bucket[env_name]` | Provisions the Pulumi state S3 bucket pair (primary + cross-region-replicated DR bucket) for one account×geography. Scope is production (both geographies) plus `staging.in` (used to rehearse DR — a drill against a personal Pulumi Cloud login wouldn't rehearse the real procedure). Idempotent — safe to re-run to repair drift. Full design lives in `IRM-Infra/PULUMI_STATE.md`. | ⚠️ Creates AWS infrastructure (buckets, replication rules) | — |

### `lib/tasks/packer.rake` — namespace `packer`

Builds the AMI templates (`appserver`, `db_redis_es`, `observability`) that back the fleet.

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `packer:check_env[env, env_variant]` | Validates syntax of all Packer templates for a given env/variant. | Read-only | — |
| `packer:check` | Same, defaulting to `dev`/`us`. | Read-only | — |
| `packer:init_env[env, env_variant]` | Runs `packer init` for a given env/variant. | Downloads Packer plugins | — |
| `packer:init` | Same, defaulting to `dev`/`us`. | — | — |
| `packer:build_env[env, env_variant, template_type]` | **Bakes** an AMI (`app`, `db`, `obs`, or `all`) for a given env/variant. `PACKER_AWS_REGION` can override the target region (e.g. baking directly into the DR region). | ⚠️ Creates AWS resources (instances, AMIs) — billable, can take a long time | — |
| `packer:build` | Same, defaulting to `dev`/`us`/`all`. | ⚠️ Creates AWS resources | — |
| `packer:teardown_build_network[region]` | Deletes the transient `packer-build-<region>` VPC/network used during bakes. | ⚠️ Deletes AWS networking resources | — |

---

## Monitoring / observability

Grafana provisioning, health checks, and infra/cost reporting.

### `lib/tasks/grafana_provision.rake` — namespace `grafana`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `grafana:provision` | Applies **all** Grafana provisioning: contact points, alert rules, dashboard patches. | Modifies live Grafana config | `grafana:provision:contact_points`, `:alert_rules`, `:dashboards` |
| `grafana:provision:contact_points` | Applies contact points + notification policy only. | Modifies live Grafana config | — |
| `grafana:provision:alert_rules` | Applies alert rules only. **Idempotent by deletion** — deletes and recreates every rule in the managed folder each run. | ⚠️ Deletes+recreates existing alert rules | — |
| `grafana:provision:dashboards` | Patches existing dashboards (fixes queries, adds panels/variables) and saves the resulting JSON to `config/grafana/dashboards/`. | Modifies live dashboards | — |
| `grafana:provision:save` | Saves the *current live* dashboard JSON to `config/grafana/dashboards/` **without** patching — for taking an initial backup before making changes. | Read-only against Grafana; writes local files | — |
| `grafana:provision:overview_dashboard` | Creates/updates the "CapHive Overview" dashboard — current-state stat panels (P99 latency, Puma thread saturation, Sidekiq queue depth/age, cache miss rate, InnoDB deadlocks, aborted connections, iowait, network throughput, etc.) for every monitored system. | Modifies live Grafana dashboards | — |
| `grafana:provision:viewer_users` | Creates/updates read-only viewer users defined in `grafana_provision.yml`. | Requires `GRAFANA_VIEWER_PASSWORD`; creates Grafana user accounts | — |

### `lib/tasks/grafana_health.rake` — namespace `grafana`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `grafana:health_check[env_name]` | Queries the live "CapHive Overview" dashboard's panels and reports any red/yellow threshold breaches. | Read-only | — |

### `lib/capistrano/tasks/grafana_annotations.rake` — namespace `grafana`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `grafana:annotate` | Posts a deploy annotation to Grafana (a vertical marker on every dashboard at deploy time) using the exact SHA Capistrano deployed. **Silently skipped** if `GRAFANA_PASS` isn't set — never blocks a deploy over a missing annotation. Non-fatal if Grafana is unreachable. | Non-destructive; fire-and-forget. ENV: `GRAFANA_URL`, `GRAFANA_USER`, `GRAFANA_PASS` | Runs automatically as part of every Capistrano deploy |

### `lib/tasks/infra_report.rake` — namespace `infra`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `infra:report` | Generates an HTML resource-usage report covering CPU, RAM, disk, inode usage, 5xx/4xx rates, response times, Sidekiq queue depth/age, Puma worker RSS, DB RAM/connection-pool saturation, slow queries, replication lag, InnoDB buffer-pool miss rate, deadlocks, and aborted connections — each metric with an explanatory blurb. | Read-only against Grafana. ENV: `GRAFANA_URL`, `GRAFANA_PASS`, `WINDOW` (default 7d) | — |

### `lib/tasks/deploy_notifications.rake` — namespace `deploy`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `deploy:notify_before` | Enqueues `DeploymentNotificationWorker.perform_async("before")` to warn users the system is about to go down for a deploy. No-ops with a warning log if the worker class isn't defined. | ⚠️ **Sends real user-facing notifications** | Run as part of the deploy pipeline |
| `deploy:notify_after` | Enqueues the same worker with `perform_in(1.minute, "after")` to tell users the system is back. | ⚠️ **Sends real user-facing notifications** | Run as part of the deploy pipeline |

---

## Demo / seed data generation

Idempotent, entity-scoped seed tasks used to populate a demo/staging tenant with realistic
data for a feature demo, QA, or sales walkthrough. Most take `ENTITY_ID` as an argument and
are safe to re-run (found-or-created by name/key). A few (`demo_data.rake`,
`deal_demo_activity.rake`) generate large volumes of **fake/fabricated** records via Faker —
treat those as strictly non-production tools.

### `lib/tasks/demo_data.rake` — namespace `irm`

Bulk fake-data generator using `Faker`/`FactoryBot`. Not entity-scoped — creates its own
entities.

| Task | Description | Flags |
|---|---|---|
| `irm:generateFakeEntities` | Creates fake Company/Investment Advisor/Investment Fund entities (Urban Company, Demo Company, Wakefit, Ambit, Citi, IAN, Atrium Angels, etc.) each with a couple of users. | ⚠️ Dev/demo-only, writes fabricated rows |
| `irm:generateFakeBlankEntities` | Creates fake entities with no further data. | ⚠️ Dev/demo-only |
| `irm:generateFakeDocuments` | Generates fake `Document` rows. | ⚠️ Dev/demo-only |
| `irm:generateFakeInvestors` | Generates fake `Investor` rows. | ⚠️ Dev/demo-only |
| `irm:generateFakeInvestments` | Generates fake investments. | ⚠️ Dev/demo-only |
| `irm:generateFakeFundInvestments` | Generates fake fund-level investments. | ⚠️ Dev/demo-only |
| `irm:generateFakeHoldings` | Generates fake holdings. | ⚠️ Dev/demo-only |
| `irm:generateFakeNotes` | Generates fake `Note` rows. | ⚠️ Dev/demo-only |
| `irm:generateFakeValuations` | Generates fake valuations. | ⚠️ Dev/demo-only |
| `irm:generateFakeDeals` | Generates fake `Deal` rows. | ⚠️ Dev/demo-only |
| `irm:generateFakeSales` | Generates fake sales. | ⚠️ Dev/demo-only |
| `irm:generateFakeOffers` | Generates fake offers. | ⚠️ Dev/demo-only |
| `irm:generateFakeLoadTestUsers` | Generates fake users specifically for load testing. | ⚠️ Dev/demo-only, bulk-writes users |
| `irm:generateFakePortfolios` | Generates fake portfolios. | ⚠️ Dev/demo-only |
| `irm:generateFakeFunds` | Generates fake funds. | ⚠️ Dev/demo-only |
| `irm:generateAll` | Runs `generateFakeEntities` → `Investors` → `Documents` → `Notes` → `Sales` → `Offers` → `Funds` → `Portfolios` in sequence. | ⚠️ Dev/demo-only, large combined write | depends on the seven tasks it chains |
| `irm:seed_demo_deals[entity_id]` | Seeds two fully-populated demo deals for `DealManagementAgent` testing. | ⚠️ Dev/demo-only |

### `lib/tasks/deal_demo_activity.rake` — namespace `deal`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `deal:demo_activity[deal_id, task_count, note_count]` | Generates fake `Task`/`Note` records for an existing deal and its `DealInvestor`s, spread across the deal's kanban board columns with a mix of overdue/upcoming/undated dates, so the board and notes timeline can be exercised without hand-creating records. Every generated row is tagged `demo-seed` for easy identification and cleanup (`Task.where("tags LIKE '%demo-seed%'")`). | **Refuses to run outside `Rails.env.development?`** — hard-coded dev-only guard | — |

### `lib/tasks/workflow_seeds.rake` — namespace `workflow_seeds`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `workflow_seeds:seed[entity_id]` | Seeds meaningful `WorkflowTemplate`s for `Folder`, `InvestorKyc`, `CapitalCall`, and `Approval` workflowable types on an entity. Idempotent by template name+entity; skips any that already exist. | Writes demo workflow templates | run `workflow_seeds:teardown` first to replace |
| `workflow_seeds:teardown[entity_id]` | Removes all seeded workflow templates for an entity, archiving any active instances first. | ⚠️ Destroys templates/instances | — |

### `lib/tasks/investor_workflow_seeds.rake` — namespace `investor_workflow_seeds`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `investor_workflow_seeds:seed[entity_id]` | Seeds two workflow scenarios: (1) "Investor Onboarding" — auto-assigned + auto-launched on new non-portfolio-company investors; (2) "Portfolio Company KPI Report Review" — auto-assigned but launched only on KPI import (see `KpiReport#launch_portfolio_company_workflow`). Also creates a demo Portfolio Company investor + a demo `KpiReport` with sample KPIs and directly triggers the launch, exercising the same production code path `ImportKpiWorkbookJob` uses. Idempotent. | Writes demo workflow templates/rules/investor/report | — |
| `investor_workflow_seeds:teardown[entity_id]` | Removes everything `seed` created for an entity — demo investor/report/KPI rows first (which cascades to their workflow instances), then archives remaining active instances and destroys each template. Reports (rather than raises) if a template can't be destroyed because a `WorkflowInstance` FK still references it. | ⚠️ Destroys demo investor + associated data | — |

### `lib/tasks/workflow_demo.rake` — namespace `workflow_demo`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `workflow_demo:setup[entity_id, launch]` | Seeds a sample "Two-Stage LP Review" workflow template plus a "Q3 2026 LP Data Room" folder with 4 sample documents. Pass `launch` as the second arg to also launch the workflow (notifies step-1 actors — a real notification). Idempotent: tears down and recreates the demo template/folder by name on every run. | ⚠️ `launch` sends real notifications to step actors | — |
| `workflow_demo:teardown[entity_id]` | Tears down the demo workflow template and folder. Idempotent. | ⚠️ Destroys demo template/folder | — |

### `lib/tasks/lp_crm_custom_fields.rake` — namespace `lp_crm`

| Task | Description | Flags |
|---|---|---|
| `lp_crm:seed_custom_fields[entity_id]` | Seeds the LP CRM custom fields for an entity: `InvestorAccess` contact/touch-point fields (designation, POC role, intro, LinkedIn, primary-contact flag) and `Investor`-level fields (engagement status, relationship owner). The whole CRM is custom-field driven, so this is the only "setup" a tenant needs. Idempotent — only creates fields that don't already exist by normalized name; never clobbers tenant edits to existing fields. | Writes custom-field definitions |

### `lib/tasks/validation_rules.rake` — namespace `rules`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `rules:seed_defaults[entity_id]` | Seeds/updates default `ValidationRule`s. With no arg, upserts all global defaults across every entity; with an entity id, that entity customizes via overrides. Idempotent — creates missing rules, updates `condition_tree`/`params`/`description`/`message_template` on existing ones, but **never touches the `enabled` flag or any override**. Safe to re-run on every deploy. | Writes/updates global validation rule config | — |
| `rules:enable_for_entity[entity_id]` | Creates/updates `ValidationRuleOverride`s so all global default rules are **enabled** for one entity. | Requires `rules:seed_defaults` to have run first | `rules:seed_defaults` |
| `rules:disable_for_entity[entity_id]` | Same, but **disables** all global default rules for one entity. | — | — |
| `rules:seed_entity_overrides[entity_id]` | Seeds example `ValidationRuleOverride`s for a specific entity (defaults to entity 157). Idempotent. | — | — |

### `lib/tasks/fund_ratio_run_templates.rake` — namespace `fund_ratios`

| Task | Description | Flags |
|---|---|---|
| `fund_ratios:seed_templates[entity_id]` | Seeds a standard set of `FundRatioRunTemplate`s into an entity, modelled on entity 157's ("Demo Fund") templates. Fund/portfolio-company names are resolved at runtime against the target entity; anything not found is skipped with a warning rather than raising. `ANCHOR=Fund A` can be passed to override the reference fund. Fully idempotent. | — |

### `lib/tasks/dashboard_widgets.rake` — namespace `irm:dashboard_widgets`

| Task | Description | Flags |
|---|---|---|
| `irm:dashboard_widgets:setup_lp[entity_id]` | Configures the default LP Landing Page widget set (Funds, LP Menus, LP Header, Metric Cards, Action Items, Latest Documents, Performance Chart, Ratios charts for TVPI/DPI/MOIC and IRR, Investment Opportunities) — position-ordered, skipping any widget_name+tags combo that already exists. | Writes `DashboardWidget` rows |
| `irm:dashboard_widgets:setup_fm[entity_id]` | Same for the FM (fund-manager-facing) Landing Page widget set. | Writes `DashboardWidget` rows |
| `irm:dashboard_widgets:setup_all[entity_id]` | Runs both `setup_lp` and `setup_fm`. | — |

### `lib/tasks/support_agents.rake` — namespace `support_agents`

| Task | Description | Flags |
|---|---|---|
| `support_agents:setup[entity_id]` | Idempotently sets up all `SupportAgent` `FormType`s, custom fields, and agent records for an entity via `SupportAgentsSetupService`. Safe to re-run after adding new fields/agents. | — |
| `support_agents:clone[target_entity_id, source_entity_id]` | Clones all `SupportAgent`s from a fully-configured source entity (default source: 157) to a target entity — mirrors enabled agent bitflags and copies configuration. Run `setup` on the source first. | Writes agent config to the target entity |

### `lib/tasks/portfolio_scoring_seed.rake` — namespace `portfolio_scoring`

| Task | Description | Flags |
|---|---|---|
| `portfolio_scoring:seed[entity_id]` | Fabricates `SupportAgentReport` rows in the exact shape `PortfolioScoringAgent#store_score` writes, so the Portfolio Scoring Dashboard can be demoed without running the real agent or spending on LLM calls. Defaults to entity 157. Delegates to `db/seeds/portfolio_scoring_reports.rb`. | Writes fabricated report rows, tagged `"seeded": true` |
| `portfolio_scoring:clear[entity_id]` | Removes only the seeded scoring reports for an entity (matched by the `seeded` key in `json_fields`), leaving real agent output untouched. | ⚠️ `destroy_all` on matched rows |

### `lib/tasks/presentation_analyst_seed.rake` — namespace `presentation_analyst`

| Task | Description | Flags |
|---|---|---|
| `presentation_analyst:seed[entity_id]` | Same pattern as `portfolio_scoring:seed`, but for `PresentationAnalystAgent#store_results` — fabricates demo reports for the Presentation Analyst Dashboard. Defaults to entity 157. | Writes fabricated report rows |
| `presentation_analyst:clear[entity_id]` | Removes only the seeded rows for an entity. | ⚠️ `destroy_all` on matched rows |

### `lib/tasks/report_builder_demo_seed.rake` — namespace `report_builder_demo`

| Task | Description | Flags |
|---|---|---|
| `report_builder_demo:seed[entity_id]` | Loads 5 complex Report Builder reports into an entity to demo the feature: multi-join zero-fill, every aggregate type, pivot tables, computed formula columns, Ransack filters on root and joined scopes, and both SQL-level and computed sorting. Idempotent — re-running **replaces** each report's columns/template, so you can tweak this file and re-seed without piling up duplicates. Reports are marked "shared" so any entity user can see them. | Overwrites existing seeded report definitions on re-run |

### `lib/tasks/portfolio_report_seed.rake` — namespace `portfolio_report`

| Task | Description | Flags |
|---|---|---|
| `portfolio_report:generate_brand_template` | Generates a brand-template PPTX (Emerald theme) to `tmp/brand_template_emerald.pptx`. | Writes a local file |
| `portfolio_report:generate_word_template` | Generates a placeholder Word template (.docx) to `tmp/word_placeholder_template.docx`. | Writes a local file |
| `portfolio_report:generate_ppt_template` | Generates a placeholder PPT template to `public/sample_uploads/portfolio_report_templates/`. | Writes into `public/` |
| `portfolio_report:seed[entity_id]` | Seeds a full portfolio company ("Report Gen Test Co") with everything needed to test Portfolio Report Generation v2: `InvestorKpiMapping`s, 6 months of monthly `KpiReport`/`Kpi` actuals, a `PortfolioReport` with 4 sections, a `PortfolioReportTemplate` with a generated style-reference `.docx` (hand-built OOXML with named styles: Title/Heading1/Heading2/Body Text/List Bullet/Caption/TableGrid, brand colors), 3 context notes, and 2 fake `PortfolioReportExtract` rows. Idempotent — safe to re-run. | Writes a substantial amount of demo data |

### `lib/tasks/agent_charts.rake` — namespace `agent_charts`

| Task | Description | Flags |
|---|---|---|
| `agent_charts:seed` | Seeds standard `AgentChart` definitions for an entity given via `ENTITY_ID=157` env var (not a bracket arg). Idempotent — skips any chart whose title already exists for the entity. | — |

### `lib/tasks/rta_demo.rake` — namespace `rta`

| Task | Description | Flags |
|---|---|---|
| `rta:demo[fund_id]` | Ensures a fund's `FundUnitSetting`s all have ISINs, generates an all-success and an all-issue-types RTA statement PDF from the fund's live data, and runs `RtaReconciliationAgent` against both — a one-command way to exercise the full reconciliation pipeline. | Generates real files; runs a real agent pass |

### `lib/tasks/remittance_reconciliation.rake` — namespace `remittance_reconciliation`

| Task | Description | Flags |
|---|---|---|
| `remittance_reconciliation:statement[capital_call_id, bank, coverage, run]` | Generates a bank-statement `.xlsx` (ICICI or Axis export format) for an **existing** capital call, crafted from the call's own remittances so `RemittanceReconciliationAgent` would hit every outcome type (Exact, Partial, Probable, discrepancy, overpayment, No match, Internal, ignored withdrawal) if run against it. `coverage` is `full` (default — also pays every other outstanding remittance) or `sample` (one row per outcome). Add `run` as the last arg to also execute the agent against the generated statement. **Creates nothing in the DB** — the statement is a standalone file. | Generates a file; `run` executes a real agent pass |

### `lib/tasks/faq_threads_setup.rake` — namespace `faq_threads`

| Task | Description | Flags |
|---|---|---|
| `faq_threads:setup` | Uploads docs from `public/docs/` and creates an OpenAI Assistant (`KnowledgeBaseSetupService`) named "CapHive Support Bot". | ⚠️ Calls OpenAI API, creates a billable Assistant + vector store |
| `faq_threads:delete_assistant` | Deletes an OpenAI Assistant given `FAQ_ASSISTANT_ID` env var. | ⚠️ **Destructive** — deletes an OpenAI Assistant |
| `faq_threads:recreate_assistant` | Recreates an OpenAI Assistant using an existing `VECTOR_STORE_ID` env var. | ⚠️ Calls OpenAI API |
| `faq_threads:get_assistant` | Retrieves OpenAI Assistant details including its Vector Store IDs. | Read-only |

---

## Business operations

Tasks that run production business logic on demand — allocation-run auditing, remittance
reconciliation reports (listed above with the other demo/reconciliation tooling), the
weekly engineering/marketing email digest, and LLM model-registry sync.

### `lib/tasks/allocation_run_checker.rake` — namespace `allocation`

Generates allocation-run-checker reports **after the fact**, for runs that finished before
anyone pressed the "Check" button, or before the checker existed. Nothing about the checks
is captured at run time — every one is **recomputed from the ledger, formulas, and
commitments as they currently stand**, which is what makes a backfill possible and also
what limits how far back it's meaningful to go (checks needing `account_entries
.allocation_run_id` — added 2025-03-29 — or `allocation_runs.status` — added 2024-07-28 —
say so and skip rather than reporting a false failure on older runs).

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `allocation:check[run_id]` | Generates the checker report for one `AllocationRun`. | ⚠️ Reads the (very large) `account_entries` table | — |
| `allocation:check_fund[fund_id]` | Generates reports for every run on a fund. `FROM=2025-04-01 TO=2025-12-31` can bound the period. | ⚠️ Reads `account_entries` at scale | — |
| `allocation:check_entity[entity_id]` | Generates reports for every run across every fund in an entity. | ⚠️ Largest-scope variant | — |

Shared ENV vars across all three: `ONLY_UNCHECKED=true` (skip runs that already have a
report; default is to re-check and **overwrite** every existing report — there is never
more than one per run), `NOW=true` (run in-process instead of queueing a background job),
`DRY_RUN=true` (list what would be checked and stop). Reports are attributed to the
entity's first company admin, as if they'd clicked Check themselves.

### `lib/tasks/weekly_email.rake` — namespace `irm`

| Task | Description | Flags |
|---|---|---|
| `irm:weekly_email_internal` | Generates an internal engineering-update email from recent git commits (all commit types, full detail). | `DAYS=7` lookback, `PRODUCT=CapHive`, `SEND=true` to actually deliver via SES to `support@caphive.com` (⚠️ real email), `TO=foo@bar.com` to override recipient, `CREDS_ENV=staging.in` to use a different SMTP credentials environment |
| `irm:weekly_email` | Generates a **weekly marketing email draft** from recent git commits, aimed at an external audience rather than engineers. | Same ENV vars as above — `SEND=true` sends a **real marketing email** via SES |

### `lib/tasks/ruby_llm_models.rake` — namespace `irm:ruby_llm`

| Task | Description | Flags |
|---|---|---|
| `irm:ruby_llm:refresh_models` | Refreshes RubyLLM's model registry (new/updated model ids, context windows, pricing) from the OpenAI/Gemini/Anthropic provider APIs, saves it to `models.json`, and syncs the app's `Model` table so the in-app model pickers see the same data. | ⚠️ Calls live provider APIs; overwrites `models.json` and the `Model` table |

---

## Email / Office add-ins

Build and deploy tooling for the Gmail and Outlook add-ins (Apps Script / Office manifest
based). These boot **without** the Rails environment on purpose — they touch no database
and run from a developer machine against a remote host.

### `lib/tasks/gmail_addin.rake` — namespace `gmail`

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `gmail:build[env]` | Generates the Gmail add-on source for an environment locally, **no push**. | Writes local build dir | — |
| `gmail:setup[env]` | Builds, creates the Apps Script project if it doesn't exist, and pushes the add-on. A `setup`-pushed deployment installs only for the script owner. | ⚠️ Pushes to a remote Apps Script project | `gmail:build` (implicitly) |
| `gmail:release[env]` | Full release: build, push, and cut a **versioned deployment** — what any real user actually installs. Refuses to release to a `production*` env unless `CONFIRM=<env>` is also set (e.g. `CONFIRM=production rake gmail:release[production]`). | ⚠️ **Production-facing release**. Requires `CONFIRM=<env>` for production | `gmail:setup` (implicitly) |
| `gmail:deployments[env]` | Lists the Apps Script deployments for an environment. | Read-only | — |
| `gmail:open[env]` | Prints the Apps Script project URL for an environment. | Read-only | — |

### `lib/tasks/outlook_addin.rake` — namespace `outlook`

| Task | Description | Flags |
|---|---|---|
| `outlook:manifests` | Regenerates the per-tenant Outlook add-in manifests (`public/manifests/<tenant>_outlook_addin.xml`) from `config/outlook_addins.yml` via ERB. Raises if two tenants share an add-in `<Id>` (they'd be unable to install side by side and the second would overwrite the first). | Writes into `public/manifests/` |

---

## Marketing website

The static `caphive.com` marketing site, built from `website_src/` into the committed
`public/website/` output (served directly by nginx off disk — puma never sees this
traffic).

### `lib/tasks/website.rake` — namespace `website`

| Task | Description | Flags |
|---|---|---|
| `website:build` | Renders every page in `website_src/pages/` (YAML front matter + body) through `website_src/_layout.html.erb`, stamping asset URLs with a content hash, and writes the result into `public/website/`. Assets (css/js/img) are **not** templated and stay as-is. The output is committed — a deploy never rebuilds it, but hand-editing files under `public/website/` directly will be silently overwritten by the next build. | Overwrites `public/website/*.html` |

### `lib/tasks/website_leads.rake` — namespace `website_leads`

| Task | Description | Flags |
|---|---|---|
| `website_leads:purge` | Retention enforcement for `WebsiteLead`, run daily from `config/schedule.rb` — makes the published privacy-policy retention windows literally true rather than aspirational. Two-phase: (1) nulls `request_ip`/`user_agent` (abuse-control data) on leads past the shorter abuse-data window, batched via `in_batches(of: 1_000)` since the capture endpoint is public and a spam flood is this table's one growth path; (2) `delete_all`s (not `destroy_all` — no callbacks/associations) whole records past the full retention window. | ⚠️ **Destructive** — permanently deletes lead PII past retention |

### `lib/capistrano/tasks/website.rake` — namespace `website`

Deploys the static site **without** a full app deploy — no bundle, no `assets:precompile`,
no migration, no puma/sidekiq restart. This patches the **currently deployed release** in
place; since `public/website` is git-tracked, the next full `cap deploy` re-checks it out
from the deploy branch, so an uncommitted website change silently reverts on the next
regular deploy.

| Task | Description | Flags |
|---|---|---|
| `website:build` | Wraps `rake website:build`, run locally via `run_locally`. | Writes local files |
| `website:upload` | Uploads `public/website/` to the live release's `current_path` on every `:web` app server (deliberately `current_path`, not `release_path` — the latter has no meaning outside a running deploy). | ⚠️ **Modifies files on live production servers** |
| `website:verify` | Curls the website vhost on each server and reports the status code. | Read-only |
| `website:deploy` | Build + upload + verify in sequence — the normal way to ship a website-only change. Warns loudly if the local working tree is dirty. | ⚠️ Production-facing | `website:build`, `website:upload`, `website:verify` |

---

## Testing / CI

### `lib/tasks/cucumber.rake` — namespace `cucumber`

Auto-generated by `cucumber-rails` — the file header explicitly warns against hand-editing
it (regenerate on a cucumber-rails upgrade instead; put custom code elsewhere).

| Task | Description | Flags | Depends on |
|---|---|---|---|
| `cucumber:ok` | Runs features that should pass. | Runs test suite | `test:prepare` |
| `cucumber:wip` | Runs features tagged as work-in-progress. | Runs test suite | `test:prepare` |
| `cucumber:rerun` | Records failing features and re-runs only those, if any. | Runs test suite | `test:prepare` |
| `cucumber:all` | Runs `ok` and `wip`. | — | `cucumber:ok`, `cucumber:wip` |
| `cucumber` (top-level alias) | Alias for `cucumber:ok`; also the `default` task when this file is loaded standalone. | — | `cucumber:ok` |
| `cucumber:statsetup` | Registers Cucumber feature directories with `rails/code_statistics` so `rails stats` includes them. | — | `:environment` |
| `cucumber:stats` | Alias for `statsetup`. | — | — |
| (fallback) `cucumber` | If the `cucumber` gem isn't installed, a stub task is defined instead that just reports it's unavailable. | — | — |

Also referenced elsewhere in this doc: `lib/tasks/support/workflow_seed_helpers.rb` is a
shared helper module (`WorkflowSeedHelpers`) used by `workflow_seeds.rake` and
`investor_workflow_seeds.rake` for common entity/actor lookup and template/step creation —
it defines no rake tasks of its own. `lib/tasks/aws_utils.rb` similarly defines no tasks
directly; it's a shared module (`AwsUtils`, mixed in via `include AwsUtils`) providing AMI
lookup, Pulumi stack-output reading, replication reset, and DR-changes-commit helpers
consumed by most of the `aws:*` and `dr:*` tasks above.
