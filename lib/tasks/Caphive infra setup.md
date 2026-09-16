# Infra Setup & Disaster Recovery Runbook

> **In an actual DR event, start with `docs/operations/dr/dr_guide.md`** — the operator guide
> (scenario decision table, the one command, what happens, verification
> checklists, aftermath). This file is the fuller setup/reference runbook.

This runbook covers rebuilding an environment in a new region (DR) and standing up
a brand-new region. It matches the code in `lib/tasks/aws.rake` / `lib/tasks/aws_utils.rb`
and the Pulumi project in the sibling `IRM-Infra` repo.

## Deployment variants

Two independent deployments, each with its own domain, credentials, env files and regions:

| Variant | Domain | Regions (primary → DR) | Cap stages | Credentials / env files |
|---|---|---|---|---|
| **IN** (India) | `*.caphive.com` | ap-south-1 → ap-south-2 | `production_in`, `staging_in` | `production.in.yml.enc`, `.env.production.in` |
| **US** | `*.caphive.us` | us-east-1 | `production_us`, `staging_us` | `production.us.yml.enc`, `.env.production.us` |

Staging uses `*.altconnects.com` (IN) / `*.altconnects.us` (US).

## Naming conventions (keep these in sync)

For `stack=production`, `region=ap-south-2`, `env_variant=in`:

| Thing | Pattern | Example |
|---|---|---|
| Pulumi stack | `<stack>-<region>` | `production-ap-south-2` |
| Pulumi config file | `Pulumi.<stack>-<region>.yaml` | `Pulumi.production-ap-south-2.yaml` |
| Env file | `.env.<stack>.<variant>` | `.env.production.in` |
| Rails credentials | `<stack>.<variant>.yml.enc` + `.key` | `production.in.yml.enc` |
| Capistrano stage | `<stack>_<variant>` | `production_in` |

The variant is deliberately **not** part of the Pulumi stack name — the region already
implies it. `env_variant` only selects the app-repo file names.

## Prerequisites

1. `git clone` both repos as **siblings** (the rake tasks hardcode `../IRM-Infra`):
   `IRM` and `IRM-Infra`.
2. Pulumi CLI installed and logged into the state backend (`pulumi whoami`).
   State migration to a company-owned S3 backend is scripted in
   `IRM-Infra/migrate_state_to_s3.sh` — after migration, login is
   `pulumi login "s3://<state-bucket>?region=<region>"` and
   `PULUMI_CONFIG_PASSPHRASE` must be exported (stored in Rails credentials).
3. AWS credentials for the target account. The `env_name` argument (e.g.
   `production.in`) makes `aws:environment` load `.env.production.in` via Dotenv and
   decrypt `config/credentials/production.in.yml.enc` with its `.key` to configure the
   AWS SDK — so the correct `.key` files must be present locally.
4. An EC2 **key pair** must already exist in the target region (Pulumi does not create
   key pairs). IN prod: `caphive`; US prod: `caphive2.us`.
5. A Route53 **hosted zone** for the variant's base domain must already exist
   (`caphive.com` / `caphive.us`) — Pulumi looks it up for ACM cert validation.
6. `MYSQL_ROOT_PASSWORD` present in Rails credentials (or exported) if you will bake
   AMIs — AMI baking fails fast without it.
7. Latest AMIs present in the target region for `AppServer`, `DB-Redis-ES` and
   `Observability` (the weekly cron bakes and copies them to `AWS_BACKUP_REGION`;
   verify with `rake "aws:get_latest_ami[AppServer, <region>, <env_name>]"`).
8. **SSM backup parameters seeded in the target region** — the baked DB backup
   script reads MySQL creds + bucket config from SSM at runtime:
   `rake "xtrabackup:seed_ssm_params[production.in, ap-south-2]"`
   (idempotent; re-run to rotate values; seed every region that hosts DB instances
   **before** you need it in an incident).

## Background

1. Every week, AMIs for AppServer and DB-Redis-ES are baked and copied to
   `AWS_BACKUP_REGION` (see `config/schedule.rb`), keeping the 3 newest.
2. MySQL backups: nightly full + half-hourly incrementals streamed to S3 via
   Percona XtraBackup (`db_backup_xtra.sh` on the DB server).
3. DR = rebuild in `AWS_BACKUP_REGION`, which becomes the new `AWS_REGION`.

## DR procedure (rebuild a region)

### 0. Export AWS keys for the target account

```bash
export AWS_REGION=<target region>            # e.g. ap-south-2
export AWS_ACCESS_KEY_ID=xxxxx
export AWS_SECRET_ACCESS_KEY=yyyyy
```

### 1. Run the master task — one command, no prompts (recommended)

```bash
# Signature: aws:setup_infra[stack, web_server_name, db_server_name, region, env_variant, env_name, branch]
# IN production into the DR region, fully unattended:
RAILS_ENV=production rake "aws:setup_infra[production, AppServer, DB-Redis-ES, ap-south-2, in, production.in, dr_prod_in_2026_07_08]"

# US production rebuild:
RAILS_ENV=production rake "aws:setup_infra[production, AppServer, DB-Redis-ES, us-east-1, us, production.us, dr_prod_us_2026_07_08]"
```

