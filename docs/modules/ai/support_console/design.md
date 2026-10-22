# Support Console — Claude Code for the support team

**Status:** built (2026-10-16) as the OpenSpec change [`support-console`](../../../../openspec/changes/archive/2026-10-22-support-console/design.md), which supersedes this brainstorm where they differ (Claude Code CLI rather than an SDK, local mode, the staging writer rule). User guide: [Support Console](../../../user_guides/support_console_user_guide.md). This replaces the Troubleshooting Sandbox
design on the `troubleshooting-sandbox` branch (`docs/modules/ai/framework/troubleshooting_sandbox.md`
there), keeping what it proved and dropping most of its machinery.

**Branch:** `support-assistant-brainstorm`

## The idea in one paragraph

A user with the `:support` role opens **Support Console** in the CapHive app, picks one of the clients
they are mapped to, and asks a question such as *"why is Investor Y's closing balance zero in Fund X?"*.
The question goes to **Claude Code** running on a small, separate machine. Claude reads **the code of
the deployed revision** and queries **the production read replica** through a read-only account, then
answers in business terms, citing `file:line` and the rows behind the answer. The support user never
logs into the machine, and the machine never sees a production secret.

## The picture

```mermaid
flowchart LR
    s(["Support user<br/>(:support role)"]) -->|"normal CapHive login"| ui

    subgraph app["CapHive app servers"]
        ui["/support_console<br/>client picker + chat"]
        job["SupportTurnJob<br/>Sidekiq queue: support_console"]
        ui --> job
    end

    subgraph box["Support machine · one per environment · no production secrets"]
        relay["Relay service<br/>(HTTP, HMAC-signed calls only)"]
        cc["Claude Code<br/>claude -p (headless CLI)"]
        code[("/code/&lt;rev&gt;<br/>git archive of the deployed code")]
        tool["db MCP tool (stdio)<br/>SELECT only · 30s · row cap"]
        hook["PreToolUse hook<br/>client check on every query"]
        tx[("/clients/&lt;entity_id&gt;/<br/>transcripts · 90 days")]
        relay --> cc
        cc -->|"Read / Grep / Glob"| code
        cc --> hook --> tool
        cc --- tx
    end

    job -->|"POST turn, stream back"| relay
    tool -->|"TCP 3306 · support_ro"| replica[("Production<br/>read replica")]
    cc -->|"subscription token"| anthropic["Anthropic API<br/>(Claude)"]
    primary[("Primary DB")] -.->|"replication"| replica
```

What reaches what:

| From | To | How | Why only this |
|---|---|---|---|
| App servers | Support machine | One inbound port, from the app servers' security group, HMAC-signed requests | Rails has already decided *who* may ask about *which* client before anything is sent |
| Support machine | Replica | TCP 3306 to the replica's security group, account `'support_ro'@'<machine IP>'` | The login is read-only and works only from the machine's own address. On production the task refuses to open the rule if the writer shares the replica's group. Staging has no replica, so there writer and replica are one server (E24) |
| Support machine | Anthropic API | A Claude subscription token (`claude setup-token`) from Parameter Store, in the relay's environment only | Claude's read tools are denied `/etc` and `/proc`, so it cannot read the token back. Client rows go to Anthropic, not just AWS. `SUPPORT_CONSOLE_AUTH=bedrock` switches back to Bedrock (instance role, the two Claude models) |
| Support user | Support machine | **Nothing** | No SSM, no shell, so no human can bypass the controls below |

## How a question is answered

```mermaid
sequenceDiagram
    autonumber
    actor S as Support user
    participant UI as /support_console
    participant J as SupportTurnJob
    participant R as Relay
    participant C as Claude Code
    participant H as PreToolUse hook
    participant DB as Replica

    S->>UI: pick client (only mapped clients listed), ask question
    UI->>UI: agent_chat_session (chattable = Entity) + user message
    UI->>J: enqueue turn
    J->>R: POST /sessions/:id/turns {entity_id, user_id, question}
    R->>C: query(question, resume: session, cwd: /clients/<entity_id>, client brief)
    loop until it has an answer
        C->>C: Grep / Read the deployed code
        C->>H: mcp__db__query(sql)
        alt query not scoped to this client
            H-->>C: blocked, with the reason
        else scoped
            H->>DB: SELECT ... (30s timeout, row cap)
            DB-->>C: rows (+ "data as of N s ago" if lagging)
        end
    end
    C-->>R: streamed messages
    R-->>J: NDJSON stream
    J-->>UI: update message + Turbo broadcast
    UI-->>S: answer, with file:line and the rows behind it
```

