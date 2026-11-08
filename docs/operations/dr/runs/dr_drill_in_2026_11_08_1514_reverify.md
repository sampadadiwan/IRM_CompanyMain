# 🟢 Staging recovery in ap-south-2 verified: 68 / 68 checks passed (step 9 re-run after a fix)

**Passed** · DR drill · staging (in) → ap-south-2 · 8 Nov 2026, 09:44–10:05 UTC · run by thimmaiah@Inspiron

| — | 1:56 | 68 / 68 | 14 min |
|:-:|:-:|:-:|:-:|
| Recovery time (RTO): not measured — step 9 re-run after a fix; 15:14 run reached step 9 at 11:16 | Database restore (primary + replica together) | Checks passed · 0 warnings · 0 failed | Recovery point (RPO): data lost · restored to 09:30 UTC · promised 30 min |

## In plain words

- This report combines two runs on the same drill stack. Steps 1–8 ran in the 15:14 drill (11:16 to step 9). Step 9 stopped on a bug in the new load-balancer step, which was fixed (a63e7b9660) and re-run on the same stack at 10:04 UTC. The recovery time is not measured by this report.
- The whole staging environment was rebuilt from scratch in ap-south-2, the disaster-recovery region, from the same backups a real recovery would use.
- Each of the 2 app servers was checked end to end: web, background jobs, database, search and file storage, all through the app.
- The site was also checked the way users reach it: HTTPS through the new load balancer, before any DNS change.
- Every check passed.
- The database was recovered as it was at 09:30 UTC (the newest backup), 14 minutes before the recovery started. That is the data a real recovery at this moment would have lost.
- This was a drill: the live site was not touched and nothing was switched over, and the rebuilt servers were deleted afterwards.

## Recovery point and time vs what we promise clients

| | Objective | Promised to clients | This run |
|:-:|---|---|---|
| ✅ | **Recovery point (RPO)**: How much data a real recovery would lose | 30 minutes, while backup-freshness alerts are green | restored to 8 Nov 09:30 UTC (backup 2026-11-08_093001-incr): 14 min of changes lost |
| ⚠️ | **Recovery time (RTO)**: How long until users are served again | about 10 minutes for a staging-sized dataset, scaling with database size | not measured: Steps 1–8 ran in the 15:14 drill (11:16 to step 9). Step 9 stopped on a bug in the new load-balancer step, which was fixed (a63e7b9660) and re-run on the same stack at 10:04 UTC. The recovery time is not measured by this report. |

The recovery time shown is the rebuild. A customer's full wait also includes noticing the outage, deciding to recover and switching DNS. Promises: Security questionnaire H3/H4 (docs/gtm/prerequisites/E2_security_questionnaire.md).

## Needs attention

Nothing needs attention.

## What the recovery did, step by step

| | # | Step | Start (UTC) | Took |
|:-:|:-:|---|---|---|
| ✅ | 1 | Prepare the infrastructure settings | 09:44:20 | **0:03** |
| ✅ | 2 | Create servers, network and load balancer | 09:44:23 | **2:37** |
| ✅ | 3 | Point the app at the new servers | 09:47:00 | **0:17** |
| ✅ | 4 | Save those settings on a recovery branch | 09:47:17 | **0:04** |
| ✅ | 5 | Install the app on both servers | 09:47:21 | **5:59** |
| ✅ | 6 | Take the site offline | 09:53:20 | **0:10** |
| ✅ | 7 | Restore the database from backups | 09:53:30 | **1:56** |
| ✅ | 8 | Start the search rebuild (background) | 09:55:26 | **0:10** |
| ✅ | 9 | Bring the site back and verify it | 10:04:54 | **0:52** |

**What each step does**

