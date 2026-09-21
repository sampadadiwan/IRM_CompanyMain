# DR Review — Point 3: Secrets committed to git

**Status:** ⚠️ Partially applied per review decision:
- Exposure A (SSH keys `config/deploy_id_rsa*`): **left as-is by request** — files remain tracked; rotation checklist in §3.1 still recommended.
- Exposure B (MySQL root password): ✅ applied — both `packer.rake` literals replaced with credentials/ENV lookup that raises if unset (`ruby -c` passes). Rotation checklist in §3.2 pending (add MYSQL_ROOT_PASSWORD to credentials; rotate live DB root passwords).
- Exposure C (IRM-Infra state artifacts): ✅ applied — `pulumi.prod.export`, `output.json`, `tmp/*.json` untracked (files kept on disk); `.gitignore` extended with commented `*.export` / `output.json` / `tmp/` entries.

**New finding during apply:** `ses_bounce.py` and `ses_bounce_tracking.py` in IRM-Infra are **untracked** — the SES bounce-tracking code has never been committed and exists only on this machine. Should be committed (it contains no secrets) — folded into the SES automation point (Point 16).
**Repos affected:** `IRM` and `IRM-Infra`
**Severity:** Critical security exposure. Three independent issues, each meaning "anyone with read access to the repo (or any laptop/CI checkout of it, forever, via git history) holds live credentials or sensitive infrastructure state."

---

## 1. The three exposures

### Exposure A — plaintext SSH private key tracked in `IRM`

| | |
|---|---|
| Files | `config/deploy_id_rsa` (plaintext, `-----BEGIN OPENSSH PRIVATE KEY-----`, 411 bytes) and `config/deploy_id_rsa_enc` (2340 bytes) |
| Tracked? | Yes — both appear in `git ls-files` |
| Referenced in code? | **No** — `grep -r deploy_id_rsa` across the repo finds no usage in any `.rb`, deploy template, or Dockerfile |

Because nothing in the codebase reads it, this key is either dead (safe to delete) or used *out-of-band* — the classic candidates being a **GitHub deploy key** (so servers can `git clone` the repo during Capistrano deploys) or an entry in a server's `authorized_keys`. Either way it does not belong in git: the repo is cloned onto every developer laptop, every app server (`/home/ubuntu/IRM` via Capistrano), and any CI — each clone carries the private key, and git history preserves it even after deletion.

### Exposure B — MySQL root password hardcoded, baked into every AMI with remote root access

The password `Root1234$` is hardcoded twice in `lib/tasks/packer.rake` — once for dev (line 162), once for prod (line 176), both annotated `# Placeholder, update with actual password` (they never were):

```ruby
common_vars['mysql_root_password'] = "Root1234$" # Placeholder, update with actual prod password
```

It flows into the DB AMI bake, and the template does more than set a local password — `config/deploy/templates/packer/db_redis_es.ami.pkr.hcl:223-228`:

```hcl
"echo \"ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${var.mysql_root_password}';\" > /tmp/mysql-init.sql",
"echo \"CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH caching_sha2_password BY '${var.mysql_root_password}';\" >> /tmp/mysql-init.sql",
"echo \"GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;\" >> /tmp/mysql-init.sql",
```

So **every DB-Redis-ES AMI ever baked (dev and prod, IN and US) contains a `root@'%'` account — root reachable over the network — whose password sits in plain text in the git repo.** The only thing standing between that and the world is the security group on the DB instance (private subnet, 3306 restricted). One SG mistake — and recall Point 5's finding that `update_security_groups.py` mutates SGs out-of-band and `manage_ssh` tasks rewrite rules — makes this a full remote-root compromise.

### Exposure C — Pulumi state and live infrastructure details tracked in `IRM-Infra`

`git ls-files` in `IRM-Infra` shows these tracked non-source files:

| File | What it leaks |
|---|---|
| `pulumi.prod.export` (2313 lines) | Full state export of the production ap-south-2 stack: AWS account ID (`825199636520`), every resource ARN/ID, key pair name, a `passwordData` field, embedded runbook comments. Only one field in it is encrypted. |
| `output.json` | Live public/private IPs of app/DB/replica/observability instances and the DB security-group ID. Rewritten on every `pulumi up` by `outputs.py:44-48`, so it churns and re-commits. |
| `tmp/changes.json`, `tmp/dns-records.json`, `tmp/prev-state.json` | Route53 change artifacts from the dynamic provider — more IPs/hostnames. |

`.gitignore` is 3 lines (`*.pyc`, `venv/`, `.venv/`) — none of the above is ignored, so they keep coming back.

Also worth knowing: real state lives in Pulumi Cloud under a **personal** account (`owner: thimmaiah`) — the committed export is someone's manual backup of that. The instinct (have a state backup outside a personal SaaS account) is right; the location (git) is wrong. Moving state to an org-owned backend is Point 12; here we just stop leaking it.

## 2. How the exposures propagate — diagram