**Worked example.** A support user mapped to *Golden Angels* (entity 18) asks why investor *Ravi K* shows a
zero closing balance in *Fund I*. Claude greps for how the closing balance is computed, reads that method,
sees it sums `account_entries` of a given name for the commitment, queries
`SELECT name, SUM(amount_cents) FROM account_entries WHERE entity_id = 18 AND capital_commitment_id = …
GROUP BY name`, finds the closing-balance entry missing for the latest `reporting_date`, and answers:
*"The closing balance is zero because the Q3 account entries were never generated for this commitment —
the fund's Q3 allocation run excluded it (`file:line`). Re-running the allocation for Q3 would fix it."*
It explains the fix; it can't apply it.

## Who can ask about which client

The client picker uses the same rule as every admin page for a support user
(`app/packs/core/base/policies/base_scope.rb`, `EntityPolicy::Scope#resolve_admin`):

```mermaid
flowchart TD
    u["Support user"] --> m{"SupportClientMapping<br/>for this user + client?"}
    m -->|no| x["Not listed"]
    m -->|yes| e{"enabled, and<br/>end_date not passed?"}
    e -->|no| x
    e -->|yes| p{"client has<br/>enable_support permission?"}
    p -->|no| x
    p -->|yes| ok["Listed · a session can start"]
```

A session belongs to exactly one (support user, client) pair. Switching client starts a new session.

## Keeping a session to one client

The account itself reads **every** client — MySQL has no row-level security. In v1, keeping Claude on
the chosen client is **best effort**, in layers:

```mermaid
flowchart LR
    q["Claude writes SQL"] --> p1["1 · System prompt<br/>names the client, its funds,<br/>'filter entity_id = 18'"]
    p1 --> p2["2 · PreToolUse hook<br/>blocks queries on entity_id tables<br/>without entity_id = 18,<br/>or naming another entity_id"]
    p2 --> run["Runs on the replica"]
    run --> p3["3 · Result check<br/>flags rows whose entity_id ≠ 18"]
    p3 --> p4["4 · Audit log<br/>every query, user, client, row count"]
```

| Layer | Stops an honest model drifting | Stops a model steered by data it read (prompt injection) |
|---|---|---|
| 1 · System prompt | mostly | no |
| 2 · Hook | yes, for simple queries | partly — `... entity_id = 18 OR 1=1` contains the filter |
| 3 · Result check | detects afterwards | detects afterwards |
| 4 · Audit log | detects afterwards | detects afterwards |
| **v2 · Tenant views** | yes | **yes** |

The realistic v1 failure is an answer that mixes two clients' figures; layers 1–2 prevent it, and 3–4
make any cross-client read findable. Tables without `entity_id` (`audits`, `versions`, `workflow_*`, …)
are scoped only by the prompt (through their parent row), so for them the audit log is the safeguard.

### v2: tenant views, a real boundary

```mermaid
flowchart LR
    subgraph v1["v1"]
        a1["support_ro"] -->|"SELECT on IRM.*"| t1[("base tables<br/>every client")]
    end
    subgraph v2["v2"]
        a2["support_ro"] -->|"SELECT on support.* only"| v[("support.capital_calls =<br/>SELECT * FROM IRM.capital_calls<br/>WHERE entity_id = support_tenant()")]
        v --> t2[("base tables")]
    end
    v1 ==>|"grants change + view generator;<br/>same machine, same tool"| v2
```