- **1 · Prepare the infrastructure settings**: Points the DR stack at the newest server images and the DR region. *If it fails:* Run rake aws:dr_readiness — usually a missing server image or setting.
- **2 · Create servers, network and load balancer**: Pulumi creates the app servers, the database primary and replica, the load balancer and its certificate. *If it fails:* The Pulumi error names the resource. "Locked" means another run is in progress.
- **3 · Point the app at the new servers**: Writes the new database, Redis and search addresses into the app's settings and deploy file, waits for the servers to accept SSH, and removes old backup jobs copied from the live box. *If it fails:* A missing address means the Pulumi output is incomplete — re-run; an SSH timeout names the server.
- **4 · Save those settings on a recovery branch**: Commits only those settings to the recovery branch and pushes it, so the servers deploy exactly this code. *If it fails:* Check git access to origin and that the working tree had no conflicting edits.
- **5 · Install the app on both servers**: Installs Ruby, gems and the app on every app server. The longest step after the restore. *If it fails:* The Capistrano error names the server and the task that failed.
- **6 · Take the site offline**: Maintenance page on; web and background workers stopped, so nothing writes while the database is restored. *If it fails:* Check nginx on the named server: sudo nginx -t.
- **7 · Restore the database from backups**: Downloads the newest full backup and its incremental from S3 onto the primary and replica in parallel, then reconnects replication. *If it fails:* Look for the [primary] / [replica] lines in the transcript; the backup bucket and key are named there.
- **8 · Start the search rebuild (background)**: Search is not backed up, so a background job is queued to rebuild every search index the live app maintains from the restored database. The site comes back without waiting; search results fill in as the job runs, and the checks below show its progress. *If it fails:* The transcript's table names the index and why; re-run one with ONLY=<Index> cap recovery:reindex_search.
- **9 · Bring the site back and verify it**: Maintenance page off, then every check below runs on every app server. Any failed check fails the recovery. *If it fails:* The failed checks are listed under Needs attention, each with what to do.

## Verification: what was proven

Each check exercises the real thing, not a status file.

### Through the load balancer

| Check | ip-10-0-1-28 | ip-10-0-2-254 | load-balancer |
|---|---|---|---|
| HTTPS certificate (dev.altconnects.com) | — | — | ✅ certificate valid for dev.altconnects.com |
| Request reaches the database | — | — | ✅ HTTP 200 — a request reaches the app and the database |
| App servers healthy in the load balancer | — | — | ✅ 2 of 2 app servers healthy |
| Sign-in page over HTTPS | — | — | ✅ HTTP 200 — the sign-in page loads over HTTPS |

- **HTTPS certificate (dev.altconnects.com)**: The load balancer's certificate is valid for the address users type, so browsers will open the site without a warning.
- **Request reaches the database**: A request sent the way users send it (HTTPS to the load balancer) reached the app and the database.
- **App servers healthy in the load balancer**: The load balancer considers every app server healthy, so it sends users to all of them.
- **Sign-in page over HTTPS**: The sign-in screen loads over HTTPS through the load balancer, as a user would see it.

### App servers

| Check | ip-10-0-1-28 | ip-10-0-2-254 | load-balancer |
|---|---|---|---|
| Web server (nginx) running | ✅ active | ✅ active | — |
| App processes (puma) | ✅ 5 process(es) | ✅ 5 process(es) | — |
| Background jobs (sidekiq) | ✅ 2 process(es) | ✅ 2 process(es) | — |
| Monitoring exporter | ✅ 2 process(es) | ✅ 2 process(es) | — |
| Drill servers marked | ✅ drill servers marked (ap-south-2): tagged mail, no WhatsApp pages | ✅ drill servers marked (ap-south-2): tagged mail, no WhatsApp pages | — |
| Drill cannot contact users | ✅ nothing can reach users: mail intercepted, messaging hosts guarded, no timed jobs (0 held back so far) | ✅ nothing can reach users: mail intercepted, messaging hosts guarded, no timed jobs (0 held back so far) | — |

- **Web server (nginx) running**: nginx is up and will hand requests to the app.
- **App processes (puma)**: The Rails app server is running and can take requests.
- **Background jobs (sidekiq)**: Sidekiq registered itself in Redis, so emails, documents and reports will be processed.
- **Monitoring exporter**: Metrics will reach Grafana once monitoring is pointed at these servers.
- **Drill servers marked**: The drill's servers carry DR_DRILL_STACK: their error mail is tagged and they never page WhatsApp.
- **Drill cannot contact users**: On this drill copy no email, WhatsApp, SMS or push can reach a user, and no timed job runs; the count shows what was held back.

### Requests through the app

| Check | ip-10-0-1-28 | ip-10-0-2-254 | load-balancer |
|---|---|---|---|
| Database | ✅ HTTP 200 | ✅ HTTP 200 | — |
| Cache | ✅ HTTP 200 | ✅ HTTP 200 | — |
| Search reachable | ✅ HTTP 200 | ✅ HTTP 200 | — |
| Disk space | ✅ HTTP 200 | ✅ HTTP 200 | — |
| XIRR service | ✅ HTTP 200 | ✅ HTTP 200 | — |
| Public website (altconnects.com) | ✅ serving public/website | ✅ serving public/website | — |
| Website alias redirect (www.altconnects.com) | ✅ redirects to altconnects.com | ✅ redirects to altconnects.com | — |

