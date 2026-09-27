# 2026-09-27 — prod IN Redis MISCONF / data box disk full: what to examine

Companion to [disk_hygiene_remediation_design.md](../disk_hygiene_remediation_design.md), which
holds the incident narrative and the proposed fixes (T1–T9). **This file is the audit list**:
everything the incident exposed that someone should look at, whether or not it caused the outage.

All findings below were verified read-only on 2026-09-27. Nothing was changed on any box.

**One-line summary:** the root disk on the data box `10.0.3.182` filled, Redis could not write
`dump.rdb`, and with `stop-writes-on-bgsave-error yes` it refused every write for ~80 minutes.
The disk filled because prod IN's `incr` backup cron has been taking its full-restore fallback
branch every 30 minutes — it cannot find its LSN checkpoint, which lives in `/tmp` — and that
branch stages downloads on the root volume. Restores from the bucket itself work.

```mermaid
flowchart LR
  B["incr cron loses its LSN checkpoint<br/>(/tmp wiped on reboot)"] --> FB["Every 30 min:<br/>falls back to full-chain download"]
  FB --> DF["Root disk fills"]
  DF --> RM["Redis MISCONF<br/>writes refused"]
  DF --> MY["MySQL errno 28"]
  RM --> J["Sidekiq dead ·<br/>user-facing 500s"]
  RM --> RA["Rack::Attack fails OPEN"]
  RM --> EM["~4,500 identical emails"]
  DF --> RB["Manual reboot"]
  RB --> QL["Redis has no volume →<br/>all queued jobs destroyed"]
  RB --> H["Looks healthy again.<br/>Nothing actually fixed."]
```

---

## A. Backups and restorability — examine first

- [ ] **A1. The `incr` cron fails every 30 minutes — in its fallback branch, not at S3.**
  `xbcloud` logs `failed after 3 attempts` on each run. Two things to examine, in this order:

  1. **Why it is in the fallback branch at all.** The log's first line is
     `WARN: LSN not found or readable. Falling back to restoring full backup.` — see **A4**.
     A healthy incremental should never take this path.
  2. **The command it builds there is malformed.** `retry()`'s error echoes
     `xbcloud … get` followed by **nine** backup names (`2026-04-19_230001-full` …
     `2026-09-26_230001-full`). `get` takes one backup name, so whatever selects "the latest
     full" is returning the whole list and passing it as a single argument. Examine that
     selection logic.

  **Not the cause:** the bucket name. An earlier revision of this document claimed the dots in
  `docs.caphive.com.production-backup-xtra` broke TLS because AWS serves a single-label wildcard
  (`CN = *.s3.ap-south-1.amazonaws.com`). It is true that a *virtual-hosted-style* URL for a
  dotted bucket fails verification — measured on the box — but it was never verified that
  `xbcloud` issues requests in that form, and `xbcloud` has bucket-lookup handling for exactly
  this case. **Restores from this bucket are known to work.** The `SSL peer certificate` lines in
  the log still want an explanation, but they are not evidence that the bucket is unreachable —
  run the failing `xbcloud` invocation verbosely, and check whether the key has `s3:ListBucket`,
  since the paired error is literally `Cannot list <name>`.

- [ ] **A2. When did a backup last actually succeed?** I could not list the bucket — the AWS CLI on
  the data box has no ambient credentials, and I deliberately did not go hunting for the secret to
  source it. `xbcloud`'s own error output names fulls up to `2026-09-26_230001-full`, but that is
  the *argument list* it was given, not proof the objects exist or are complete. **Verify the last
  restorable full + incremental chain before anything else on this list.**

- [ ] **A3. Has a restore ever been tested from this chain?** `backup_db.sh` contains
  `restore_full`, `apply_incremental`, `TEST_RESTORE` and `PRIMARY_RESTORE` paths, so the intent
  exists. Confirm a restore has been exercised end-to-end since the bucket was created.

- [ ] **A4. The LSN checkpoint lives in `/tmp`.** `--extra-lsndir=/tmp/lsndir`, and
  `MYSQL_TMPDIR` defaults to `/tmp`. `/tmp` is cleared on boot and this box reboots, so the
  checkpoint is destroyed and every subsequent run logs
  `WARN: LSN not found or readable. Falling back to restoring full backup.` Both `/tmp/lsndir` and
  `/tmp/lsndir-incr` are **absent right now**. Move this to a reboot-persistent path.

- [ ] **A5. The fallback path stages multi-GB downloads on the root volume.**
  `TMPDIR="${MYSQL_TMPDIR}/xb_$$"` → `/tmp` → `/`. Combined with A4, a 30-minute cron tries to
  pull the whole full-backup chain onto the same volume MySQL lives on. Stage elsewhere, or stream.

