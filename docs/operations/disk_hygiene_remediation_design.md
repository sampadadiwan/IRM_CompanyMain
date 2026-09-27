# Prod IN disk hygiene — incident record and remediation design

**Status:** design, awaiting approval. No code written, no prod changes made.
**Audit list:** [27092026_prod_in_disk_full_incident_review.md](troubleshooting/27092026_prod_in_disk_full_incident_review.md) — everything this incident exposed, as a checklist.
**Investigated:** 2026-09-27, read-only, on all three prod IN boxes.
**Incident:** `RedisClient::CommandError (MISCONF ...)` flooding from prod IN.

---

## 1. Topology (as found, not as documented)

`config/deploy/production_in.rb` declares two servers and gives `15.206.165.118` the
roles `%w[primary app db web]`. That box has no MySQL, Redis or Elasticsearch. The data
tier is a third box, on a private address, that appears in no deploy file.

```mermaid
flowchart LR
  subgraph pub["Public (ALB → :80)"]
    A1["ip-10-0-2-137<br/>15.206.165.118<br/>puma · sidekiq · nginx · xirr_py"]
    A2["ip-10-0-1-56<br/>35.154.185.236<br/>puma · sidekiq · nginx · xirr_py"]
  end
  subgraph priv["Private — the real data tier"]
    D["ip-10-0-3-182 · 10.0.3.182<br/>MySQL (native) · redis-stack-server (docker)<br/>elasticsearch (docker) · mysqld_exporter<br/>58G root, 34G used"]
  end
  A1 -->|"REDIS_URL redis://10.0.3.182:6379"| D
  A2 -->|"MySQL · Elasticsearch"| D
  A1 -.->|"ssh caphive.pem<br/>(only key the data box accepts)"| D
```

`caphive2.pem` reaches the app boxes but **not** the data box. The data box accepts the
older `caphive.pem`, which exists only *on* the app boxes at `/home/ubuntu/.ssh/`. Hop:

```bash
ssh -i ~/.ssh/caphive2.pem ubuntu@15.206.165.118 \
  'ssh -i /home/ubuntu/.ssh/caphive.pem ubuntu@10.0.3.182 "bash -s"' <<'EOF'
…commands…
EOF
```

`ssh -J` does not work — it offers the local key on the second hop.

---

## 2. What actually happened

The root filesystem on the data box filled. Redis could not write `dump.rdb`, and with
`stop-writes-on-bgsave-error yes` it refused every write command — which is all the
`MISCONF` error ever was.

```mermaid
flowchart TD
  F["Root volume on 10.0.3.182 reaches 100%"] --> M["MySQL: InnoDB errno 28<br/>'Disk is full writing ./binlog.024065'<br/>07:58:45 UTC onward"]
  F --> R["Redis BGSAVE fails"]
  R --> MI["MISCONF — all writes refused"]
  MI --> S["Sidekiq push + heartbeat raise<br/>RedisClient::CommandError"]
  MI --> C["User-facing 500s:<br/>generate_soa → KycDocGenJob"]
  MI --> K["Rack::Attack store fails OPEN —<br/>throttles + 404 blocklist silently OFF"]
  F --> L["rsyslogd + dockerd:<br/>'no space left on device' 09:18:26"]
  M --> RB["Box rebooted 09:27:00"]
  RB --> W["Redis container recreated EMPTY<br/>(--rm, no volume) → all Sidekiq queues destroyed"]
  RB --> Q["MISCONF stops — space freed by reboot + docker image prune"]
```

### Timeline (UTC; IST = +5:30)

| Time | Evidence |
|---|---|
| **Sep 10 09:42** | Earliest `MISCONF` in `sidekiq.log` — **7,365 lines over 17 days**. Recurring, not new. |
| Sep 27 07:58:45 | MySQL error log: `InnoDB ... Operating system error number 28` / `No space left on device` |
| Sep 27 08:31:47 | `Disk is full writing './binlog.024065' ... Waiting for someone to free space` |
| Sep 27 09:02, 09:03 | Two user-facing **500s** — `PATCH /capital_commitments/13917/generate_soa` could not enqueue `KycDocGenJob` (Investor Statement, template 52553, Aug 2026) |
| Sep 27 09:18:23–31 | Sidekiq heartbeat failures; `rsyslogd`/`dockerd` `no space left on device` |
| Sep 27 09:27:00 | Data box deliberately rebooted (clean `systemd-shutdown`; its previous boot had begun only at 09:04:38 — two reboots in 23 min) |
| Sep 27 09:27:23 | `redis-stack-server` recreated empty → MISCONF ends, **queues lost** |
| Sep 27 09:28:31+ | `dockerd` image prunes — how space was actually reclaimed |
| Sep 27 11:36 | Both app boxes rebooted |
| Now | Redis healthy: `rdb_last_bgsave_status:ok`, 108 keys, 2.43 MB; disk 34G/58G |

### Email blast