```mermaid
sequenceDiagram
    autonumber
    participant Git as git repos (IRM / IRM-Infra)
    participant Dev as Every clone (laptops, CI, app servers)
    participant Packer as packer:build_env
    participant AMI as DB-Redis-ES AMI (dev+prod, IN+US)
    participant DB as Running DB instance

    Note over Git: config/deploy_id_rsa (plaintext key)<br/>packer.rake: "Root1234$"<br/>pulumi.prod.export / output.json
    Git->>Dev: clone / pull — secrets on every machine, forever in history
    Git->>Packer: mysql_root_password = "Root1234$" (packer.rake:162,176)
    Packer->>AMI: bake: ALTER root@localhost + CREATE root@'%' GRANT ALL
    AMI->>DB: every instance launched from AMI
    Note over DB: remote root enabled,<br/>password known to anyone with repo read access.<br/>Only the SG stands in the way.
```

## 3. Proposed fix (what I'll do now, on approval)

### 3.1 IRM — remove the key, stop tracking it

1. `git rm --cached config/deploy_id_rsa config/deploy_id_rsa_enc` — untrack both (keeps local copies on disk so nothing you use manually breaks today).
2. Add to `.gitignore`: `config/deploy_id_rsa*`.
3. **Rotation checklist for you** (I can't see where the public key is authorized — this needs your access):
   - Check GitHub → IRM repo → Settings → Deploy keys; if this key is there, generate a fresh pair, install the new one, delete the old.
   - Check `~/.ssh/authorized_keys` for `ubuntu`/deploy users on the app/DB servers.
   - Until rotated, treat the key as compromised — untracking does **not** remove it from git history (see §3.4).

### 3.2 IRM — move the MySQL root password out of code

Replace both hardcoded literals in `packer.rake` with the same credentials-with-ENV-fallback pattern the rest of the codebase uses (`backup_db_xtra.rake:10-12`):

```ruby
# Root password for the baked DB AMI. Never hardcode: it ends up inside every
# AMI (including a root@'%' remote account — see db_redis_es.ami.pkr.hcl).
common_vars['mysql_root_password'] =
  Rails.application.credentials.dig(:MYSQL_ROOT_PASSWORD) ||
  ENV["MYSQL_ROOT_PASSWORD"] ||
  raise("MYSQL_ROOT_PASSWORD not set: add it to Rails credentials or export it before baking AMIs")
```

Failing loudly is deliberate — a bake without the password set should stop, not fall back to a known placeholder.

**Rotation checklist for you:**
   - Add `MYSQL_ROOT_PASSWORD` (a newly generated strong password) to Rails credentials for each env.
   - On **live** DB servers, the existing root password is the leaked one — rotate it in place: `ALTER USER 'root'@'localhost' IDENTIFIED BY '<new>'; ALTER USER 'root'@'%' IDENTIFIED BY '<new>';` (or better, see the follow-up below).
   - Next weekly AMI bake then picks up the new password from credentials.

**Follow-up question to answer before we harden further** (queued, not part of this change): does anything actually need `root@'%'`? `db:reset_replication` / the replica connect to the primary over the network — if they use root, we should create a scoped `replication`/`app_admin` user and drop remote root entirely. I'll check what user replication uses when we get to the restore-automation point (Point 11).

### 3.3 IRM-Infra — untrack state/output artifacts, fix .gitignore

1. `git rm --cached pulumi.prod.export output.json tmp/changes.json tmp/dns-records.json tmp/prev-state.json` (files stay on disk).
2. Extend `.gitignore` with: `*.export`, `output.json`, `tmp/`.
3. The state-backup need this export was serving gets solved properly in Point 12 (org-owned backend with versioning). If you want an interim offline backup, `pulumi stack export` to an encrypted S3 bucket — not git.

### 3.4 History purge — recommended, but your call (separate decision)

Untracking removes secrets from the **tip**; every clone of history still contains them. A real purge means rewriting history (`git filter-repo` on `config/deploy_id_rsa*` in IRM and `pulumi.prod.export` in IRM-Infra) plus a coordinated force-push and re-clone by everyone. Given both repos are private and the **rotation** steps above make the leaked values worthless, my recommendation is: **rotate first (mandatory), purge history opportunistically (nice-to-have)**. Rotation is what actually closes the hole.

## 4. Blast radius

- Untracking + `.gitignore` changes affect git only; no runtime behaviour changes.
- The `packer.rake` change makes the next AMI bake **fail fast** unless `MYSQL_ROOT_PASSWORD` is configured — that's intended, and it's the only behavioural change. Nothing running is touched.
- Live servers keep their current (leaked) passwords/keys until you run the rotation checklists — the code change alone does not rotate anything.

## 5. Verification steps (after applying)

1. `git ls-files | grep deploy_id_rsa` in IRM → empty; `git status` shows the files as untracked-ignored.
2. `git ls-files | grep -E "export|output.json|tmp/"` in IRM-Infra → empty.
3. `rake "packer:build_env[dev,in,db]"` without `MYSQL_ROOT_PASSWORD` set → aborts with the clear error (proves no silent fallback).
4. After you add the credential: bake proceeds and the AMI gets the new password.