- [ ] **A6. Does the 30-minute cadence make sense?** `0,30 0-22 * * *` for incrementals plus a
  full at 23:00. Confirm that matches the actual RPO you want, now that we know each run was
  attempting a full-chain restore.

## B. Disk capacity and growth

- [ ] **B1. `/var/lib/mysql` is 27G of a 58G root volume** and growing. Everything else on the list
  only buys headroom. Decide whether the volume grows or the data tier moves off the root disk.
- [ ] **B2. `db:purge_binlogs` runs 4× a month** (`30 22 1,8,15,22 * *`). MySQL named
  `./binlog.024065` as the file it could not write. Consider daily, and/or
  `binlog_expire_logs_seconds`.
- [ ] **B3. No `/etc/docker/daemon.json` on the data box** → `json-file` driver is unlimited.
  `dockerd` itself hit `no space left on device` writing a container log at 09:18:26.
- [ ] **B4. No swap on the data box** (app boxes have 4G). `overcommit_memory` is already `1`
  there, so BGSAVE forks survive, but ES holds 4.4G RSS of 7.8G with **no container memory limit**.
- [ ] **B5. Inode headroom** is fine today (3%) but should be in whatever check B6 produces.
- [ ] **B6. There is no disk alerting.** `node_exporter` is installed and running on all three
  boxes and `lib/tasks/grafana_provision.rake` already exists — nothing alerts on
  `node_filesystem_avail_bytes`. This is why a 17-day-old fault was found by reading an email.

## C. Redis durability and data-tier drift

- [ ] **C1. Redis runs `--rm` with no volume** (`binds=[]`, `mounts=` empty, `policy=no`). It holds
  Sidekiq's queues. Every reboot destroys them silently, and a restart makes MISCONF "disappear"
  while doing so. **Decide whether Redis is meant to be durable here** — it is the one genuinely
  blocking design question.
- [ ] **C2. `maxmemory=0`, `maxmemory_policy=noeviction`.** Unbounded, on a box with no swap.
- [ ] **C3. The data box is not running the code in this repo.**
  `/usr/local/bin/start_data_containers.sh` is **not installed**; ubuntu's crontab still has the
  raw `@reboot sudo docker run --rm …` lines that script was written to replace — the exact
  docker-daemon race documented in its header from the 2026-07-10 DR drill. Its AMI predates the
  script.
- [ ] **C4. Elasticsearch has no volume and no memory limit** on that box either — the crontab
  lines omit both `-v elasticsearch-data:…` and `--memory=4g` that the repo script specifies. So
  the ES index is rebuilt on every reboot.
- [ ] **C5. Docker swarm is active** on the data box (`ingress`, `mysqlnw` overlay networks).
  Nothing in the repo describes this. Establish what is swarm-managed and what is not.

## D. Secrets

- [ ] **D1. ⛔ S3 backup credentials are in a world-readable file.** `backup_db.sh` echoes its whole
  `xbcloud` command line — including `--s3-access-key` and `--s3-secret-key` — into
  `/tmp/mysql_backup_incr.log`, mode `0664`, on **every** failure, and it fails every 30 minutes.
  Key `AKIA4AIN3GAUL3SIYNMS`, bucket `docs.caphive.com.production-backup-xtra`. **Rotate the key**
  and pass credentials by env var or instance role so they cannot be logged.
- [ ] **D2. Audit for the same pattern elsewhere** — any other script that logs a failing command
  line verbatim.
- [ ] **D3. While rotating, confirm whether that key is used anywhere besides backups.**

## E. Observability and alert fatigue

- [ ] **E1. ~4,500 exception emails for one root cause.** `mail_production.log` on one app box:
  **1,457 in the 08:00 hour, 943 in the 09:00 hour**, with a comparable burst on the second box.
  `config/initializers/exception_notification.rb` has no `ignore_if` and no rate limit. A second,
  unrelated incident in that window would have been invisible.
- [ ] **E2. The precedent for the fix already exists in that file.**
  `SidekiqRedisFetchError.suppress?` was added after incident 2d7eca43 for exactly this shape —
  Redis blips in Sidekiq's BRPOP loop paging on-call for an already-healed event. Extend it.
- [ ] **E3. Nothing alerted for 17 days.** Earliest MISCONF in `sidekiq.log` is
  **2026-09-10 09:42 UTC**; 7,365 lines. Email was the only signal and it was ignorable by volume.