- **Database**: A request went nginx → app → MySQL and back.
- **Cache**: The app's cache works. It lives in MySQL (solid_cache), so this does not test Redis; the sidekiq check does.
- **Search reachable**: Elasticsearch answered. It does not prove search has data; "Search index populated" does.
- **Disk space**: The root disk is under 95% full.
- **XIRR service**: The Python XIRR container that fund returns use is running.
- **Public website (altconnects.com)**: The public website is served.
- **Website alias redirect (www.altconnects.com)**: The www address redirects to the main website.

### What users do

| Check | ip-10-0-1-28 | ip-10-0-2-254 | load-balancer |
|---|---|---|---|
| Document files present | ✅ 30 of 30 files found in S3 (newest and older documents) | ✅ 30 of 30 files found in S3 (newest and older documents) | — |
| Background job ran | ✅ a job queued on 'default' ran in 3.0s | ✅ a job queued on 'default' ran in 3.0s | — |
| Sign-in page | ✅ HTTP 200 with the sign-in form | ✅ HTTP 200 with the sign-in form | — |
| Signed-in request | ✅ GET /funds.json as a signed-in user: HTTP 200 with JSON | ✅ GET /funds.json as a signed-in user: HTTP 200 with JSON | — |
| PDF generation | ✅ a Word file converted to PDF in 2.3s | ✅ a Word file converted to PDF in 2.4s | — |

- **Document files present**: The restored database's documents still have their files in S3 (the 20 newest and 10 older ones were looked up). Files are not part of the database restore.
- **Background job ran**: A job queued now was picked up and finished, so emails, documents and reports will be processed.
- **Sign-in page**: The sign-in screen renders with its form: layout, compiled assets and sessions work, not only the health endpoints.
- **Signed-in request**: A request as a real user (short-lived token, drill only) read their funds: authentication, permissions and JSON all work.
- **PDF generation**: LibreOffice turned a Word file into a PDF the way document generation does, so notices and statements can be generated.

### Data

| Check | ip-10-0-1-28 | ip-10-0-2-254 | load-balancer |
|---|---|---|---|
| Database schema up to date | ✅ ok | ✅ ok | — |
| Restored data age | ✅ newest users/documents row is 0.0h old | ✅ newest users/documents row is 0.0h old | — |
| Search index populated | ✅ rebuilt in the background: 29/29 indexes hold their records | ✅ rebuilt in the background: 29/29 indexes hold their records | — |
| File storage (S3) | ✅ docs.altx.com.staging | ✅ docs.altx.com.staging | — |

- **Database schema up to date**: Every migration newer than the backup was applied.
- **Restored data age**: Age of the newest user/document row: the data a real recovery would have lost.
- **Search index populated**: Search holds the restored records: either the background rebuild's progress (queued, running, finished) or, with no recent rebuild, every index counted against the database. An incomplete index is a warning: the data is complete, only some search results are missing.
- **File storage (S3)**: The app's own credentials can reach its document bucket.

### Database servers

| Check | ip-10-0-1-28 | ip-10-0-2-254 | load-balancer |
|---|---|---|---|
| Primary MySQL (10.0.3.54) | ✅ active | ✅ active | — |
| Search engine container | ✅ running | ✅ running | — |
| Redis container | ✅ running | ✅ running | — |
| Replica MySQL (10.0.4.243) | ✅ active | ✅ active | — |
| Replication round trip | ✅ Ok | ✅ Ok | — |

- **Primary MySQL (10.0.3.54)**: MySQL is running on the primary.
- **Search engine container**: The Elasticsearch container is running on the primary.
- **Redis container**: The Redis container (background job queue) is running on the primary.
- **Replica MySQL (10.0.4.243)**: MySQL is running on the replica.
- **Replication round trip**: A value written to the primary was read back from the replica seconds later.

### Backups