`mail_production.log` on `15.206.165.118` alone: **1,457 emails in the 08:00 hour and 943 in
the 09:00 hour**, with a comparable burst on the second app box — roughly 4,000–5,000
exception emails for this one root cause. The **last** MISCONF-bearing email was generated at
**09:18:29 UTC**; the only two since are ordinary "Login request received" notices at 11:46
and 11:47. Anything still arriving in the inbox after that is SES/Gmail delivery backlog, not
a live fault — the `Date:` header, not the received time, is what distinguishes them.

**The error stopped at 09:18:31.** Nothing was fixed; space was freed by hand.

---

## 3. Why the disk fills — three live mechanisms

### 3a. The incremental backup re-downloads the full backup chain (primary suspect)

`/home/ubuntu/backup_db.sh` keeps its xtrabackup LSN checkpoint in **`/tmp`**:

```
MYSQL_TMPDIR="${MYSQL_TMPDIR:-/tmp}"
TMPDIR="${MYSQL_TMPDIR}/xb_$$"
--extra-lsndir=/tmp/lsndir
```

`/tmp` is cleared on boot, and this box reboots (weekly cron on the app boxes, plus ad hoc).
With the checkpoint gone, every run takes the fallback path — the first line of
`/tmp/mysql_backup_incr.log` is literally:

```
WARN: LSN not found or readable. Falling back to restoring full backup.
```

…and the log then shows `xbcloud get` pulling **nine full backups** (`2026-04-19_230001-full`
… `2026-09-26_230001-full`) onto the root volume. That cron runs **every 30 minutes**
(`0,30 0-22 * * *`), with a full at 23:00. A multi-GB download twice an hour on a volume
with ~24G of headroom is a sufficient explanation for the fill.

It is *currently* failing outright — `xbcloud: error: http request failed: SSL peer
certificate or SSH remote key was not OK`, 3 attempts, at 11:30 and 12:00 today — which is
the only reason `/tmp` is 144K right now. **So prod IN incremental backups are also broken.**

### 3b. Binlogs are purged only four times a month

`db:purge_binlogs` runs `30 22 1,8,15,22 * *`. MySQL named `./binlog.024065` as the file it
could not write. `/var/lib/mysql` is **27G of the 58G volume**; between purges, binlogs are
unbounded.

### 3c. No Docker log rotation on the data box

There is no `/etc/docker/daemon.json`, so the `json-file` driver is unlimited. `dockerd`'s
own `no space left on device` error at 09:18:26 was a container `-json.log` write.

---

## 4. Separate finding — app-box log rotation has never run

Both app boxes have a weekly cron:

```
50 0 * * 6  logrotate /home/ubuntu/IRM/shared/log/logrotate.conf --state .../logrotate.state --verbose
0  1 * * 6  sudo reboot
```

**`logrotate.conf` does not exist on either box.** A dry run as `ubuntu` reproduces it:

```
error: cannot stat /home/ubuntu/IRM/shared/log/logrotate.conf: No such file or directory
Handling 0 logs
```

The state file's mtime is Sep 26 00:50 — last Saturday — so the cron fires on schedule and
does nothing. There are **zero** `.gz` files in the log directory: nothing has ever rotated.

Cause: `configure_logrotate` (`config/deploy.rb:724`) uploads the file, but its only caller
inside `task :setup` is **commented out** at `config/deploy.rb:772`. It ships only if someone
runs `setup_logrotate` by hand.

Current sizes — 2.4G and 2.8G of logs, one week's worth each, never rotated:

| File | 15.206.165.118 | 35.154.185.236 |
|---|---|---|
| `production.log` | 846 MB | 944 MB |
| `nginx.access.log` | 583 MB | 584 MB |
| `puma.access.log` | 517 MB | 477 MB |
| `sidekiq.log` | 428 MB | 577 MB |

Two further defects once the file does land:

- The repo has **two divergent copies** — `config/deploy/logrotate.conf` (`rotate 7`,
  `delaycompress`, `notifempty`, `create 0640 ubuntu ubuntu`) and
  `config/deploy/templates/logrotate.conf` (`rotate 24`, bare `create`). Only the first is
  uploaded; the second is dead.
- Neither has `copytruncate` or a postrotate reopen signal. puma, nginx and Rails hold their
  file descriptors, so a rename leaves them writing to the rotated inode. Today that is
  masked by the `sudo reboot` ten minutes later — the rotation only works *because* of the
  reboot, which is not a property to rely on.

---

## 5. Urgent, and outside the disk problem: leaked S3 credentials

On failure, `backup_db.sh` echoes the whole `xbcloud` invocation — including
`--s3-access-key` and `--s3-secret-key` — into `/tmp/mysql_backup_incr.log`, mode `0664`,
world-readable, and it has failed repeatedly today.

- Key ID: `AKIA4AIN3GAUL3SIYNMS` (bucket `docs.caphive.com.production-backup-xtra`)
- The secret is in that file in plaintext. It is not reproduced here.

**This key should be rotated regardless of anything else in this document,** and the script
changed to pass credentials via env vars or an instance role so they cannot be logged.

---

## 6. Proposed remediation

