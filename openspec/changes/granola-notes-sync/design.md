# Granola Meeting Notes Sync — Design

> **Audience:** Engineering team.
> **Companion documents:** [Proposal](proposal.md) · [Spec](specs/granola-notes-sync/spec.md)

> **Planning phase — no code changes.** This document explains HOW the proposal will be built.
> Do not edit application code while writing it; implementation happens later, in the tasks phase.

> **Design, not code.** Diagrams and tables only; real class, table and path names appear inside
> them. User-facing behaviour and mockups live in the proposal, requirements in the spec.

---

## Contents

- [Overview](#overview)
- [Architecture](#architecture)
  - [Component Boundaries](#component-boundaries)
  - [Class Diagram](#class-diagram)
  - [Change Footprint](#change-footprint)
- [Data Model and States](#data-model-and-states)
  - [Data Model](#data-model)
  - [State Transitions](#state-transitions)
- [Behaviour](#behaviour)
  - [Pipeline / Flow](#pipeline--flow)
  - [Sequence Diagrams](#sequence-diagrams)
  - [Worked Examples](#worked-examples)
- [Key Components](#key-components)
  - [Decision Flows](#decision-flows)
- [Controllers and Routes](#controllers-and-routes)
- [Policy](#policy)
- [UI Changes](#ui-changes)
  - [At a glance](#at-a-glance)
  - [Journey 1: A partner connects Granola](#journey-1-a-partner-connects-granola)
  - [Journey 2: A meeting shows up on the investor (no clicks)](#journey-2-a-meeting-shows-up-on-the-investor-no-clicks)
  - [Journey 3: An admin reviews meetings CapHive couldn't place](#journey-3-an-admin-reviews-meetings-caphive-couldnt-place)
  - [Journey 4: Rescue an ignored meeting](#journey-4-rescue-an-ignored-meeting)
  - [Journey 5: The connection breaks](#journey-5-the-connection-breaks)
  - [Build notes (for implementers)](#build-notes-for-implementers)
- [Cross-cutting Concerns](#cross-cutting-concerns)
  - [Transactions and Queries](#transactions-and-queries)
  - [Exception Handling and Monitoring](#exception-handling-and-monitoring)
  - [Performance and Security](#performance-and-security)
- [Design Decisions](#design-decisions)
- [Testing](#testing)
- [Risks and Open Questions](#risks-and-open-questions)

---

## Overview

A sidekiq-cron job polls Granola's read-only REST API (`https://public-api.granola.ai/v1`) for each
connected API key. Every returned meeting is upserted into a `granola_meetings` row, unique per
entity by Granola note id. A matcher resolves attendee emails to `InvestorAccess` contacts, and the
meeting is then auto-filed as `Note`s, parked for review, or ignored. This follows the deal-ingest
pipeline (`AgentIngestedEmail` → `DealStakeholderMatcher` → `DealIngestProcessor` → `WarehouseItem`)
without its LLM parse step: Granola already produces structured attendees and a summary.

---

## Architecture

### Component Boundaries

The feature is split into six boundaries. Each arrow crossing a boundary is the **only** way the
two sides talk. Nothing reaches around a boundary: for example, controllers never call Granola
directly except to verify a key on Connect.

```mermaid
flowchart LR
    subgraph EXT["External"]
        GAPI[["Granola public API<br/>read-only, API key"]]
    end
    subgraph UI["UI boundary"]
        UIC["Connection panels<br/>profile + entity settings"]
        UII["Granola Inbox"]
        UIN["Investor Notes tab"]
    end
    subgraph SCHED["Scheduling boundary"]
        CRON["sidekiq-cron"]
        JOBS["Sync / Rematch jobs"]
    end
    subgraph SYNC["Sync boundary (core/granola)"]
        ORCH["Sync orchestration<br/>page, upsert, route"]
        MATCH["Matching"]
        FILE["Filing"]
    end
    subgraph INTEG["Integration boundary"]
        CLIENT["Granola client"]
    end
    subgraph CRM["CapHive CRM boundary (existing)"]
        NOTES[("Notes")]
        INV[("Investors + contacts")]
        USERS[("Fund users")]
    end
    subgraph ALERT["Notification boundary (existing)"]
        NOTIF["Notifier: email + in-app"]
    end

    UIC -- "connect / sync now / disconnect" --> SCHED
    UIC -- "verify key" --> INTEG
    UII -- "file / discard / rematch" --> SYNC
    CRON -- "every 15 min" --> JOBS
    JOBS -- "run pass per connection" --> ORCH
    ORCH -- "list + get notes" --> CLIENT
    CLIENT -- "HTTPS" --> GAPI
    ORCH --> MATCH
    MATCH -- "read emails" --> INV
    MATCH -- "read emails" --> USERS
    ORCH --> FILE
    FILE -- "create / refresh notes" --> NOTES
    NOTES -- "last interaction date" --> INV
    UIN -- "reads" --> NOTES
    ORCH -- "connection failed" --> NOTIF
```

| From → To | Contract | Direction rule |
|---|---|---|
| UI → Scheduling | Enqueue a sync for one connection | UI never runs a sync inline |
| UI → Integration | Verify a key once, on Connect | The only UI call to Granola |
| UI → Sync | File, discard or re-match one meeting | Always through the filer or processor, never writing notes itself |
| Scheduling → Sync | Run one pass for one connection | One pass at a time per connection |
| Sync → Integration | List changed notes, fetch one note | Only the client knows URLs, auth and rate limits |
| Sync → CRM | Read contacts and users; create and refresh notes | Only the filer writes notes. The matcher is read-only |
| Sync → Notification | Connection needs attention | Raised only by the connection's failure handling |

### Class Diagram

Classes grouped by the boundaries above. Arrows between groups are the boundary contracts.

```mermaid
classDiagram
    direction LR

    namespace UI_Boundary {
        class GranolaConnectionsController {
            <<Controller>>
            +create()
            +update()
            +destroy()
            +sync()
        }
        class GranolaMeetingsController {
            <<Controller>>
            +index()
            +file()
            +discard()
            +rematch()
            +rematch_all()
        }
        class GranolaConnectionPolicy {
            <<Policy>>
        }
        class GranolaMeetingPolicy {
            <<Policy>>
        }
    }

    namespace Scheduling_Boundary {
        class GranolaSyncAllJob {
            <<Job, cron 15 min>>
            +perform()
        }
        class GranolaSyncJob {
            <<Job, queue low>>
            +perform(connection_id)
        }
        class GranolaRematchJob {
            <<Job, queue low>>
            +perform(meeting_ids, user_id)
        }
    }

    namespace Sync_Boundary {
        class GranolaSyncService {
            <<Service>>
            +call(connection)
        }
        class GranolaMeetingProcessor {
            <<Service>>
            +call(meeting)
        }
        class GranolaAttendeeMatcher {
            <<Service>>
            +call(meeting) MatchResult
        }
        class MatchResult {
            <<Value>>
            tier
            investor_ids
            touch_points
        }
        class GranolaNoteFiler {
            <<Service>>
            +call(meeting, investor_ids, filed_by)
            +refresh(meeting)
        }
        class GranolaConnection {
            <<Model>>
            kind
            status
            +claim_sync()
            +record_success(max_updated_at)
            +record_failure(error)
        }
        class GranolaMeeting {
            <<Model>>
            status
            +upsert_from_api(connection, payload)$
            +mark_needs_review(candidate_ids, tier)
            +mark_ignored(tier)
            +resolve(user, resolution)
        }
    }

    namespace Integration_Boundary {
        class GranolaClient {
            <<Service, HTTP>>
            +list_notes(updated_after, cursor)
            +get_note(id)
            +verify()
        }
    }

    namespace CRM_Boundary_existing {
        class Note {
            <<Model, modified>>
            +granola_detached() bool
            +update_investor()
        }
        class Investor {
            <<Model>>
            last_interaction_date
        }
        class InvestorAccess {
            <<Model>>
            email
        }
    }

    namespace Notification_Boundary_existing {
        class GranolaConnectionFailedNotifier {
            <<BaseNotifier>>
        }
    }

    GranolaConnectionsController ..> GranolaSyncJob : enqueue
    GranolaConnectionsController ..> GranolaClient : verify key
    GranolaMeetingsController --> GranolaNoteFiler : file
    GranolaMeetingsController --> GranolaMeetingProcessor : rematch
    GranolaMeetingsController ..> GranolaRematchJob : rematch all
    GranolaSyncAllJob ..> GranolaSyncJob : per connection
    GranolaSyncJob --> GranolaSyncService
    GranolaRematchJob --> GranolaMeetingProcessor
    GranolaSyncService --> GranolaClient : list, get
    GranolaSyncService --> GranolaMeeting : upsert
    GranolaSyncService --> GranolaMeetingProcessor
    GranolaMeetingProcessor --> GranolaAttendeeMatcher
    GranolaAttendeeMatcher --> MatchResult
    GranolaAttendeeMatcher ..> InvestorAccess : read
    GranolaMeetingProcessor --> GranolaNoteFiler
    GranolaNoteFiler --> Note : create, refresh
    Note --> Investor : last interaction
    Note --> InvestorAccess : touch point
    GranolaConnection "1" o-- "*" GranolaMeeting
    GranolaMeeting "1" o-- "*" Note
    GranolaConnection ..> GranolaConnectionFailedNotifier : on failure
```

### Change Footprint

All new code lives in one new sub-domain, `app/packs/core/granola/`. Existing code only gains small
hooks. Green is new, amber is modified, grey is reused unchanged. Exact file paths are per task in
[tasks.md](tasks.md).

```mermaid
flowchart LR
    classDef new fill:#d4edda,stroke:#2e7d32,color:#000
    classDef mod fill:#fff3cd,stroke:#b8860b,color:#000
    classDef reuse fill:#eceff1,stroke:#90a4ae,color:#000

    DB[("2 new tables<br/>+ 2 columns on notes")]:::new
    Pack["core/granola pack<br/>models, services, jobs,<br/>controllers, policies, views, notifier"]:::new
    Tests["4 Cucumber features,<br/>Granola stub, factories"]:::new
    Guide["User guide"]:::new

    NoteM["Note model<br/>meeting link, edited check,<br/>last-interaction rule"]:::mod
    NoteV["Notes list + note card"]:::mod
    Screens["Profile, entity settings,<br/>Investors menu"]:::mod
    Config["Routes, sidekiq cron"]:::mod

    Pattern["Deal-ingest pattern<br/>(status + review inbox shape)"]:::reuse
    Enc["Rails encryption"]:::reuse
    Notif["Standard notifier"]:::reuse
    Libs["Faraday, Redcarpet,<br/>base job"]:::reuse
    Touch["Touch-point check,<br/>note visibility rule"]:::reuse
    Mock["@sync-http WebMock switch"]:::reuse

    Pack --> DB
    Pack --> NoteM
    NoteM --> NoteV
    Screens --> Pack
    Config --> Pack
    Pack -.follows.-> Pattern
    Pack --> Enc
    Pack --> Notif
    Pack --> Libs
    NoteM --> Touch
    Tests --> Mock
    Tests -.-> Pack
    Guide -.-> Screens
```

---

## Data Model and States

### Data Model

Two new tables, `granola_connections` and `granola_meetings`, plus two new columns on the existing
`notes` table. Existing tables are shown only with the columns this feature reads or adds.

```mermaid
erDiagram
    entities ||--o{ granola_connections : "has"
    entities ||--o{ granola_meetings : "has"
    users ||--o{ granola_connections : "owns (kind=user)"
    users ||--o{ granola_connections : "connected_by"
    granola_connections |o--o{ granola_meetings : "imported (nullify on disconnect)"
    users |o--o{ granola_meetings : "resolved author / resolved_by"
    granola_meetings |o--o{ notes : "filed as (one per investor)"
    investors ||--o{ notes : "owner (owner_type=Investor)"
    investors ||--o{ investor_accesses : "contacts"
    investor_accesses |o--o{ notes : "touch_point"

    granola_connections {
        bigint id PK
        bigint entity_id FK
        string kind "user | workspace"
        bigint user_id FK "NULL for workspace"
        bigint connected_by_id FK
        string scope_key UK "user:ID | workspace, unique with entity_id"
        text api_key "encrypted"
        string api_key_last4
        string status "connected | needs_attention"
        datetime cursor_at "next updated_after"
        datetime sync_started_at "single-flight claim"
        datetime last_synced_at
        datetime last_success_at
        datetime failure_notified_at
        string last_error
        json last_sync_stats "filed, review, ignored"
    }

    granola_meetings {
        bigint id PK
        bigint entity_id FK
        bigint granola_connection_id FK "nullable"
        string granola_note_id UK "unique with entity_id"
        string title
        datetime meeting_at "calendar start, else created_at"
        string owner_email
        string owner_name
        json attendees "name, email"
        text summary_markdown "NULL while ignored"
        text private_notes_markdown "per-user connections only"
        string web_url
        datetime granola_updated_at
        string status "needs_review | filed | ignored | discarded"
        string match_tier "exact | domain | none | internal"
        json candidate_investor_ids
        json filed_investor_ids "never re-create after delete"
        bigint user_id FK "resolved author, drives visibility"
        bigint resolved_by_id FK
        datetime resolved_at
    }

    notes {
        bigint id PK
        bigint owner_id "Investor"
        bigint touch_point_id FK "InvestorAccess"
        date on "meeting date"
        string tags "granola"
        bigint granola_meeting_id FK "NEW, nullify"
        string granola_digest "NEW, SHA256 of details as last synced"
    }

    investors {
        bigint id PK
        date last_interaction_date "max(current, meeting date)"
    }

    investor_accesses {
        bigint id PK
        bigint entity_id
        bigint investor_id
        string email "matched against attendees"
    }
```

**Indexes:** unique `granola_connections[entity_id, scope_key]`; unique
`granola_meetings[entity_id, granola_note_id]`; `granola_meetings[entity_id, status, meeting_at]`
for the inbox; `notes[granola_meeting_id]`.

**Column rationale** (non-obvious columns only):

**`granola_connections`**

| Column | Why |
|---|---|
| `kind` + `user_id` | One table for both connection kinds (proposal decision 1). `user_id` NULL means workspace |
| `scope_key` | MySQL has no partial unique index. `"user:<id>"` / `"workspace"` with a unique index on `[entity_id, scope_key]` enforces "one per user, one workspace per entity" at the DB level |
| `connected_by_id` | Who gets failure alerts, and the fallback author for workspace notes |
| `api_key` (encrypted) + `api_key_last4` | Secret is never decrypted for display. Last 4 characters render the masked key |
| `cursor_at` | Granola `updated_after`. Only advanced after a fully successful pass |
| `sync_started_at` | Single-flight claim so cron and "Sync now" can't run the same connection twice |
| `last_success_at` / `failure_notified_at` | Drive the 24h prolonged-outage alert and stop repeat alerts |

**`granola_meetings`**

| Column | Why |
|---|---|
| `[entity_id, granola_note_id]` unique | Duplicate guard across a partner's key and the workspace key (spec: "Same meeting via two connections") |
| `summary_markdown` NULL while ignored | Unmatched meetings (portfolio co, personal) never store content. Re-match re-fetches from Granola |
| `private_notes_markdown` | Written only when the source connection is `kind=user`. A later workspace pass never blanks it |
| `filed_investor_ids` | `Note` is **not** soft-deleted (`Trackable` is commented out in `note.rb:2`). This list is how "deleted note not recreated" is enforced: refresh only updates notes that still exist, and never creates for an investor already listed |
| `user_id` | Resolved author, used for the note's `user` and for inbox visibility, mirroring `NotePolicy::Scope` |

**`notes`**

| Column | Why |
|---|---|
| `granola_meeting_id` | Links each filed note back to its meeting; one meeting can produce several notes (one per investor) |
| `granola_digest` | SHA256 of `details` HTML as the sync last wrote it; a mismatch means a user edited it (see `granola_detached?`) |

**Changes to existing models** (`Note`):

- New association to `GranolaMeeting` (optional).
- New derived predicate `granola_detached?` (see *Note sync ownership* above).
- `update_investor`: only for Granola notes on an `Investor` owner,
  `last_interaction_date` becomes `max(current, on)` instead of `created_at`. Manual notes and
  `DealInvestor` owners keep today's behaviour.

**FAQ**

| Question | Answer |
|---|---|
| Why a digest instead of an `edited_by_user` flag? | A flag set in the notes controller misses edits from every other path (API, MCP tools, console). Comparing digests catches all of them without a callback on `Note`. The digest is taken after save, because ActionText normalises the HTML |

### State Transitions

#### Meeting status lifecycle

```mermaid
stateDiagram-v2
    [*] --> filed: exact match, one investor
    [*] --> needs_review: exact match, 2+ investors / domain match
    [*] --> ignored: no match / internal only
    ignored --> filed: re-match finds one investor
    ignored --> needs_review: re-match finds several / domain
    needs_review --> filed: reviewer files (1..N investors)
    needs_review --> discarded: reviewer discards
    filed --> filed: Granola update refreshes non-detached notes
    discarded --> [*]
```

#### Connection status lifecycle

```mermaid
stateDiagram-v2
    [*] --> connected: Connect with a key Granola accepts
    connected --> syncing: claim_sync (cron or Sync now)
    syncing --> connected: pass completes, cursor advanced
    syncing --> connected: transient error, retried, cursor kept
    syncing --> needs_attention: 401 or 403 from Granola
    needs_attention --> connected: owner reconnects with a valid key
    connected --> [*]: Disconnect (row deleted, notes kept)
    needs_attention --> [*]: Disconnect
    note right of syncing
        not a stored status - it is the
        sync_started_at claim (stale after 30 min)
    end note
```

#### Note sync ownership

```mermaid
stateDiagram-v2
    [*] --> synced: filer creates note, digest stored
    synced --> synced: Granola update, refresh rewrites and re-digests
    synced --> detached: user edits details in CapHive
    detached --> detached: Granola update ignored
    synced --> deleted: user deletes note
    detached --> deleted: user deletes note
    deleted --> [*]: never recreated (investor stays in filed_investor_ids)
```

`detached` is derived, not stored: `granola_digest` differs from the digest of the current `details`
HTML.

---

## Behaviour

### Pipeline / Flow

```mermaid
flowchart TD
    Cron(["sidekiq-cron<br/>every 15 minutes"]) --> AllJob["GranolaSyncAllJob#perform<br/>GranolaConnection.syncable.find_each"]
    SyncNow(["Sync now / Connect<br/>(GranolaConnectionsController)"]) --> Job
    AllJob -->|"perform_later(id) per connection"| Job["GranolaSyncJob#perform(connection_id)<br/>queue :low"]
    Job --> Svc["GranolaSyncService.call(connection)"]
    Svc --> Claim{"connection.claim_sync!<br/>claim acquired?"}
    Claim -->|no| Stop(["no-op: another sync running"])
    Claim -->|yes| List["GranolaClient#list_notes<br/>updated_after: cursor_at − 1 min<br/>30 per page, follow cursor"]
    List --> Skip{"meeting unchanged<br/>(same granola_updated_at)<br/>or discarded?"}
    Skip -->|yes| Next
    Skip -->|no| Get["GranolaClient#get_note(id)"]
    Get --> Upsert["GranolaMeeting.upsert_from_api!<br/>unique entity_id + granola_note_id"]
    Upsert --> Proc["GranolaMeetingProcessor.call(meeting)"]
    Proc --> Filed{"already filed?"}
    Filed -->|yes| Refresh["GranolaNoteFiler.refresh<br/>update non-detached notes only"]
    Filed -->|no| Match["GranolaAttendeeMatcher.call<br/>→ tier, investor_ids, touch_points"]
    Match -->|":exact, 1 investor"| File["GranolaNoteFiler.call<br/>Note.create! per investor<br/>status filed"]
    Match -->|":exact, 2+ investors<br/>or :domain"| Review["mark_needs_review!<br/>candidate_investor_ids"]
    Match -->|":none / :internal"| Ignore["mark_ignored!<br/>drops summary + private notes"]
    Refresh --> Next
    File --> Next
    Review --> Next
    Ignore --> Next
    Next{"more notes<br/>or pages?"} -->|yes| Skip
    Next -->|no| Success["connection.record_success!<br/>advance cursor_at"]
    List -. "AuthError / RetryableError" .-> Failure["connection.record_failure!<br/>needs_attention + notify, or retry_on"]

    Review --> Inbox[["Granola Inbox<br/>GranolaMeetingsController"]]
    Ignore --> Inbox
    Inbox -->|"#file (filed_by: current_user)"| File
    Inbox -->|"#discard → resolve!"| Discarded(["status discarded"])
    Inbox -->|"#rematch → get_note → upsert"| Proc
```

### Sequence Diagrams

Happy path: a scheduled sync auto-files a single-investor meeting.

```mermaid
sequenceDiagram
    participant Cron as sidekiq-cron
    participant AllJob as GranolaSyncAllJob
    participant Job as GranolaSyncJob
    participant Svc as GranolaSyncService
    participant API as Granola API
    participant GM as GranolaMeeting
    participant Proc as GranolaMeetingProcessor
    participant Match as GranolaAttendeeMatcher
    participant Filer as GranolaNoteFiler
    participant NoteRec as Note (model)

    Cron->>AllJob: every 15 minutes
    AllJob->>Job: perform_later(connection.id) per syncable connection
    Job->>Svc: call(connection)
    Svc->>Svc: connection.claim_sync!
    Svc->>API: GET /v1/notes?updated_after=cursor&page_size=30
    API-->>Svc: [{id: not_abc, updated_at}], hasMore=false
    Svc->>API: GET /v1/notes/not_abc
    API-->>Svc: note (attendees, calendar_event, summary_markdown)
    Svc->>GM: upsert_from_api!(connection, payload)
    Svc->>Proc: call(meeting)
    Proc->>Match: call(meeting)
    Match-->>Proc: tier=:exact, investor_ids=[12], touch_points={12=>InvestorAccess 88}
    Proc->>Filer: call(meeting, investor_ids: [12])
    Filer->>NoteRec: create!(owner: Investor 12, on:, touch_point:, details:, tags: "granola")
    NoteRec->>NoteRec: after_save update_investor (last_interaction_date = max(current, on))
    Filer->>GM: mark_filed!(filed_investor_ids: [12])
    Svc->>Svc: connection.record_success!(max updated_at)
```

Error and edge path: the key is revoked mid-sync, and an ambiguous meeting is parked.

```mermaid
sequenceDiagram
    participant Job as GranolaSyncJob
    participant Svc as GranolaSyncService
    participant API as Granola API
    participant Conn as GranolaConnection
    participant Proc as GranolaMeetingProcessor
    participant GM as GranolaMeeting
    participant Notifier as GranolaConnectionFailedNotifier

    Job->>Svc: call(connection)
    Svc->>API: GET /v1/notes/not_xyz
    API-->>Svc: note, attendees match Investor 12 and Investor 40
    Svc->>Proc: call(meeting)
    Proc->>GM: mark_needs_review!(candidate_investor_ids: [12, 40])
    Svc->>API: GET /v1/notes?cursor=...
    API-->>Svc: 401 Unauthorized
    Svc->>Conn: record_failure!(GranolaClient::AuthError)
    Conn->>Conn: status = needs_attention, cursor_at unchanged
    Conn->>Notifier: with(record: conn, entity_id:).deliver_later(conn.connected_by)
    Note over Svc,Conn: Retryable errors (429/5xx/timeout) re-raise instead.<br/>ActiveJob retry_on handles them. Notifier fires only once<br/>last_success_at is more than 24h old.
```

Connecting a key: verify it first, then start the 90-day backfill.

```mermaid
sequenceDiagram
    actor Raj as Raj (fund employee)
    participant Ctrl as GranolaConnectionsController
    participant Pol as GranolaConnectionPolicy
    participant API as Granola API
    participant Conn as GranolaConnection
    participant Job as GranolaSyncJob

    Raj->>Ctrl: POST /granola_connections (kind user, api_key)
    Ctrl->>Pol: create?
    Pol-->>Ctrl: true (own per-user connection)
    Ctrl->>API: GET /v1/notes?page_size=1 (verify)
    alt key rejected (401/403)
        API-->>Ctrl: 401
        Ctrl-->>Raj: inline error, nothing saved
    else key accepted
        API-->>Ctrl: 200
        Ctrl->>Conn: save (encrypted key, last4, cursor_at = 90 days ago)
        Ctrl->>Job: perform_later(connection.id)
        Ctrl-->>Raj: Connected, backfill started
    end
```

Review inbox: a fund admin files an ambiguous meeting to two investors.

```mermaid
sequenceDiagram
    actor Priya as Priya (fund admin)
    participant Ctrl as GranolaMeetingsController
    participant Pol as GranolaMeetingPolicy
    participant Filer as GranolaNoteFiler
    participant GM as GranolaMeeting
    participant NoteRec as Note (model)
    participant Inv as Investor

    Priya->>Ctrl: PATCH /granola_meetings/7/file (investor_ids 12, 40)
    Ctrl->>Pol: file?
    Pol-->>Ctrl: true (admin, same entity)
    Ctrl->>Filer: call(meeting, investor_ids, filed_by Priya)
    Filer->>GM: lock
    Filer->>Inv: where(entity_id, id in 12, 40)
    alt an id is outside the entity
        Filer-->>Ctrl: RecordNotFound
        Ctrl-->>Priya: flash Investor not found, nothing filed
    else both found
        loop each investor not in filed_investor_ids
            Filer->>NoteRec: create! (owner, on, touch_point, tag granola)
            NoteRec->>Inv: update_investor (last_interaction_date = max)
            Filer->>NoteRec: store granola_digest
        end
        Filer->>GM: status filed, filed_investor_ids, resolve(Priya, filed)
        Ctrl-->>Priya: turbo_stream remove row
    end
```

Granola changes a meeting that was already filed, and one of its notes was edited in CapHive.

```mermaid
sequenceDiagram
    participant Svc as GranolaSyncService
    participant GM as GranolaMeeting
    participant Proc as GranolaMeetingProcessor
    participant Filer as GranolaNoteFiler
    participant N1 as Note on Acme Pension
    participant N2 as Note on Acme SPV

    Svc->>GM: upsert (new summary, granola_updated_at)
    Svc->>Proc: call(meeting)
    Proc->>Filer: refresh(meeting) because status is filed
    Filer->>N1: granola_detached?
    N1-->>Filer: false (digest matches)
    Filer->>N1: update details, on, touch_point, new digest
    Filer->>N2: granola_detached?
    N2-->>Filer: true (user edited)
    Note over Filer,N2: skipped, shows Edited in CapHive line
    Note over Filer: deleted notes are absent from meeting.notes and never recreated
```

Re-match an ignored meeting after a contact is added.

```mermaid
sequenceDiagram
    actor Priya as Priya (fund admin)
    participant Ctrl as GranolaMeetingsController
    participant GM as GranolaMeeting
    participant API as Granola API
    participant Proc as GranolaMeetingProcessor

    Priya->>Ctrl: PATCH /granola_meetings/9/rematch
    alt meeting.granola_connection is gone
        Ctrl-->>Priya: flash reconnect to re-match
    else connection present
        Ctrl->>API: GET /v1/notes/not_9 (ignored rows hold no summary)
        API-->>Ctrl: note
        Ctrl->>GM: upsert_from_api
        Ctrl->>Proc: call(meeting)
        Proc-->>Ctrl: filed / needs_review / still ignored
        Ctrl-->>Priya: turbo_stream remove or replace row
    end
```

### Worked Examples

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error (exception) case. IDs are
referenced from tasks.md and Cucumber scenario names.

**Shared setup:**

| Record | Name | Key data |
|---|---|---|
| Entity | Alpha Capital | — |
| Fund admin | Priya | priya@alphacap.com |
| Fund employee | Raj | raj@alphacap.com |
| Investor + contact | Acme Pension / Jane Doe | jane@acmepension.com |
| Investor + contact | Acme Co-invest SPV / Mark Lee | mark@acmepension.com |
| Investor + contact | Bluewater FO / Ann Roy | ann@bluewater.co |

#### Happy Path

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| H1 | Connect a per-user key | Raj has no connection; Granola accepts his key ending `1a2b` | Raj clicks Connect on his profile | Connected; key shown as `grn_••••••••1a2b`; 90-day backfill queued | Valid per-user key | connections |
| H2 | Auto-file a one-investor meeting | Raj connected; "Q3 check-in" on 28/09/2026 with raj@ and jane@acmepension.com; summary "Reaffirmed Fund III"; private notes "Pushy on fees" | Sync runs | Acme Pension gets 1 note: author Raj, dated 28/09/2026, with Jane Doe, tag granola, title + summary + "Private notes" heading, Open in Granola link; meeting `filed`; last interaction 28/09/2026 | New meeting picked up · Single investor exact match is auto-filed · Note fields · Private notes via per-user connection · Author with per-user connection · Recent meeting | sync |
| H3 | Re-sync is idempotent | H2 has run | Sync runs again, meeting unchanged | Still exactly 1 note; last-sync time updated; no Granola fetch for that meeting | Nothing new | sync |
| H4 | Review, then file to two investors | "Co-invest sync" with jane@ and mark@acmepension.com | Sync runs; Priya ticks both candidates and clicks File | After sync: `needs_review` with 2 candidates, no notes. After File: 1 note on each, row gone, resolved by Priya | Multiple investors go to review · File to several investors | inbox |
| H5 | Domain match filed to one investor | "Intro call" with tom@bluewater.co (not a contact) | Sync runs; Priya picks Bluewater FO and clicks File | After sync: `needs_review`, candidate Bluewater FO. After File: 1 note on Bluewater FO | Domain-only match goes to review · File to one investor | inbox |
| H6 | Unedited note follows Granola | H2's note untouched in CapHive | Summary changes in Granola to "Reaffirmed Fund III and IV"; sync runs | Note shows the new summary and a new digest | Unedited note refreshed | updates |

#### Edge Cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E1 | Same meeting via two keys | Workspace (Priya) and Raj's key both return the H2 meeting | Both syncs run | One meeting record, one note, author Raj, private notes present | Same meeting via two connections | sync |
| E2 | Internal-only meeting | Meeting with only raj@ and priya@alphacap.com | Sync runs | `ignored`; no note; no summary stored | Internal-only meeting is ignored | sync |
| E3 | Stranger on a public domain | Meeting with stranger@gmail.com; a contact also uses gmail.com | Sync runs | `ignored`; no candidate from the gmail.com overlap | Public email domains never domain-match · No match is ignored | sync |
| E4 | Old meeting doesn't rewind history | Acme Pension last interaction 20/09/2026 | A meeting from 01/08/2026 is filed | Last interaction stays 20/09/2026 | Backfilled old meeting | sync |
| E5 | Workspace author fallback | Workspace connected by Priya; meeting owner advisor@consult.io has no login; attendee jane@ | Workspace sync runs | Note on Acme Pension authored by Priya, with "Imported from Granola (owner: advisor@consult.io)"; no private notes | Author with workspace connection | sync |
| E6 | Edited note is protected | H2's note edited by Priya to add "Follow up in Nov" | Summary changes in Granola; sync runs | Note unchanged; shows "Edited in CapHive — later Granola changes are not applied" | Edited note preserved | updates |
| E7 | Deleted note stays deleted | Priya deleted H2's note | Meeting changes in Granola; sync runs | No note recreated on Acme Pension | Deleted note not recreated | updates |
| E8 | Discard sticks | A meeting in the Inbox | Priya clicks Discard; later the meeting changes in Granola | Row gone and never returns | Discard | inbox |
| E9 | Re-match after adding a contact | Meeting with sam@startup.io is `ignored` | Priya adds sam@startup.io to Bluewater FO, clicks Re-match | Meeting filed on Bluewater FO | Re-match after adding a contact | inbox |
| E10 | Non-admin sees only own meetings | Inbox holds Raj's meeting and one resolved to Priya | Raj opens the Inbox | Only Raj's meeting listed; Priya sees both | Inbox visibility follows note visibility | inbox |
| E11 | Disconnect keeps notes | H2 has run | Raj clicks Disconnect and confirms | Connection and key gone; Acme Pension's note remains | Disconnect keeps imported notes | connections |

#### Error Cases

| # | Scenario | Given | When | Then (what the user sees, who is alerted) | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| X1 | Invalid key on Connect | Granola rejects `grn_bad` | Raj clicks Connect | Inline "Granola rejected this API key. Check it and try again."; nothing saved; no alert | Rejected key | connections |
| X2 | Non-admin tries workspace | Raj is not a fund admin | Raj opens entity settings; posts a workspace connection directly | Section not shown; request denied | Workspace connection restricted to fund admins | connections |
| X3 | Second per-user connection | Raj already connected | Raj submits another key as a new connection | Refused; offered Disconnect or reconnect instead | Only one connection of each kind | connections |
| X4 | Key revoked mid-sync | Raj connected; Granola now returns 401 | Sync runs; later Raj enters a valid key | Needs attention with reason; cursor unchanged; Raj gets email + in-app alert; cron skips it. After reconnect: connected, resumes from the old cursor | Revoked key · Reconnect resumes | updates |
| X5 | Granola down for a day | Every call returns 503 | Syncs retry for 24 hours | No alert until 24h without success, then exactly one to Raj; none again until a success and a new failure | Prolonged outage | updates |
| X6 | Filing to another fund's investor | An investor id from a different entity | Priya submits File with it | "Investor not found"; nothing filed | Cross-entity investor rejected | inbox |
| X7 | Re-match with connection gone | Raj disconnected; his ignored meeting remains | Priya clicks Re-match | "The Granola connection that imported this meeting has been disconnected — reconnect to re-match" | — (design-only guard) | inbox |

**FAQ**

| Question | Answer |
|---|---|
| What is the retry behaviour for a 500 from Granola? | Retried with backoff, 5 attempts. The cursor does not move, so the next cron pass covers it too. The connector is alerted only after 24h without success (X5) |

---

## Key Components

Responsibilities are summarised here. The collaborations are in the Class Diagram and the timing is
in the Sequence Diagrams.

| Component | Responsibility | Notes |
|---|---|---|
| `GranolaClient` | The only class that talks HTTP to `public-api.granola.ai/v1` | Bearer key; 10s/30s timeouts; 0.2s spacing between calls (Granola allows 5 req/s); raises `AuthError` (401/403), `RetryableError` (429 honouring Retry-After, 5xx, timeout), `Error` |
| `GranolaSyncService` | One incremental pass for one connection | Claim, then page through `updated_after`, batch-lookup existing meetings per page, skip unchanged or discarded, fetch, upsert, process. The cursor advances only if every meeting in the pass succeeded |
| `GranolaAttendeeMatcher` | Attendee emails → `MatchResult` | Deterministic, no LLM. Decision flow below |
| `GranolaMeetingProcessor` | Routes one meeting by status and match | Discarded: no-op. Filed: refresh. Needs review: update candidates only, never auto-file. New or ignored: match and route |
| `GranolaNoteFiler` | Creates and refreshes notes, transactionally | Decision flow below. Markdown goes through the existing Redcarpet setup with `escape_html` |
| `GranolaSyncAllJob` / `GranolaSyncJob` | Scheduling and retries | Cron registered next to `SchedulerPollingJob` in `config/initializers/sidekiq.rb`; the pass runs inside `Chewy.strategy(:atomic)` |
| `GranolaRematchJob` | Bulk "Re-match all" | Up to 500 most recent ignored meetings in the user's scope |

### Decision Flows

#### Matching

```mermaid
flowchart TD
    Start(["attendee emails<br/>normalised, blanks dropped"]) --> Internal["remove emails of users<br/>in this entity"]
    Internal --> AnyExt{"any external<br/>attendees left?"}
    AnyExt -->|no| TInternal(["tier internal → ignored"])
    AnyExt -->|yes| Exact["InvestorAccess in entity<br/>with email in externals"]
    Exact --> HowMany{"distinct investors<br/>matched exactly"}
    HowMany -->|1| TExact1(["tier exact, 1 investor → auto-file<br/>touch point = first matching contact"])
    HowMany -->|2 or more| TExactN(["tier exact, many → needs_review"])
    HowMany -->|0| Domains["external domains minus<br/>PUBLIC_EMAIL_DOMAINS"]
    Domains --> DomHit{"any contact in entity<br/>on those domains?"}
    DomHit -->|yes| TDomain(["tier domain → needs_review"])
    DomHit -->|no| TNone(["tier none → ignored"])
```

#### Filing

```mermaid
flowchart TD
    In(["GranolaNoteFiler.call<br/>meeting, investor_ids, filed_by"]) --> Lock["lock meeting row<br/>open transaction"]
    Lock --> Load{"all investor_ids<br/>in meeting's entity?"}
    Load -->|no| Deny(["RecordNotFound, rollback"])
    Load -->|yes| Each["for each investor"]
    Each --> Already{"in filed_investor_ids?"}
    Already -->|yes| Skip["skip: filed before,<br/>maybe deleted since"]
    Already -->|no| Author{"connection kind"}
    Author -->|user| AUser["author = connection user<br/>include private notes"]
    Author -->|workspace| AWs{"owner email is a<br/>user in entity?"}
    AWs -->|yes| AOwner["author = that user"]
    AWs -->|no| AFallback["author = connected_by<br/>add Imported from Granola line"]
    AUser --> Create
    AOwner --> Create
    AFallback --> Create
    Create["create Note on investor<br/>on = meeting date, tag granola,<br/>touch point, then store digest"] --> Mark
    Skip --> Mark
    Mark["meeting status filed<br/>append filed_investor_ids<br/>resolve if filed_by present"] --> Done(["commit"])
```

**FAQ**

| Question | Answer |
|---|---|
| Why not reuse `DealIngestProcessor` / `WarehouseItem`? | `WarehouseItem.deal_id` is NOT NULL and points at `AgentIngestedEmail`, and the deal flow starts with an LLM parse this feature does not need. We copy the shape (string status, resolve, candidate ids), not the tables |
| Why no LLM? | Granola already gives structured attendee emails. A guess is the one failure this feature must avoid |
| Why poll instead of webhooks? | Granola has no webhooks. `updated_after` is its documented incremental mechanism |
| Why never auto-file a meeting already in review? | A reviewer may be looking at it. Moving it out of the inbox silently would be surprising |

---

## Controllers and Routes

All routes go in `config/routes/core.rb`.

| Verb and path | Action | Does | Responds with |
|---|---|---|---|
| `POST /granola_connections` | `create` | authorize, verify key with Granola, save, queue backfill | redirect back; inline error if rejected |
| `PATCH /granola_connections/:id` | `update` | reconnect with a new key; keeps `cursor_at` | redirect back |
| `DELETE /granola_connections/:id` | `destroy` | delete connection; meetings nullified, notes kept | redirect back (after `turbo-confirm`) |
| `POST /granola_connections/:id/sync` | `sync` | queue `GranolaSyncJob` | "Sync started" flash |
| `GET /granola_meetings?status=` | `index` | inbox tabs `needs_review` / `ignored`, paginated, candidate names batch-loaded | HTML |
| `PATCH /granola_meetings/:id/file` | `file` | `GranolaNoteFiler.call` with `filed_by` | turbo_stream remove row |
| `PATCH /granola_meetings/:id/discard` | `discard` | `resolve!(discarded)` | turbo_stream remove row |
| `PATCH /granola_meetings/:id/rematch` | `rematch` | re-fetch, upsert, process | turbo_stream remove or replace row |
| `POST /granola_meetings/rematch_all` | `rematch_all` | queue `GranolaRematchJob` | flash |

---

## Policy

**Access control:**

| Role | Connections | Granola Inbox |
|---|---|---|
| Fund admin (`company_admin`) | own per-user connection; the entity's workspace connection | every meeting in the entity |
| Fund employee (non-admin, `enable_investors`) | own per-user connection only | meetings whose resolved author is them |
| Investor / investor advisor | none | none |
| Support (`support?`) | as fund admin | as fund admin |

```mermaid
flowchart TD
    Req(["request on a GranolaMeeting"]) --> Ent{"meeting.entity_id ==<br/>user.entity_id?"}
    Ent -->|no| No(["deny"])
    Ent -->|yes| Inv{"enable_investors and<br/>not investor advisor?"}
    Inv -->|no| No
    Inv -->|yes| Adm{"company_admin<br/>or support?"}
    Adm -->|yes| Yes(["allow"])
    Adm -->|no| Own{"meeting.user_id ==<br/>user.id?"}
    Own -->|yes| Yes
    Own -->|no| No
```

- `GranolaMeetingPolicy::Scope` applies the same rule as a query, mirroring `NotePolicy::Scope`.
- `GranolaConnectionPolicy`: a `kind=user` connection is allowed only when `record.user_id == user.id`.
  `kind=workspace` uses the same admin test as `EntityPolicy#update?` (`entity_policy.rb:56-57`).
- **Multi-tenancy:** every query scopes by `entity_id`: connections, meetings, matcher contacts and
  users, and the filer's investor load. An investor id from another entity raises instead of filing.

---

## UI Changes

This section walks through the UI as the people using it will. It starts with where Granola shows
up, then covers each journey with its screen and steps, and ends with notes for whoever builds it.
User-facing rules (messages, validation) are in the [proposal](proposal.md#behavior-rules).

### At a glance

| Where in CapHive | Today | After this change | Who sees it |
|---|---|---|---|
| My profile | No Granola | New **Granola** panel to connect your own account | Any fund employee, on their own profile |
| Entity settings | No Granola | New **Granola workspace** panel to connect the fund's shared account | Fund admins |
| Investors menu | — | New **Granola Inbox (3)** link, shown once the fund has a connection | Fund admins and employees |
| Granola Inbox | Doesn't exist | **New page** listing meetings CapHive couldn't place | Admins see all; employees see their own meetings |
| Investor → Notes tab | Manual notes only | Granola meetings appear as notes, tagged `granola`, with a link back | Same as notes today |
| Email + bell alert | — | "Granola connection needs attention" | The person who connected the key |

```mermaid
flowchart LR
    J1["Journey 1<br/>Connect"] --> J2["Journey 2<br/>Meetings arrive<br/>on investors"]
    J2 --> J3["Journey 3<br/>Review what<br/>couldn't be placed"]
    J3 --> J4["Journey 4<br/>Rescue an<br/>ignored meeting"]
    J1 -.-> J5["Journey 5<br/>Connection breaks"]
    J5 -.-> J1
```

### Journey 1: A partner connects Granola

```
My profile
┌──────────────────────────────────────────────────────┐
│  Granola                                              │
│  ① Status:  ○ Not connected                           │
│  ② API key: [ grn_...                          ]      │
│     Where do I find my key? (Granola → Settings → API)│
│  ③ ⚠ Filed meetings, including your private notes,    │
│     become visible to fund admins.                    │
│  ④ [ Connect ]                                        │
└──────────────────────────────────────────────────────┘
          after Connect succeeds
┌──────────────────────────────────────────────────────┐
│  Granola                                              │
│  ① Status:  ● Connected                               │
│  ② API key: grn_••••••••1a2b                          │
│  ⑤ Last sync: 30/09/2026 14:15 — 3 filed, 1 to review │
│  ⑥ [ Sync now ]   ⑦ [ Disconnect ]                    │
└──────────────────────────────────────────────────────┘
```

| Step | The user… | They see |
|---|---|---|
| 1 | Opens **My profile** and finds the Granola panel | ① Not connected, ② empty key field, ③ the visibility warning |
| 2 | Pastes their key and clicks ④ **Connect** | Wrong key: the error appears under the field and nothing is saved. Right key: the panel switches to Connected |
| 3 | Waits a few minutes | ⑤ fills in once the first import (last 90 days) finishes. Their meetings start appearing on investors (Journey 2) |
| 4 | Optionally clicks ⑥ **Sync now** | "Sync started". ⑤ updates on the next visit |
| 5 | Optionally clicks ⑦ **Disconnect** and confirms | Back to Not connected. Notes already imported stay |

A fund admin connects the shared workspace from **Entity settings → Granola workspace**. It's the
same panel and the same steps. Only admins see it.

### Journey 2: A meeting shows up on the investor (no clicks)

```
Investor: Acme Pension → Notes tab
┌──────────────────────────────────────────────────────┐
│  28/09/2026 · Q3 check-in — Acme Pension  ① [granola] │
│  By Raj Menon · ② With: Jane Doe                      │
│                                                      │
│  ③ • Reaffirmed commitment to Fund III               │
│     • Asked for DPI by vintage                       │
│     Private notes                                    │
│     • Pushy on fees                                  │
│                                                      │
│  ④ Open in Granola ↗                                 │
│  ⑤ Edited in CapHive — later Granola changes are not  │
│     applied                          (only if edited) │
└──────────────────────────────────────────────────────┘
```

| Step | What happens | What the user sees |
|---|---|---|
| 1 | The partner finishes a call with jane@acmepension.com. Granola writes the summary | Nothing in CapHive yet |
| 2 | Within ~15 minutes CapHive picks it up and recognises Jane as Acme Pension's contact | A new note on Acme Pension: ① tag, ② the contact met, ③ summary (+ private notes for a personal key), ④ link back |
| 3 | The summary is edited later in Granola | The note updates on its own, unless someone edited it in CapHive, in which case it stays as is and shows ⑤ |

### Journey 3: An admin reviews meetings CapHive couldn't place

```
Investors menu → Granola Inbox (2)
┌────────────────────────────────────────────────────────────────────┐
│  Granola Inbox            ① [ To review (2) ]  [ Ignored ]          │
│                                                                    │
│  ② Co-invest sync · 28/09/2026 · owner Raj Menon       ↗ Granola    │
│     Attendees: jane@acmepension.com, mark@acmepension.com          │
│  ③ Why here: attendees belong to 2 investors                        │
│  ④ ☐ Acme Pension   ☐ Acme Co-invest SPV                            │
│  ⑤ Other investor: [ search…            ▾ ]                         │
│  ⑥ [ File ] (greyed until an investor is ticked)   ⑦ [ Discard ]    │
│ ────────────────────────────────────────────────────────────────── │
│  Intro call · 27/09/2026 · owner Priya Shah            ↗ Granola    │
│  Why here: email domain match only (tom@bluewater.co)              │
│  ☐ Bluewater FO                                                    │
│  [ File ]   [ Discard ]                                            │
└────────────────────────────────────────────────────────────────────┘
```

| Step | The user… | They see |
|---|---|---|
| 1 | Clicks **Granola Inbox (2)** in the Investors menu | ① the To review tab. Admins see every meeting; employees only their own |
| 2 | Reads a row | ② meeting and owner, ③ why CapHive didn't file it, ④ the investors it might belong to |
| 3 | Ticks one or more investors (or searches ⑤ for a different one) | ⑥ File becomes clickable |
| 4 | Clicks **File** | The row disappears, the count drops to (1), and each ticked investor gets the note from Journey 2 |
| 5 | Or clicks ⑦ **Discard** | The row disappears for good, even if the meeting changes in Granola later |

### Journey 4: Rescue an ignored meeting

| Step | The user… | They see |
|---|---|---|
| 1 | Opens the **Ignored** tab | Meetings where no attendee is a known investor contact (title, date, attendees only, with no summary kept) |
| 2 | Spots a real LP meeting with sam@startup.io, who isn't a contact yet | — |
| 3 | Adds sam@startup.io as a stakeholder of Bluewater FO | The usual stakeholder screen |
| 4 | Returns and clicks **Re-match** on that row | The row leaves the Ignored tab and the note appears on Bluewater FO. If it now matches several investors, it moves to **To review** instead |

### Journey 5: The connection breaks

```mermaid
stateDiagram-v2
    direction LR
    NotConnected: Not connected
    Connected: Connected (green)
    NeedsAttention: Needs attention (red, reason shown)
    [*] --> NotConnected
    NotConnected --> Connected: user pastes a valid key
    Connected --> NeedsAttention: Granola rejects the key during a sync
    NeedsAttention --> Connected: user pastes a new valid key
    Connected --> NotConnected: user disconnects
    NeedsAttention --> NotConnected: user disconnects
```

| Step | What happens | What the user sees |
|---|---|---|
| 1 | The partner revokes the key in Granola, or it expires | — |
| 2 | The next sync is rejected | Email and bell alert: "Granola connection needs attention", linking to the panel |
| 3 | They open the panel | Red **Needs attention**, the reason, and a key field |
| 4 | They paste a new key | Back to Connected, catching up from where it stopped. Nothing is lost |

### Build notes (for implementers)

| Interaction | Screen update |
|---|---|
| File / Discard | Row removed in place (Turbo Stream) and badge count decremented, with no page reload |
| Re-match | Row replaced in place, or removed if filed |
| Sync now | Flash only. The last-sync line refreshes on the next load |
| Connect / Disconnect | Normal form submit, redirect back to the panel |

- Each inbox row is a Turbo Frame. The "Other investor" picker reuses the existing investor select.
  Disabling File until a tick needs no new Stimulus controller if an existing one fits; otherwise
  add a tiny one.
- The key is never rendered in full: `grn_••••••••` plus the last four characters.
- The Inbox link appears only once the fund has a connection, so funds that don't use Granola never
  see an empty feature.

---

## Cross-cutting Concerns

### Transactions and Queries

**Queries added/changed:**

| What is read | When | N+1 risk | How it stays cheap |
|---|---|---|---|
| Connections that are allowed to sync | Every cron tick | No | Read in batches |
| Meetings already stored for one page of Granola results | Each page (≤30 meetings) | Avoided | One lookup per page by Granola id, not one per meeting |
| Fund users whose email is among the attendees | Each meeting | No | One indexed lookup per meeting |
| Investor contacts whose email is among the attendees | Each meeting | No | One indexed lookup per meeting |
| Investor contacts on the attendees' email domains | Each meeting, only when there is no exact match | No | Scans only this fund's contacts (thousands, not millions) |
| Investors chosen for filing | Each file action | No | One lookup, restricted to the fund |
| Candidate investor names in the inbox | Inbox page load | **Yes**, one per row | Collect every candidate on the page and load names once |
| Meeting link and "edited" flag on each note | Investor Notes tab | **Yes**, one per note | Preload the meeting with the notes; note text is already preloaded |

**Transaction boundaries:**

| Operation | In a transaction? | Why |
|---|---|---|
| Filing a meeting (create notes, update last interaction, mark meeting filed) | Yes, with the meeting row locked | A partial file would leave the meeting in review with some notes already created |
| Refreshing a filed meeting's notes | Yes, per meeting | Note text and stored fingerprint must change together |
| Storing a meeting fetched from Granola | No | A single row. The unique Granola-id index settles a race between two connections |
| Advancing a connection's cursor | No | A single row, written only after the whole pass succeeds |

**FAQ**

| Question | Answer |
|---|---|
| Could two syncs race and double-file? | Each connection runs one pass at a time. Two connections returning the same meeting meet at the unique Granola-id index, and the filer re-checks filed investors under the row lock |

### Exception Handling and Monitoring

| Failure scenario | Who is alerted | Channel | Detail |
|---|---|---|---|
| Invalid key on Connect | User | In-app (inline form error) | "Granola rejected this API key. Check it and try again." Nothing saved |
| Key revoked or expired during sync | User (connector) | Email + in-app | Connection goes to *needs attention* and stops syncing. Uses the standard notifier pattern (same as the KPI import-failed alert) |
| Granola rate-limits, errors or times out | Nobody at first | — | Retried automatically. The last error is shown on the connection panel |
| No successful sync for 24h | User (connector) | Email + in-app | Sent once, and reset on the next success |
| One meeting fails to process | Support | Existing error tracking | Logged with the Granola id. The rest of the pass continues and the cursor stays put, so the meeting is retried |
| Filing to an investor from another fund | User | In-app (flash) | "Investor not found". Nothing filed |
| Re-match when the connection is gone | User | In-app (flash) | "The Granola connection that imported this meeting has been disconnected — reconnect to re-match" |

**FAQ**

| Question | Answer |
|---|---|
| Could one bad meeting block everything behind it? | The rest of the pass still processes, but the cursor stays put, so the bad meeting is retried each pass. After 24h with no advance, the connector is alerted |

### Performance and Security

- Volume per connection is small: tens of meetings per week per partner. The backfill is the peak
  (about 90 days of meetings, ≤5 req/s).
- All work runs on the `:low` queue. Sync is single-flight per connection.
- There are no queries on large tables. The inbox and notes list preloads are covered above.
- **Secret:** the API key is encrypted with AR encryption, never rendered (only `api_key_last4`),
  and filtered from logs (already covered by the `_key` pattern in `filter_parameter_logging.rb:7`).
- **Tenant isolation:** entity scoping on every query. The filer loads investors by `entity_id`.
  Policies mirror `NotePolicy` and `EntityPolicy`.
- **Content minimisation:** ignored meetings store no summary or private notes. Transcripts are
  never fetched.
- **HTML injection:** Granola markdown is rendered with `escape_html: true`. ActionText sanitises on
  top of that.
- **Private notes exposure:** documented in the proposal FAQ and shown as a warning before connecting.

---

## Design Decisions

1. **One `granola_connections` table with a `kind` column.** The alternative was entity-settings
   columns for the workspace key plus a user table for personal keys. That was rejected because it
   means two sync paths, two failure paths and two UIs for one behaviour.
2. **Meeting row unique per entity, not per connection.** The alternative was per connection with
   dedupe at note level. That was rejected because the same meeting via two keys would show twice in
   the inbox and race to file.
3. **Deterministic email matching, no LLM.** The alternative was reusing `DealStakeholderMatcher` /
   an LLM. That was rejected because attendee emails are exact data, and a guess is the failure this
   feature must avoid.
4. **Ignored meetings drop their content.** The alternative was keeping the summary so re-match is
   offline. That was rejected because it would store partners' non-investor meeting content (the
   leak risk from the proposal). Re-match does one GET instead.
5. **Edit detection by digest.** The alternative was a flag set in the controller. That was rejected
   because it misses non-controller edit paths (see Model FAQ).
6. **`filed_investor_ids` instead of soft-delete.** `Note` isn't paranoid, and turning `Trackable` back
   on for notes is out of scope. The alternative was re-creating any missing note, which was rejected
   because it resurrects notes users deleted on purpose.
7. **Encrypt the key despite plain-text precedent.** `entity_settings.whatsapp_token` and similar
   columns are unencrypted. A Granola key reads a partner's entire meeting history, so encryption is
   worth being the first `encrypts` in the app. The infrastructure is already configured.

---

## Testing

Cucumber only. Every scenario is tagged `@sync-http`, so WebMock stubs Granola while local services
keep working. One fixture-driven Granola stub helper goes under `features/support/`, and jobs run
inline in steps. Existing entity, investor, contact and login steps are reused, and new steps go in
one Granola step file. The scenario-to-file mapping is the **Feature** column of the Worked Examples.

---

## Risks and Open Questions

- A Granola API change (fields, auth, rate limits) could break the sync. Mitigation: the client is
  isolated in one class, the failure alerts surface it within 24h, and the Cucumber fixtures pin
  the contract we rely on.
- Contacts sharing one email across investors send more meetings to review. Mitigation: that's
  intended. The inbox badge keeps the queue visible.
- Digest false positives if ActionText re-serialises HTML differently after a Rails upgrade.
  Mitigation: at worst, notes stop auto-updating (the safe direction). They are never overwritten.
- Workspace-only funds get no private notes. That's accepted and stated in the proposal.

| # | Question | Current Thinking | Status |
|---|---|---|---|
| 1 | Does `@sync-http` WebMock allow the other HTTP a scenario needs? | Resolved: `webmock_toggle.rb` sets `disable_net_connect!(allow_localhost: true)`, so local Elasticsearch/Redis keep working; only Granola needs stubbing | Resolved |
| 2 | Is `api_key` filtered from logs? | Resolved: `filter_parameter_logging.rb:7` filters `_key` (and `secret`, `token`), so `api_key` is already covered | Resolved |
| 3 | Exact Granola error body/status for a plan without API access | Treat as `AuthError` (403). Refine the message once seen | Deferred |