The db tool runs `SET @support_tenant = <client>` before each query and rejects any SQL containing `@`
or `:=`. Whatever SQL Claude writes, it can only reach views already filtered to one client. Costs: views
are DDL, so they are created on the primary and replicate; they must be regenerated after migrations
(MySQL fixes a view's column list at creation); and `entity_id = support_tenant()` must still use the
index on large tables — **spike with `EXPLAIN` on `account_entries` first**.

## The replica, not the primary

- **The app barely uses the replica.** `ApplicationRecord` reads and writes the primary
  (`connects_to … reading: :primary`); only `UserReplica` reads the replica, for
  `ReplicationHealthJob`. Support queries don't compete with app users.
- **The account exists on both, the route does not.** MySQL replicates accounts from the primary, so
  `support_ro` is created there — as `'support_ro'@'<machine IP>'` with `SELECT, SHOW VIEW` only — but
  the security group rule is on the replica's group, and on production the task refuses it when the
  writer is in that group too.
- **The tool refuses to run off a replica.** On connect it checks `@@read_only = 1` and
  `@@super_read_only = 1`; if either is off, it is pointed at the wrong host and answers nothing.
- **Lag is shown, not hidden.** It reads `Seconds_Behind_Source`; above ~60 s, results carry "data as of
  N seconds ago".
- **Load is capped.** `MAX_USER_CONNECTIONS 4`, `MAX_QUERIES_PER_HOUR 20000`, 30 s `max_execution_time`,
  and the Sidekiq queue's concurrency of 3.

## The machine

| On it | Not on it |
|---|---|
| Claude Code (the `claude` CLI, run headless), the relay, the db MCP tool and hook | Production credentials, master keys, `.env` |
| `/code/<rev>`: `git archive` of the deployed revision, ~41 MB, no gems | Gems, Ruby app runtime — the code is read, never run |
| `support_ro` password, readable only by the tool's user | A shell for humans; Bash for Claude |
| `/clients/<entity_id>/` transcripts, encrypted volume, 90-day retention | Elasticsearch, document files, Redis, jobs |

Claude Code's settings for the session:

| Allowed | Denied |
|---|---|
| `Read`, `Grep`, `Glob` over `/code/<rev>` and the client folder | `Bash`, `Write`, `Edit`, `WebFetch`, `WebSearch` |
| `mcp__db__query`, `mcp__db__describe_tables` | anything outside those two folders |

The code bundle is built from an allow-list (`SupportConsoleCodeArchive::INCLUDED`): `app/`, `lib/`,
`config/` without credentials, keys or deploy files, the schema and migrations, the product docs
(`docs/user_guides`, `docs/modules`, `docs/technical`, `docs/release_notes`) and the repo's `CLAUDE.md`.
Ops docs, incident write-ups, skills and anything not listed stay out. A generated support brief (what this is, read-only, cite
`file:line` and rows, aggregate in SQL rather than pulling thousands of rows) is added to the system
prompt with the client.

**One machine per environment.** `production.in` and `production.us` get separate machines, replicas,
parameters, relay secrets and budgets. They are in **one AWS account** (`825199636520`), so each
environment's Bedrock budget would see the combined IN + US spend. On the default subscription token both
use the same Claude plan and its usage limit; with Bedrock's global inference profiles, neither would be
pinned to its own region either.

## Inside the app

| Piece | Built from |
|---|---|
| `/support_console` page: client picker + chat | The existing agent chat UI; picker from `resolve_admin` |
| Session and messages | `agent_chat_sessions` (`chattable` = the `Entity`) and `agent_chat_messages`. `support_agent_id` is `NOT NULL`, so a "Support Console" `SupportAgent` record owns these sessions |
| `SupportTurnJob` | Same shape as `ChatStreamJob`: stream chunks into the message, broadcast with Turbo. Own queue, concurrency 3 |
| Stop button | `DELETE /sessions/:id/turns/current` → relay aborts the query |
| Previous investigations | Listed per client from `agent_chat_sessions`; Claude can also read them from the client folder |

The relay accepts one turn per session at a time, so a resumed session is never written by two turns.

## What it can and cannot answer

| Can | Cannot |
|---|---|
| "Why does this screen show X?" — reads the code that computes it, queries its inputs | "Does this fix work?" — nothing can write |
| "Who changed this, and when?" — `audits`, `versions` | Run app code (`rails runner`, a report builder, an allocation) |
| "Why did this email not go out?" — flags, workflow state, `noticed_notifications` | Search (no Elasticsearch), open document files |
| "What will happen if the GP does Y?" — from the code path | Anything about another client |

Where an answer needs logic it can't run (waterfalls, allocations), it shows the formula from
`file:line`, its inputs from the replica, and the result, so the support user can check it.

## What changed from the Troubleshooting Sandbox

```mermaid
flowchart LR
    subgraph old["Troubleshooting Sandbox (Sep 2026)"]
        o1["Ops user in a terminal<br/>via SSM + IAM + MFA"]
        o2["Docker image, 1.4 GB bundle<br/>with gems, RAILS_ENV=sandbox"]
        o3["Runs app code<br/>read-only boot guard"]
        o4["Every client visible"]
    end
    subgraph new["Support Console"]
        n1["Support user in the app<br/>their CapHive login"]
        n2["Small machine, 41 MB code<br/>archive, no gems"]
        n3["Reads code, runs SQL"]
        n4["Mapped clients only;<br/>one client per session"]
    end
    o1 --> n1
    o2 --> n2
    o3 --> n3
    o4 --> n4
```

Kept from that branch: the SELECT-only account and its provisioning rake task
(`sandbox:provision_db_access`, already applied on staging as `sandbox_ro`), the replica checks, the
code archive published on deploy, the Bedrock decision and the "cite `file:line` and rows" brief.

Dropped: SSM access and per-person IAM, the Docker image with gems, `RAILS_ENV=sandbox` and the boot
guard, `rails runner`, Bash.

## Open items

- **Subscription terms.** The machine signs in with one person's Claude subscription and serves the whole
  support team (decided 2026-10-19, owner's call). Its usage limit is shared with that person's own use.
- **Token renewal.** A `setup-token` token lasts a year; `machine_check` warns 30 days ahead.
- **Is the replica also the DR standby?** If so, heavy support queries could delay failover; the caps
  above keep it small, but it changes the stakes.
- **v2 spike:** does `entity_id = support_tenant()` use the index on `account_entries`?
- **Prompt-injection review** of the result check and audit log before rollout.
- **Code archive on `main`:** the publish-on-deploy hook lives on `troubleshooting-sandbox`; it needs
  porting, trimmed to `git archive` only (no `vendor/cache`).