- [ ] **E4. `/health_check/redis_check` cannot detect this.** It round-trips `Rails.cache`, and
  production is `config.cache_store = :solid_cache_store` — MySQL. It returns `Ok` with Redis
  refusing every write. `lib/tasks/dr_verify_data_tier.rake` says the same thing in its header
  (finding #5) and does a real `SETEX`; nothing runs it on a schedule.
- [ ] **E5. Both health endpoints are invisible to a browser.** `respond_to` has only
  `format.json`, so `Accept: text/html` → `ActionController::UnknownFormat` → 406 → and with no
  `public/406.html` present, `PublicExceptions#render_html` returns a **bodyless 404**.

## F. App-server log hygiene

- [ ] **F1. logrotate has never run.** Both app boxes have the weekly cron, but
  `/home/ubuntu/IRM/shared/log/logrotate.conf` **does not exist** on either. A dry run as `ubuntu`
  gives `error: cannot stat … No such file or directory` / `Handling 0 logs`. Zero `.gz` files in
  the directory. State-file mtime Sep 26 00:50 proves the cron fires and does nothing.
- [ ] **F2. Cause is in the repo:** `configure_logrotate` (`config/deploy.rb:724`) is only called
  from `task :setup`, where the call is **commented out** at `config/deploy.rb:772`.
- [ ] **F3. Two divergent copies of the config.** `config/deploy/logrotate.conf` (`rotate 7`,
  `delaycompress`, `notifempty`, `create 0640 ubuntu ubuntu`) vs
  `config/deploy/templates/logrotate.conf` (`rotate 24`, bare `create`). Only the former is
  uploaded; the latter is dead code.
- [ ] **F4. Neither has `copytruncate` or a postrotate reopen.** puma, nginx and Rails hold their
  fds, so rotation only works because `sudo reboot` runs ten minutes later
  (`0 1 * * 6`). That is an accident, not a design.
- [ ] **F5. Current volume:** 2.4G and 2.8G of logs per box — `production.log` 846/944 MB,
  `nginx.access.log` ~583 MB, `puma.access.log` ~500 MB, `sidekiq.log` 428/577 MB. One week each.
- [ ] **F6. The weekly `sudo reboot` on the app boxes** deserves its own look — is it still needed,
  and is anything depending on it?

## G. Security exposure during the outage

- [ ] **G1. Rack::Attack failed OPEN for the whole window.** Its store is that same Redis, and
  `RedisCacheStore#failsafe` rescues `Redis::BaseError` returning `nil`
  (`activesupport-8.1.3.1/.../redis_cache_store.rb:492`), so **every throttle and the 404
  blocklist were off** — login brute-force limits included. The initializer's own comment says
  "every Redis failure fails OPEN". Treat Sep 10 → Sep 27 accordingly if reviewing access logs.
- [ ] **G2. `Log404s` did log its failures** (`Log404s middleware error: RedisClient::CommandError`)
  — buried in `production.log`. Consider whether that should alert.

## H. Topology and documentation drift

- [ ] **H1. The data box appears in no deploy file.** `production_in.rb` declares
  `15.206.165.118` as `%w[primary app db web]`, but that box has no MySQL/Redis/ES. The real data
  tier is `10.0.3.182`. No `cap` task can reach it today.
- [ ] **H2. SSH access to it is undocumented.** `caphive2.pem` does **not** work; the data box
  accepts the older `caphive.pem`, which exists only *on* the app boxes. `ssh -J` fails (it offers
  the local key on the second hop). Working form:
  ```bash
  ssh -i ~/.ssh/caphive2.pem ubuntu@15.206.165.118 \
    'ssh -i /home/ubuntu/.ssh/caphive.pem ubuntu@10.0.3.182 "bash -s"' <<'EOF'
  …
  EOF
  ```
- [ ] **H3. `config/deploy/production_in.rb` still has the ap_south_2 pair commented out.**
  Confirm whether that DR region exists and where its data tier is.

## I. Blast radius — cleanup owed

- [ ] **I1. Two Investor Statements 500'd** at 09:02:10 and 09:03:39 UTC —
  `PATCH /capital_commitments/13917/generate_soa`, template 52553, Aug 2026 period, from
  `101.2.249.26`. `KycDocGenJob` never enqueued. **Re-run them.**
- [ ] **I2. Every Sidekiq job queued, scheduled or retrying before 09:27:23 was destroyed** with
  the container. Establish what was in flight — statements, capital-call notices, doc generation,
  emails — and replay what matters. Queues are empty now (`retry=0 scheduled=0 dead=0`), so this
  has to be reconstructed from logs, not from Redis.
- [ ] **I3. The ~4,500 emails cannot be recalled.** Delivery is `:smtp` direct to
  `email-smtp.ap-south-1.amazonaws.com` with no local MTA and no pending mailer jobs, so they were
  accepted by SES hours ago. Clear the inbox with a filter; there is nothing to drain.
- [ ] **I4. The box rebooted twice in 23 minutes** (boots at 09:04:38 and 09:27:00). Find out who
  and why — it is the only unexplained action in the timeline.