| Check | ip-10-0-1-28 | ip-10-0-2-254 | load-balancer |
|---|---|---|---|
| Primary not armed (drill) | ✅ drill: deliberately not armed — the live box still owns the backup chain | ✅ drill: deliberately not armed — the live box still owns the backup chain | — |
| Primary backup schedule | ✅ /etc/cron.d/irm-db-backup present, no old backup job | ✅ /etc/cron.d/irm-db-backup present, no old backup job | — |
| Backup checkpoint fresh | ✅ no checkpoint since the restore — the next backup bases on the newest full in S3 | ✅ no checkpoint since the restore — the next backup bases on the newest full in S3 | — |
| Replica not armed | ✅ ok | ✅ ok | — |
| Replica has no backup writer | ✅ no backup job outside the marker-gated schedule | ✅ no backup job outside the marker-gated schedule | — |

- **Primary not armed (drill)**: In a drill the rebuilt database must not write backups: the live box is still writing the same bucket. A real recovery arms it.
- **Primary backup schedule**: The timetable that runs backups exists, and no second, older backup job sits beside it.
- **Backup checkpoint fresh**: The first backup after the restore bases on the restored data, not on a checkpoint copied from the live box — so it can be restored.
- **Replica not armed**: The replica is not allowed to write backups (one writer per chain).
- **Replica has no backup writer**: No old backup job on the replica either — it can never write the backup chain.

## What the rebuild time does and does not include

- **Included:** Creating the servers · Installing the app · Restoring the database · Rebuilding search · Every check above
- **Not included:** Noticing the outage · Deciding to recover · Switching the domain to the new servers (DNS) and the minutes it takes to spread

So the time customers would actually wait is the rebuild time plus those three.

## Proof you can check yourself

| Claim | Evidence | How to check |
|---|---|---|
| Infrastructure provisioned in ap-south-2 | Pulumi update #0 — succeeded, 2026-11-08T09:44:29.000Z → 2026-11-08T09:46:59.000Z | `pulumi stack history --stack staging-ap-south-2` (server-side record, Pulumi console) |
| Database instances launched in ap-south-2 | i-015c31ccc8d53ab29 (10.0.4.243, launched 2026-11-08T09:44:50Z); i-02a68c62aba8caf8c (10.0.3.54, launched 2026-11-08T09:44:51Z) | CloudTrail `RunInstances` events in ap-south-2; `aws ec2 describe-instances --region ap-south-2` |
| Recovered stack endpoints | app servers 18.61.228.110, 18.61.201.28; DB primary 10.0.3.54, replica 10.0.4.243 | `pulumi stack output --stack staging-ap-south-2` |
| Application code deployed | commit `8f4f8ee32f803073bc6056e3f4a5ef94ae44990d` on branch `dr_drill_in_2026_11_08_1514` (pushed to origin) | `git log -1 8f4f8ee32f`; GitHub branch push timestamp |
| Data restored from real backups | source bucket `docs.altx.com.staging-backup-xtra` (full + incremental chain; keys named in the transcript) | `aws s3 ls s3://docs.altx.com.staging-backup-xtra/` — compare object timestamps against the run window |
| Recovered stack verified serving (step 9, re-run) | `recovery:verify` passed 32/32 on each app server and 4/4 load-balancer checks, 2026-11-08T10:04:54Z → 2026-11-08T10:05:46Z, after fix a63e7b9660 | `git show a63e7b9660`; local transcript docs/operations/dr/runs/dr_drill_in_2026_11_08_1514_reverify.log |
| Drill stack destroyed | `pulumi destroy` — 46 resources deleted, no errors, finished 2026-11-08T10:10:56Z | `pulumi stack history --stack staging-ap-south-2` |

## Words used in this report

| | |
|---|---|
| Drill | A rehearsal: the same steps as a real recovery, in a separate copy, with the live site untouched. |
| Rebuild time | From starting the recovery command to every check passing. |
| Recovery point (RPO) | The moment the data was recovered to (the newest backup); the minutes between it and the start of the recovery are the data a real recovery would lose. |
| Recovery time (RTO) | How long until users are served again. The figure here is the rebuild, from the recovery command to a verified stack; noticing the outage, deciding to recover and the DNS switch come on top. |
| Armed | A database allowed to write backups. Exactly one may, and in a drill none. |
| Full transcript | docs/operations/dr/runs/dr_drill_in_2026_11_08_1514_reverify.log: every command and its output. |

---
<sub>Generated 8 Nov 2026 10:05 UTC by hand: steps 1–8 from <code>rake aws:dr_drill</code> (15:14 run), step 9 re-run after a63e7b9660</sub>
