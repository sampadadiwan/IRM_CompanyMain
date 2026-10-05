# NDA Module 3: GP Status Dashboard — Design

> **Audience:** The engineering team implementing this feature.
> **Companion documents:** [Proposal](proposal.md) · [Spec](specs/) · [LLD](lld.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document explains how to implement the feature.
> Implementation happens in the tasks phase.

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
  - [Sequence Diagrams](#sequence-diagrams)
  - [Worked Examples](#worked-examples)
- [Key Components](#key-components)
- [Controllers and Routes](#controllers-and-routes)
- [Policy](#policy)
- [UI Changes](#ui-changes)
  - [Journey 1: GP views NDA status summary in modal](#journey-1-gp-views-nda-status-summary-in-modal)
  - [Journey 2: GP opens dedicated dashboard and manages exemptions](#journey-2-gp-opens-dedicated-dashboard-and-manages-exemptions)
  - [Journey 3: GP sends bulk reminders](#journey-3-gp-sends-bulk-reminders)
  - [Build Notes for Implementers](#build-notes-for-implementers)
- [Cross-cutting Concerns](#cross-cutting-concerns)
- [Design Decisions](#design-decisions)
- [Testing](#testing)
- [Risks and Open Questions](#risks-and-open-questions)

---

## Overview

Adds a GP-facing NDA status dashboard using a server-rendered HTML table (matching the standard Ransack table style). Two views: a lightweight Status tab in the existing NDA Settings modal (simple HTML partial via Turbo Frame) and a dedicated full-page dashboard with HTML table, client-side filtering, export, and exemption management. A new `nda_exemptions` table stores user-level NDA bypasses, and the existing NDA gate gains an exemption check. Bulk reminders are descoped to a separate notifications module.

---

## Architecture

### Component Boundaries

```mermaid
flowchart TD
    subgraph UI["UI Layer"]
        Modal["NDA Modal — Status Tab"]
        DashPage["Dedicated Dashboard Page"]
        AGGrid["AG Grid (ag_controller.js)"]
    end

    subgraph Domain["Domain — nda_configs pack"]
        NdaStatusCtrl["NdaStatusController"]
        NdaExemption["NdaExemption model"]
        NdaConfig["NdaConfig model"]
        NdaAcceptance["NdaAcceptance model"]
        NdaStatusService["NdaStatusResolver service"]
    end

    subgraph ExistingModels["Existing Models"]
        InvestorAccess["InvestorAccess model"]
        Investor["Investor model"]
        Folder["Folder model"]
    end

    subgraph Gate["Gate — documents pack"]
        DocsCtrl["DocumentsController#ensure_nda_accepted"]
    end

    Modal -->|"Turbo Frame load"| NdaStatusCtrl
    DashPage -->|"HTML"| NdaStatusCtrl
    NdaStatusCtrl -->|"resolve investors + users"| InvestorAccess
    NdaStatusCtrl -->|"latest acceptance"| NdaAcceptance
    NdaStatusCtrl -->|"check exemptions"| NdaExemption
    NdaStatusCtrl -->|"folder context"| Folder
    NdaStatusCtrl -->|"NDA config"| NdaConfig
    DocsCtrl -->|"exemption check"| NdaExemption
```

**Contract table:**

| From | To | Contract | Direction |
|---|---|---|---|
| Modal Status Tab | NdaStatusController#summary | Turbo Frame request → HTML partial | Request |
| Dashboard Page | NdaStatusController#index | HTML (page) + XLSX (export) | Request |
| NdaStatusController | InvestorAccess | `.where(entity_id:, approved: true)` → investor universe + users + tags | Query |
| NdaStatusController | NdaAcceptance | `.where(nda_config_id:, investor_id:)` → latest status | Query |
| NdaStatusController | NdaExemption | `.where(nda_config_id:)` → exempt user_ids | Query |
| DocumentsController | NdaExemption | `.exists?(nda_config_id:, user_id:)` | Query |

**Design decision — investor universe source:** The investor universe comes from `InvestorAccess` (entity-level), not `AccessRight` (folder-level). Data Room folder visibility for regular LP users is driven by InvestorAccess — the `!investor_advisor?` check in `DocumentsController#folder` bypasses folder-level AccessRight checks for all non-advisor users. The NDA gate also resolves investors via InvestorAccess, so the dashboard uses the same source for consistency.

### Class Diagram

```mermaid
classDiagram
    namespace NdaConfigsPack {
        class NdaConfig {
            +has_many nda_acceptances
            +has_many nda_exemptions
        }
        class NdaAcceptance {
            +belongs_to nda_config
            +belongs_to investor
            +belongs_to user
            +accepted?() Boolean
        }
        class NdaExemption {
            <<new>>
            +belongs_to nda_config
            +belongs_to user
            +belongs_to exempted_by : User
            +reason : String
        }
        class NdaStatusController {
            <<new>>
            +summary()
            +index()
            +create_exemption()
            +destroy_exemption()
        }
        class NdaStatusResolver {
            <<new>>
            +resolve(nda_config, folder) StatusData
        }
    }

    namespace InvestorAccessesPack {
        class InvestorAccess {
            +with_tag(tag) scope
            +belongs_to investor
            +belongs_to user
        }
    }

    namespace DocumentsPack {
        class DocumentsController {
            +ensure_nda_accepted()
        }
    }

    NdaConfig "1" --> "*" NdaAcceptance
    NdaConfig "1" --> "*" NdaExemption
    NdaExemption "*" --> "1" NdaConfig
    NdaExemption "*" --> "1" User
    NdaStatusController --> NdaStatusResolver
    NdaStatusResolver --> InvestorAccess
    NdaStatusResolver --> NdaAcceptance
    NdaStatusResolver --> NdaExemption
    DocumentsController --> NdaExemption
```

### Change Footprint

```mermaid
flowchart LR
    subgraph New["New (green)"]
        NE["NdaExemption model"]
        NSC["NdaStatusController"]
        NSR["NdaStatusResolver service"]
        STIM["nda_status_controller.js (Stimulus)"]
        MIG["create_nda_exemptions migration"]
        VIEWS["Status tab partial + dashboard HTML + XLSX"]
    end

    subgraph Modified["Modified (amber)"]
        MODAL["NDA modal — enable Status tab"]
        GATE["DocumentsController#ensure_nda_accepted — add exemption check"]
        NDACONF["NdaConfig — add has_many :nda_exemptions"]
        ROUTES["config/routes/core.rb — add nda_status routes"]
    end

    subgraph Reused["Reused (grey)"]
        IA["InvestorAccess queries"]
        NA["NdaAcceptance queries"]
        LAYOUT["modernize layout + breadcrumbs"]
    end

    subgraph Descoped["Descoped (red)"]
        REM["Bulk reminders — separate notifications module"]
    end

    classDef green fill:#e8f5e9,stroke:#2e7d32,color:#000
    classDef amber fill:#fff3e0,stroke:#ef6c00,color:#000
    classDef grey fill:#f5f5f5,stroke:#9e9e9e,color:#000
    classDef red fill:#ffebee,stroke:#c62828,color:#000
    class NE,NSC,NSR,STIM,MIG,VIEWS green
    class MODAL,GATE,NDACONF,ROUTES amber
    class IA,NA,LAYOUT grey
    class REM red
```

---

## Data Model and States

### Data Model

```mermaid
erDiagram
    nda_configs ||--o{ nda_exemptions : "has_many"
    users ||--o{ nda_exemptions : "exempted user"
    users ||--o{ nda_exemptions : "exempted_by"

    nda_exemptions {
        bigint id PK
        bigint nda_config_id FK "NOT NULL"
        bigint user_id FK "NOT NULL"
        bigint exempted_by_id FK "NOT NULL"
        string reason "limit 500, nullable"
        datetime created_at "NOT NULL"
        datetime updated_at "NOT NULL"
    }
```

**Indexes:**
- `idx_nda_exemptions_config_user [nda_config_id, user_id]` UNIQUE — one exemption per user per NDA config
- `idx_nda_exemptions_user [user_id]` — audit queries

**Changes to existing models:**
- `NdaConfig`: add `has_many :nda_exemptions, dependent: :destroy`

### State Transitions

Investor-level NDA status is derived at read time, not stored. The states and transitions:

```mermaid
stateDiagram-v2
    [*] --> Pending : investor gains folder access
    Pending --> Accepted : any user of investor accepts NDA
    Pending --> Declined : any user of investor declines NDA
    Declined --> Accepted : any user of investor accepts NDA
    Accepted --> Declined : future revocation (not Module 3)
    Pending --> Exempt : all users of investor are individually exempted
    Exempt --> Pending : any user's exemption is revoked
```

User-level exemption status:

```mermaid
stateDiagram-v2
    [*] --> NotExempt : user has folder access
    NotExempt --> Exempt : GP creates NdaExemption
    Exempt --> NotExempt : GP revokes NdaExemption
```

---

## Behaviour

### Sequence Diagrams

**Happy path: GP views status summary in modal**

```mermaid
sequenceDiagram
    actor GP
    participant Modal as NDA Modal
    participant Ctrl as NdaStatusController
    participant Resolver as NdaStatusResolver
    participant IA as InvestorAccess
    participant NA as NdaAcceptance
    participant NE as NdaExemption

    GP->>Modal: Click Status tab
    Modal->>Ctrl: GET /nda_status/summary?nda_config_id=X&folder_id=Y (Turbo Frame)
    Ctrl->>Resolver: resolve(nda_config, folder)
    Resolver->>IA: InvestorAccess.where(entity_id:, approved: true).distinct.pluck(:investor_id)
    IA-->>Resolver: investor universe
    Resolver->>IA: InvestorAccess.where(entity_id:, investor_id: [...], approved: true).includes(:user)
    IA-->>Resolver: users per investor + NDA tags
    Resolver->>NA: NdaAcceptance.where(nda_config_id: X, investor_id: [...])
    NA-->>Resolver: latest acceptance per investor
    Resolver->>NE: NdaExemption.where(nda_config_id: X)
    NE-->>Resolver: exempt user_ids
    Resolver-->>Ctrl: StatusData (counters + investor rows)
    Ctrl-->>Modal: HTML partial (counters + table)
    Modal-->>GP: Status summary displayed
```

**GP marks user as exempt**

```mermaid
sequenceDiagram
    actor GP
    participant Page as Dashboard Page
    participant Ctrl as NdaStatusController
    participant NE as NdaExemption

    GP->>Page: Click "Exempt" on User 5 row
    Page->>Ctrl: POST /nda_status/exemptions?nda_config_id=X&user_id=5&reason=...
    Ctrl->>Ctrl: authorize (GP must be same entity)
    Ctrl->>NE: NdaExemption.create!(nda_config_id: X, user_id: 5, exempted_by: GP, reason: ...)
    NE-->>Ctrl: created
    Ctrl-->>Page: JSON response { status: "ok" }
    Page->>Page: window.location.reload()
    Page-->>GP: User 5 now shows "Exempt"
```

**Exempt user hits NDA gate**

```mermaid
sequenceDiagram
    actor User as Exempt User
    participant Docs as DocumentsController
    participant NE as NdaExemption
    participant Folder as Folder Contents

    User->>Docs: GET /documents/folder?folder_id=Y
    Docs->>Docs: GP bypass? No (different entity)
    Docs->>NE: NdaExemption.exists?(nda_config_id: X, user_id: User)
    NE-->>Docs: true
    Docs->>Folder: render folder contents
    Folder-->>User: Documents visible (no NDA screen)
```

### Worked Examples

**Shared setup:**

| Entity | Item | Detail |
|---|---|---|
| Alpha Ventures | GP Admin | fm1@ian.com, company_admin |
| Alpha Ventures | Folder "Fund Alpha Docs" | Data Room folder with NDA-A (enabled, click_through, until_revoked) |
| Alpha Ventures | Investor "Acme Capital" | Category: LP. InvestorAccess approved. |
| Acme Capital | User A (alice@acme.com) | InvestorAccess approved, NDA tag |
| Acme Capital | User B (bob@acme.com) | InvestorAccess approved, NDA tag |
| Acme Capital | User C (carol@acme.com) | InvestorAccess approved, no NDA tag |
| Acme Capital | User D (dave@acme.com) | InvestorAccess approved, no NDA tag |
| Acme Capital | User E (eve@acme.com) | InvestorAccess approved, no NDA tag, EXEMPT |
| Alpha Ventures | Investor "Beta Holdings" | Category: LP. InvestorAccess approved. No acceptance. |
| Beta Holdings | User F (frank@beta.com) | InvestorAccess approved, NDA tag |
| Alpha Ventures | Investor "Gamma Fund" | Category: LP. InvestorAccess approved. Declined. |
| Gamma Fund | User G (gina@gamma.com) | InvestorAccess approved, NDA tag |

**Happy Path:**

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| H1 | GP views status summary in modal | NDA-A active on folder, Acme accepted, Beta pending, Gamma declined, Eve exempt | GP opens NDA Settings modal, clicks Status tab | Counters: Accepted=1, Pending=1, Declined=1, Exempt=0. Table shows 3 investor rows with correct statuses. | GP views status summary for NDA-protected folder | nda_status.feature |
| H2 | GP opens dedicated dashboard | Same as H1 | GP clicks "View Full Dashboard" | HTML table with 3 investor rows. Acme expandable to 5 users (Alice=Signer, Eve=Exempt, rest=dash). | GP opens dedicated dashboard from modal | nda_status.feature |
| H3 | GP marks user as exempt | Eve not yet exempt | GP clicks Exempt on Eve's row, enters reason "NDA signed offline" | Eve's status changes to Exempt. NdaExemption record created. | GP creates exemption for a user | nda_status.feature |
| H4 | GP revokes exemption | Eve is exempt | GP clicks Revoke on Eve's row | Eve's status reverts to stakeholder status (Accepted). NdaExemption deleted. | GP revokes exemption | nda_status.feature |
| H5 | GP exports status | Same as H1 | GP clicks Export | XLSX downloaded with all investors + users, statuses, dates | GP exports NDA status | nda_status.feature |
| H6 | ~~GP sends bulk reminders~~ | ~~Descoped to separate notifications module~~ | — | — | — | — |

**Edge Cases:**

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E1 | Exempt user accesses folder before stakeholder signs | Eve exempt, Acme has NOT accepted NDA-A | Eve navigates to folder | Folder contents shown (no NDA screen) | Exempt user accesses NDA-protected folder before stakeholder signs | nda_status.feature |
| E2 | Exemption revoked, stakeholder not accepted | Eve's exemption revoked, Acme has NOT accepted | Eve navigates to folder | NDA acceptance screen shown | Exemption revoked, stakeholder not accepted | nda_status.feature |
| E3 | All entity investors shown | All investors with approved InvestorAccess to entity | GP views dashboard | All approved investors appear regardless of folder | Entity-level investor universe | nda_status.feature |
| E4 | Investor access revoked | Acme's InvestorAccess revoked (approved: false) | GP views dashboard | Acme no longer appears in dashboard | Investor access revoked | nda_status.feature |
| E5 | ~~No pending investors for reminders~~ | ~~Descoped to separate notifications module~~ | — | — | — | — |
| E6 | Duplicate exemption attempt | Eve already exempt | GP attempts to exempt Eve again | No duplicate created (unique constraint) | Exemption uniqueness | nda_status.feature |
| E7 | ~~Reminder skips exempt users~~ | ~~Descoped to separate notifications module~~ | — | — | — | — |
| E8 | ~~Reminder targets only NDA-tagged~~ | ~~Descoped to separate notifications module~~ | — | — | — | — |
| E9 | Status tab hidden for folder without NDA | Folder has no NDA config | GP opens NDA Settings modal | Only Settings tab visible, no Status tab | Status tab hidden when no active NDA | nda_status.feature |
| E10 | Inherited NDA status | Child folder inherits NDA-A from parent | GP opens Status tab on child | Shows statuses for NDA-A. Investor universe from entity's InvestorAccess. | Status tab for inherited NDA | nda_status.feature |
| E11 | Investor fully exempt | All users of Delta LP are individually exempt | GP views dashboard | Delta LP investor-level status = "Exempt" | Investor-level status derivation (all exempt) | nda_status.feature |

**Error Cases:**

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| X1 | Non-GP tries to access dashboard | LP user logged in | LP navigates to /nda_status?nda_config_id=X | 403 Forbidden — policy denies | (policy check) | nda_status.feature |
| X2 | Other-entity GP tries dashboard | GP from different entity | GP navigates to /nda_status?nda_config_id=X | 403 Forbidden — entity mismatch | (policy check) | nda_status.feature |
| X3 | NDA config not found | Invalid nda_config_id | GP navigates to /nda_status?nda_config_id=99999 | 404 Not Found | (standard RecordNotFound) | nda_status.feature |

---

## Key Components

| Component | Responsibility |
|---|---|
| NdaStatusResolver | Resolves the full status picture for a given NDA config + folder: investor universe (from InvestorAccess), user details per investor (from InvestorAccess), latest acceptance per investor (from NdaAcceptance), exempt users (from NdaExemption). Returns structured data for both the modal summary and the HTML table. |
| nda_status_controller.js | Stimulus controller for client-side status filtering, text search, and exemption grant/revoke actions via fetch API. |

**Status derivation decision flow:**

```mermaid
flowchart TD
    A["For each investor with InvestorAccess"] --> B{"All users of investor exempt?"}
    B -- Yes --> C["Status = Exempt"]
    B -- No --> D{"Latest NdaAcceptance exists?"}
    D -- No --> E["Status = Pending"]
    D -- Yes --> F{"Latest status?"}
    F -- accepted --> G["Status = Accepted"]
    F -- declined --> H["Status = Declined"]
```

---

## Controllers and Routes

| Method | Route | Action | Response |
|---|---|---|---|
| GET | `/nda_status/summary` | NdaStatusController#summary | Turbo Frame HTML partial (counters + table) |
| GET | `/nda_status` | NdaStatusController#index | HTML page (dashboard) |
| GET | `/nda_status.xlsx` | NdaStatusController#index | XLSX download |
| POST | `/nda_status/exemptions` | NdaStatusController#create_exemption | JSON (for Stimulus fetch) |
| DELETE | `/nda_status/exemptions/:id` | NdaStatusController#destroy_exemption | JSON (for Stimulus fetch) |

All routes scoped under the NDA configs pack. Query params: `nda_config_id`, `folder_id`.

---

## Policy

**NdaStatusPolicy:**

| Role | summary | index / export | create_exemption | destroy_exemption |
|---|---|---|---|---|
| GP Admin (same entity) | Allow | Allow | Allow | Allow |
| GP Employee (same entity) | Allow | Allow | Allow | Allow |
| LP / Investor user | Deny | Deny | Deny | Deny |
| Other-entity GP | Deny | Deny | Deny | Deny |

**Entity scoping:** Policy checks `nda_config.entity_id == current_user.entity_id` and `curr_role_employee?`. Same pattern as NdaConfigPolicy.

```mermaid
flowchart TD
    A["User requests NDA status action"] --> B{"curr_role_employee?"}
    B -- No --> C["DENY"]
    B -- Yes --> D{"nda_config.entity_id == user.entity_id?"}
    D -- No --> C
    D -- Yes --> E["ALLOW"]
```

---

## UI Changes

### At a Glance

| Screen | Before | After |
|---|---|---|
| NDA Settings Modal | Status tab disabled ("Coming soon") | Status tab enabled with summary counters + investor table |
| Dedicated dashboard page | Does not exist | New page: HTML table, status filter, search, export, exemptions |
| NDA gate (invisible to GP) | GP bypass → stakeholder check | GP bypass → **exemption check** → stakeholder check |

### Journey 1: GP views NDA status summary in modal

```
+-------------------------------------------------------+
|  NDA Settings — Fund Alpha Docs                    [x] |
|-------------------------------------------------------|
|  [Settings]  [Status]  <-- ① Tab now enabled           |
|-------------------------------------------------------|
|                                                        |
|  ② Accepted: 1  Pending: 1  Declined: 1  Exempt: 0    |
|                                                        |
|  ③ +--------------------------------------------------+|
|     | Investor        | Status   | Signed By | Date   ||
|     |-----------------|----------|-----------|--------|  |
|     | Acme Capital    | Accepted | Alice     | Oct 3  ||
|     | Beta Holdings   | Pending  | —         | —      ||
|     | Gamma Fund      | Declined | Gina      | Oct 2  ||
|     +--------------------------------------------------+|
|                                                        |
|  ④ [View Full Dashboard -->]                            |
+-------------------------------------------------------+
```

| Step | The user... | They see |
|---|---|---|
| 1 | Clicks the Status tab in the NDA Settings modal | Tab becomes active, Settings pane hides, Status pane shows |
| 2 | Looks at the counters | Four badges: Accepted, Pending, Declined, Exempt with counts |
| 3 | Scans the investor table | Simple HTML table with one row per investor |
| 4 | Clicks "View Full Dashboard" | Navigates to the dedicated dashboard page |

### Journey 2: GP opens dedicated dashboard and manages exemptions

```
+--------------------------------------------------------------+
|  NDA Status — Fund Alpha Docs                                |
|  ① [Filter: Status v] ② [Search...] ③ [Export] ④ [Reminders]|
+--------------------------------------------------------------+
|  ⑤ Investor       | Status   | Signed By | Date    | Action  |
|  ------------------|----------|-----------|---------|---------|
|  v Acme Capital    | Accepted | Alice     | Oct 3   |         |
|    ⑥ Alice (NDA)   | Signer   | Alice     | Oct 3   |         |
|    Bob (NDA)       | —        | —         | —       |[Exempt] |
|    Carol           | —        | —         | —       |[Exempt] |
|    Dave            | —        | —         | —       |[Exempt] |
|    ⑦ Eve           | Exempt   | —         | —       |[Revoke] |
|  > Beta Holdings   | Pending  | —         | —       |         |
|  > Gamma Fund      | Declined | Gina      | Oct 2   |         |
+--------------------------------------------------------------+
```

| Step | The user... | They see |
|---|---|---|
| 1 | Selects a status from Filter dropdown | Grid filters to show only investors matching that status |
| 2 | Types in Search box | Grid filters by investor or user name |
| 3 | Clicks Export | XLSX file downloads |
| 4 | Clicks Send Reminders | Confirmation dialog, then success message |
| 5 | Expands Acme Capital row | User rows appear under the investor |
| 6 | Sees Alice marked as Signer with (NDA) tag | Alice is the user who physically signed |
| 7 | Sees Eve marked as Exempt with Revoke button | Eve has an NdaExemption record |

### Journey 3: GP sends bulk reminders

| Step | The user... | They see |
|---|---|---|
| 1 | Clicks "Send Reminders" | Confirmation dialog: "Send NDA reminders to 1 pending investor (1 NDA-tagged user)?" |
| 2 | Clicks Confirm | Flash message: "Reminders sent to 1 user" |
| 3 | If no pending investors | Button disabled or message "No pending investors to remind" |

### Build Notes for Implementers

- **Modal Status tab**: Turbo Frame lazy-load. The Status tab content is loaded via `turbo_frame_tag "nda_status_summary"` with `src` pointing to `nda_status_summary_path(nda_config_id:, folder_id:)` and `loading: :lazy`. Content loads only when the tab is clicked.
- **AG Grid**: Follow existing pattern — `data-controller="ag"`, `data-source` pointing to JSON endpoint, `data-custom-columns` from `STANDARD_COLUMNS`. Use `group_by_column` for investor-level grouping.
- **Turbo Stream for exemptions**: POST/DELETE actions return Turbo Stream responses that replace the affected user row in the grid. Consider using `turbo_stream.replace` targeting the user row by DOM id.
- **Export**: Standard `.xlsx.axlsx` template. Skip pagination when `request.format.xlsx?`.
- **Reminder job**: Enqueue `NdaReminderJob` from the controller to keep the response fast. The job loops through user_ids and dispatches `NdaReminderNotifier`.

---

## Cross-cutting Concerns

### Transactions and Queries

- **NdaStatusResolver**: Multiple queries (AccessRight, InvestorAccess, NdaAcceptance, NdaExemption) but all are reads — no transaction needed. Preload investors and users to avoid N+1 on the AG Grid JSON endpoint.
- **Create exemption**: Single INSERT — no transaction needed.
- **Send reminders**: Controller enqueues one background job with the list of user_ids. The job dispatches notifications one at a time (Noticed handles delivery). No transaction.
- **N+1 risk**: The JSON endpoint must eager-load investor → users → investor_accesses to avoid N+1 when rendering rows. Use `includes` or batch queries in the resolver.

### Exception Handling and Monitoring

| Failure | Who is alerted | How |
|---|---|---|
| NdaExemption save fails (validation) | GP | Flash error on page |
| NdaReminderJob fails | Sidekiq retry + dead set | Standard Sidekiq monitoring |
| NdaReminderMailer delivery fails | Sidekiq retry | Standard mail delivery retry |

### Performance

- Status derivation is read-time, not cached. For large investor lists (100+), the resolver should batch queries (pluck investor_ids, batch NdaAcceptance lookups) rather than N+1.
- The modal summary partial should be lightweight — no AG Grid JS loaded.

### Security

- All actions require GP authentication + entity match via NdaStatusPolicy.
- NdaExemption.exempted_by_id set server-side (current_user), not from params.
- XLSX export does not include sensitive fields beyond what's visible on screen.

---

## Design Decisions

| # | Decision | Alternative | Why rejected |
|---|---|---|---|
| 1 | Separate NdaExemption table | Store exemption as NdaAcceptance with status "exempt" | Exemption is a GP configuration, not an LP action. Mixing them in the same table muddies the audit trail and conflates two different concepts. |
| 2 | NdaStatusResolver service object | Inline queries in controller | The resolver is reused by both the modal summary and the dashboard JSON endpoint. Extracting it avoids duplication. |
| 3 | Background job for reminders | Inline notification dispatch in controller | Sending N emails synchronously would block the GP's request. Job keeps the response fast. |
| 4 | Turbo Frame lazy-load for modal Status tab | Eager-load status data with the modal | Status data requires multiple queries. Lazy-loading means the Settings tab renders instantly and status loads only when clicked. |
| 5 | Simple HTML table in modal, AG Grid on dedicated page | AG Grid everywhere | Modal-lg is too narrow for AG Grid. HTML table is simpler and faster for a summary. |
| 6 | Exemption per user (not per investor) | Exemption per investor | Product requirement: specific users are exempted (legal counsel, advisors), not entire organizations. |
| 7 | Status computed at read time | Denormalized status column | Status depends on NdaAcceptance (append-only) + NdaExemption (mutable) + AccessRight (mutable). Caching would go stale. Read-time derivation is simpler and always correct. |

---

## Testing

Cucumber only. Single feature file `features/core/nda_status.feature`, tagged `@nda`.

Shared setup reuses existing step files: `nda_config_steps.rb` (entity, folder, NDA config), `nda_acceptance_steps.rb` (acceptance records), `investor_access_steps.rb` (InvestorAccess with tags). New step file: `nda_status_steps.rb` for dashboard navigation, exemption actions, reminder actions, and export verification.

The Feature column in Worked Examples maps each scenario to `nda_status.feature`.

---

## Risks and Open Questions

- **AG Grid row grouping with Turbo Stream updates**: Replacing a single user row inside a grouped AG Grid via Turbo Stream may not work cleanly — AG Grid manages its own DOM. Mitigation: exemption toggle may need to reload the grid data via `fetch` + `gridApi.setRowData()` instead of Turbo Stream DOM replacement. Investigate during implementation.
- **Large investor lists**: Entities with 500+ investors could make the modal summary slow. Mitigation: the Turbo Frame lazy-load keeps the modal responsive; if needed, limit the modal table to top N rows with a "View Full Dashboard" CTA.
- **Reminder deduplication**: If the GP clicks "Send Reminders" twice quickly, two jobs may enqueue. Mitigation: disable the button after first click via Stimulus controller; consider job-level idempotency check.