Per repo convention, everything operational is a rake task under `lib/tasks/*.rake` reading
per-env credentials — dry-run by default, `EXECUTE=1` to act, with an STS account assertion
before any mutation. No bash scripts.

```mermaid
flowchart TD
  S["rake ops:disk_guard"] --> STS{"STS account == expected<br/>for this env?"}
  STS -->|no| AB["abort — wrong account"]
  STS -->|yes| RPT["Collect per-box: df, df -i,<br/>top consumers, log sizes,<br/>docker log sizes, binlog count"]
  RPT --> DR{"EXECUTE=1 ?"}
  DR -->|no| OUT["Print report + what WOULD be reclaimed. Exit 0"]
  DR -->|yes| ACT["Reclaim: docker prune,<br/>rotate logs, purge binlogs"]
  ACT --> V["Re-check df; exit non-zero if still under threshold"]
```

### Task list, in the order I would land it

| # | Task | Where | Risk |
|---|---|---|---|
| **T1** | **Rotate the leaked S3 key**; stop `backup_db.sh` echoing credentials | data box + AWS | none to uptime; do first |
| **T2** | Move the xtrabackup LSN dir off `/tmp` to a reboot-persistent path; fix the `xbcloud` SSL failure; stop the incr job staging full downloads on the root volume | data box | fixes the fill **and** restores incremental backups |
| **T3** | `db:purge_binlogs` daily instead of 4×/month, and/or set `binlog_expire_logs_seconds` | data box | low |
| **T4** | `/etc/docker/daemon.json` with `log-opts max-size/max-file` | both tiers | needs docker restart → maintenance window |
| **T5** | `ops:disk_guard` rake task (report + `EXECUTE=1` reclaim) and a Grafana alert on `node_filesystem_avail_bytes` — `node_exporter` is already installed on all three boxes, and `lib/tasks/grafana_provision.rake` already exists to carry the rule | new rake task | low; read-only by default |
| **T6** | Land the logrotate config properly: one canonical file, add `copytruncate`, delete the dead duplicate, move the cron from weekly to daily, and make it verifiable rather than fire-and-forget | app boxes | low |
| **T7** | Redis durability — named volume for `/data`, `--restart unless-stopped`, `maxmemory` + policy; install the missing `start_data_containers.sh` and reconcile the data box's raw `@reboot docker run` crontab with the repo script; give Elasticsearch its `-v elasticsearch-data` volume and `--memory=4g`, both of which the box's crontab omits | data box | **restarts Redis and ES → maintenance window, and the Redis restart itself drains the queues, so run it when they are empty** |
| **T8** | Health endpoints: `/health_check/redis_check` exercises `Rails.cache` = Solid Cache = MySQL, so it cannot detect this outage at all; and both endpoints are JSON-only, so a browser gets `UnknownFormat` → 406 → bodyless 404 | app code | low |
| **T9** | **Throttle/dedupe exception email.** `config/initializers/exception_notification.rb` has no `ignore_if` and no rate limit, so one root cause produced ~4,000–5,000 identical emails in two hours and buried every other alert. The precedent already exists in this file: `SidekiqRedisFetchError.suppress?` was added for exactly this shape after incident 2d7eca43 (Redis blips in the BRPOP loop waking on-call for a healed event). Extend it — collapse repeats of the same exception class + message to one email per N minutes, and count the rest for Grafana | app code | low; **do first**, it is what makes every other alert legible |

### Open decisions for you

1. **Is Redis meant to be durable here?** It holds Sidekiq's queues but runs `--rm` with no
   volume, so every reboot silently drops them. T7 assumes yes. If the answer is "no, jobs are
   replayable", then T7 shrinks to a `maxmemory` setting and we accept the loss explicitly.
2. **Grow the data box root volume?** 27G of 58G is MySQL alone, and it grows. Capacity work
   makes T2–T5 breathing room rather than a fix.
3. **Split the data tier off the app-role declaration** in `production_in.rb` so `cap` can
   target `10.0.3.182` at all. Today no cap task can reach it.

### Verification, after each step

- `bundle exec cap production_in partial:verify_data_tier` — its Redis check does a real
  `SETEX`/`GET` write round-trip, so it fails under `MISCONF` and passes otherwise
  (`lib/tasks/dr_verify_data_tier.rake:44-62`).
- `df -h /` and `df -i /` on the data box, before and after.
- Confirm `.gz` files appear in `/home/ubuntu/IRM/shared/log/` on the app boxes.
- Confirm `/tmp/mysql_backup_incr.log` shows a *successful* incremental, with no
  "Falling back to restoring full backup".

---

## 7. Cleanup owed from this incident

- Re-run the two Investor Statements that 500'd at 09:02 and 09:03 for capital commitment
  **13917** (template 52553, Aug 2026) — their jobs never enqueued.
- Treat Sep 10 → Sep 27 as a window in which Rack::Attack throttles and the 404 blocklist
  were intermittently **off**, if you are reviewing access logs for that period.
- Any other Sidekiq work queued before Sep 27 09:27:23 was destroyed and has not been replayed.