With a **branch name** (7th arg) the task runs end-to-end unattended:
provision → rewrite config → **auto-commit only the three rewritten files to the
branch + push** → deploy → maintenance mode → **restore primary + replica from S3
(runs from the app server; arms the baked backup cron on the primary)** →
**replay migrations newer than the backup** → traffic back. Re-running with the
same branch converges (no-op commit if nothing changed).

**Legacy interactive mode**: omit the branch — the task pauses for a manual DB
restore and a manual commit, then prompts for the branch name (the pre-2026
behaviour, kept as a fallback).

All arguments matter:
- `stack` — `production` or `staging`; combined with `region` it names the Pulumi stack.
- `web_server_name` / `db_server_name` — the AMI name tags to look up (`AppServer`, `DB-Redis-ES`).
- `region` — target region (defaults to `$AWS_REGION`).
- `env_variant` — `in` or `us`; selects env file, credentials pair and cap stage (table above).
- `env_name` — e.g. `production.in`; tells `aws:environment` which `.env.*` and
  credentials to load for the AWS SDK.

The task will: refresh Pulumi config with the latest AMIs → `pulumi up` → write the new
private IPs into Rails credentials (`DB_HOST`, `DB_HOST_REPLICA`) and
`.env.<stack>.<variant>` (`ELASTIC_SEARCH_URL`, `REDIS_URL`) → rewrite the app server
IPs in `config/deploy/<stack>_<variant>.rb`.

### 2. Legacy mode only — when the task pauses: restore the DB, commit, continue

(Skip this section in branch mode — restore, commit and migrations are automatic.)
The script pauses after rewriting the config files. While it waits:

a. **Review the changed files** (credentials, `.env.*`, deploy stage file).
b. **Restore the database** onto the new DB server (reachable only via the app
   servers — SSH through one of them):
   - The backup/restore script is **baked into the DB AMI**: run
     `sudo /usr/local/bin/db_backup_xtra.sh restore_primary`
     (it reads its config from SSM via the instance role — see prerequisites).
   - Fallback for instances from older AMIs: generate the script locally with
     `RAILS_ENV=production rake xtrabackup:generate_backup_script`, copy
     `tmp/db_backup_xtra_production.sh` to the DB box via an app server, run
     `./db_backup_xtra_production.sh restore_primary`.
   - The old datadir is parked as `<datadir>.bak.<timestamp>` — delete it only after
     verifying the restore; the script prints rollback instructions if MySQL fails to start.
   - On success the restore **arms the baked backup cron** (`/etc/db_backup_enabled`)
     — the nightly-full/half-hourly-incremental schedule resumes automatically.
   - **True region loss** (the primary region's S3 is unreachable): restore from
     the DR-region replica bucket by passing it explicitly —
     `rake "db:restore_primary_remote[<bucket>-replica-backup-xtra, <dr-region>]"`
     (or on the DB box: `sudo env BUCKET_OVERRIDE=... AWS_REGION_OVERRIDE=... db_backup_xtra.sh restore_primary`).
     By default restores read the primary-region bucket cross-region, which is
     correct for every scenario short of regional S3 loss. Keep the replica
     backfilled (`aws s3 sync` once; replication covers new objects).
c. **Commit** the changes to a branch, e.g. `new_infra_prod_2026_07_08`.
d. Type the branch name at the prompt to continue (or `exit` to abort).

The task then runs, against the new infra: `recovery:delete_old_assets` → `IRM:setup` →
`deploy` → `nginx:switch_maintenance` → `recovery:restore_replica_db` → `nginx:switch_app`.

### 3. Post-restore steps (in order)

1. **Migrations**: automatic in branch mode (`recovery:migrate` runs before the
   traffic switch). Legacy mode: run `RAILS_ENV=production bundle exec rails db:migrate`
   on the app server if the backup predates the last deploy.
2. **Replication**: automatic — the restore tasks reset replication themselves.
   Manual re-run if ever needed: `rake db:reset_replication` on the app server.
3. **Backups armed?** The cron schedule is baked into the DB AMI and armed
   automatically by `restore_primary`. Verify: `ls /etc/db_backup_enabled` on the
   primary, and after the next half-hour tick check `/var/log/db_backup.log` and
   the `-backup-xtra` S3 bucket for a fresh incremental. (The replica must NOT
   have the marker — only one writer per backup chain.)
4. **Monitoring**: `rake aws:generate_prometheus_yml` to point Prometheus at the new
   instances; `rake grafana:provision` for dashboards/alerts/contact points.
5. **DNS cutover** (manual by design — the moment the region goes live):
   `rake "aws:dns_cutover[production, <region>, in]"` — shows the current record,
   asks for confirmation, then aliases `app.<domain>` to the new ALB. Never run
   automatically; drills skip it entirely. Verify the ACM cert validated.
6. **Verify**: app responds on the domain, Sidekiq running, replica in sync
   (`SHOW REPLICA STATUS`), and `rake s3:check_backup_freshness` passes —
   it alerts if the backup chain (primary or replica bucket) is stale or missing.

## New region / landing zone (flexible setup)

A region that has never been used needs, in order:

1. **Key pair**: create/import in the region (EC2 → Key Pairs).
2. **AMIs**: copy the three AMIs into the region —
   `rake "aws:copy_ami[<ami_id>, <region>, <env_name>]"` for each — or bake
   FRESH ones directly in the target region (preferred before a migration):
   `PACKER_AWS_REGION=<region> rake "packer:build_env[prod, in, all]"`
   (the packer-build network auto-creates in that region on first use).
3. **Hosted zone**: must exist for the variant's base domain (usually already global).
4. **Configure + create the stack in one command** — `DOMAIN_NAME` and `AWS_KEY_NAME`
   seed the two curated values every new stack needs; existing stacks never need them:

```bash
DOMAIN_NAME='*.caphive.com' AWS_KEY_NAME=caphive \
  rake "aws:setup_pulumi_config[production, AppServer, DB-Redis-ES, <new-region>, in, production.in]"
```

5. Then either `pulumi up --stack production-<new-region>` (infra only) or the full
   `aws:setup_infra[...]` (infra + deploy + restore) as above.
6. **Backups arming**: `restore_primary` arms the backup cron automatically. If
   this new environment starts with an EMPTY database (no restore), arm the
   primary manually or backups never run:
   `sudo touch /etc/db_backup_enabled` on the DB primary — then verify with
   `rake s3:check_backup_freshness` after the first cron tick.

If `domain_name`/`key_name` are missing and the ENV vars aren't set, the task fails
immediately with instructions — it will not leave a half-configured stack behind.

## DR flow — sequence diagram

```mermaid
sequenceDiagram
    autonumber
    actor Op as Operator
    participant Rake as aws:setup_infra
    participant PC as Pulumi (IRM-Infra)
    participant AWS as AWS (target region)
    participant App as App repo files
    participant DB as New DB primary
    participant Cap as Capistrano

    Op->>Rake: rake aws:setup_infra[production, AppServer, DB-Redis-ES, ap-south-2, in, production.in]
    Rake->>PC: stack select production-ap-south-2, config set (latest AMIs, region)
    Rake->>PC: ensure domain_name + key_name present (fail fast if new stack unseeded)
    Rake->>PC: pulumi up --yes
    PC->>AWS: VPC, subnets, EC2 (web x2, DB, replica, obs), ALB, ACM cert, SGs
    PC-->>Rake: output.json (public/private IPs)
    Rake->>App: update credentials (DB_HOST/REPLICA), .env.production.in, deploy/production_in.rb
    Rake->>App: auto-commit ONLY the 3 rewritten files to <branch>, push (branch mode)
    Rake->>Cap: recovery:delete_old_assets, IRM:setup, deploy (branch)
    Rake->>Cap: nginx:switch_maintenance
    Rake->>Cap: recovery:load_db_from_backups (runs on app server)
    Cap->>DB: restore primary from S3 → arms baked backup cron; reset replication
    Cap->>DB: restore replica from S3 (stays disarmed — single backup writer)
    Rake->>Cap: recovery:migrate (replays migrations newer than the backup)
    Rake->>Cap: nginx:switch_app
    Op->>DB: verify: rake s3:check_backup_freshness, replica in sync
    Op->>AWS: DNS cutover to new ALB, prometheus/grafana provision
```

## Additional setup (still manual)

1. **S3 buckets**: `RAILS_ENV=production bundle exec rake "aws:provision_s3_buckets[production.in]"`
   creates source/replica/backup buckets with versioning **and** configures
   cross-region replication (app assets + DB backup buckets) and CORS. Idempotent —
   safe to re-run; existing replication/CORS configs in live regions are never
   overwritten. Note replication covers new objects only; the task prints the
   backfill command when it creates a new rule.
2. **SES**: fully codified but opt-in per stack —
   `pulumi config set manage_ses true --stack <stack> && pulumi up` creates the
   domain identity, verification TXT, DKIM CNAMEs and bounce tracking. Off by
   default so drills/fresh stacks never register identities. (Sandbox exit for a
   brand-new region remains an AWS support request.)
3. **Backup retention**: handled automatically — `aws:provision_s3_buckets` sets a
   90-day expiry lifecycle rule (override with `DB_BACKUP_RETENTION_DAYS`) on both
   backup buckets. (`rake aws:setup_s3_glacier` is superseded for backup buckets;
   Glacier was deliberately avoided — retrieval delay is unacceptable mid-DR.)

## DR drill (quarterly)

Prove the whole chain end-to-end against staging in the DR region — same code
path as a real DR, with measured RTO appended to `docs/operations/dr/dr_drills.md`:

```bash
TEARDOWN=true rake "aws:dr_drill[in]"    # and [us]; drop TEARDOWN to inspect the infra
```

## Known gaps (tracked in docs/operations/dr/review/)

- Pulumi state migration to S3 pending execution (script ready — Point 12).
- SES sandbox exit in a brand-new region is an AWS support request (not codifiable).
