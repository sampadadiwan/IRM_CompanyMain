# Deals Module — Comprehensive Guide

## Table of Contents

1. [What Is the Deals Module?](#1-what-is-the-deals-module)
2. [Core Concepts](#2-core-concepts)
3. [Real-World Use Cases](#3-real-world-use-cases)
4. [Data Model & Relationships](#4-data-model--relationships)
5. [Deal Lifecycle — End to End](#5-deal-lifecycle--end-to-end)
6. [The Board: Kanban & AG Grid](#6-the-board-kanban--ag-grid)
7. [Step Progression System (DealActivity)](#7-step-progression-system-dealactivity)
8. [Tasks on Deals](#8-tasks-on-deals)
9. [Status Tracking & Audit Trail](#9-status-tracking--audit-trail)
10. [Stagnation Detection](#10-stagnation-detection)
11. [Charts & Analytics](#11-charts--analytics)
12. [Custom Fields](#12-custom-fields)
13. [Access Control & Policies](#13-access-control--policies)
14. [Search & Indexing](#14-search--indexing)
15. [Notifications](#15-notifications)
16. [AI Agents on Deals](#16-ai-agents-on-deals)
17. [Key File Reference](#17-key-file-reference)
18. [Routes Reference](#18-routes-reference)

---

## 1. What Is the Deals Module?

The Deals module is a **CRM-style pipeline tracker** built into Caphive IRM. It lets fund managers track the progress of any process that involves moving multiple entities through a sequence of stages.

Think of it as a customizable Trello/pipeline board — but deeply integrated with Caphive's investor, document, task, and notification systems.

The module lives under `app/packs/startups/deals/`.

---

## 2. Core Concepts

### Deal

A **Deal** is the top-level container representing one pipeline/campaign. It holds:

- **Name** — e.g., "Fund II Raise" or "Q3 LP Onboarding"
- **Target Amount** — the goal (e.g., $50M). Stored as `amount_cents` with a `currency`
- **Status** — `Open` or `Closed`
- **Steps** — a sequence of activity stages (templates) that every participant goes through
- **Custom Fields** — fund-manager-defined fields for tracking additional data

A single entity (e.g., Acme Capital) can have **multiple deals running simultaneously** — one for fundraising, another for onboarding, another for co-investments. Each deal is completely independent with its own board, steps, investors, tasks, and charts.

### DealInvestor

A **DealInvestor** is a participant/row in a deal's pipeline. Despite the name "investor," it can represent:

- An LP considering a commitment (fundraising use case)
- A company being evaluated for investment (deployment use case)
- A contact being onboarded (onboarding use case)

Each DealInvestor has:

| Field | Purpose |
|---|---|
| `status` | `Active`, `Pending`, or `Declined` |
| `primary_amount_cents` | Primary investment amount |
| `secondary_investment_cents` | Secondary investment |
| `fee_cents` | Fees |
| `total_amount_cents` | Computed: primary + secondary + fee |
| `pre_money_valuation_cents` | Pre-money valuation |
| `tier` | Priority classification (custom field) |
| `source` | Where this lead came from (Referral, Outbound, Conference, etc.) |
| `deal_lead` | Team member responsible for this investor |
| `investor_advisor` | External advisor for the investor |
| `company_advisor` | Company-side advisor |
| `tags` | Comma-separated tags |
| `notes` | Rich text notes (ActionText) |
| `health_score` | Computed: % of activities completed (0-100) |
| `status_changed_at` | Timestamp of last status change |
| `deal_activity_id` | Points to the current step template |

### DealActivity

A **DealActivity** represents a step/stage in the pipeline. There are two types:

1. **Templates** — `deal_investor_id = nil`. Define the step sequence for the deal. Created when the deal is set up.
2. **Investor-specific copies** — `deal_investor_id` is set. Each investor gets their own copy of every template, tracking their individual progress through that step.

Each activity has:

| Field | Purpose |
|---|---|
| `title` | Step name (e.g., "Due Diligence") |
| `sequence` | Order in the pipeline (1, 2, 3...) |
| `days` | Expected duration for this step |
| `by_date` | Computed due date (cumulative days from deal start) |
| `status` | `Incomplete`, `Complete`, `Skip`, or `Template` |
| `template_id` | For investor copies, points back to the template |
| `tasks_csv` | Comma-separated task titles auto-created when step is reached |
| `notify_employees` | Send notification to team when investor reaches this step |
| `notify_investor` | Send notification to the investor |
| `docs_required_for_completion` | Must upload docs to complete this step |
| `details_required_for_na` | Must provide details if marking N/A |

### Task

A **Task** is an action item attached to a Deal or DealInvestor (polymorphic `owner`):

| Field | Purpose |
|---|---|
| `title` | What needs to be done |
| `due_date` | Deadline |
| `assigned_to` | User responsible (belongs_to User) |
| `completed` | Boolean — done or not |
| `category` | Finance, Ops, Compliance, IR, Other |
| `details` | Rich text description (ActionText) |
| `response` | Rich text response (ActionText) |

---

## 3. Real-World Use Cases

### Use Case 1: Fund Raising

A fund manager is raising $50M for Fund II. They need to track 50 potential LPs through the commitment process.

```
Deal: "Fund II Raise"
Amount: $50,000,000
Currency: USD

Steps:
  1. Initial Outreach     (5 days)
  2. First Call            (7 days)
  3. Partner Meeting       (10 days)
  4. Due Diligence         (14 days)
  5. Term Sheet Sent       (7 days)
  6. Commitment Received   (5 days)

DealInvestors:
  Sequoia Capital  — $10M — Active  — at "Due Diligence"
  Tiger Global     — $8M  — Active  — at "First Call"
  SoftBank         — $15M — Active  — at "Term Sheet Sent"
  Blackstone       — $5M  — Pending — at "Initial Outreach"
  KKR              — $7M  — Declined
```

### Use Case 2: LP Onboarding

Tracking how many LPs have completed their onboarding process.

```
Deal: "Q3 LP Onboarding"

Steps:
  1. Welcome Email Sent
  2. KYC Documents Collected
  3. Bank Details Verified
  4. Subscription Agreement Signed
  5. Onboarding Complete

DealInvestors = the LPs being onboarded
```

### Use Case 3: Co-Investment Pipeline

Tracking potential companies for co-investment.

```
Deal: "Co-Investment Pipeline"
Amount: $20,000,000

Steps:
  1. Screening
  2. 1st Meeting
  3. IC Review
  4. Approval
  5. Deployed

DealInvestors = the companies being evaluated
```

An entity can run all three simultaneously. Each deal has its own board, charts, and reporting.

---

## 4. Data Model & Relationships

### Entity Relationship Diagram

```
Entity (e.g., Acme Capital)
│
├── Deal (1:many)
│   ├── name, amount_cents, currency, status (Open/Closed)
│   ├── DealActivity templates (1:many, deal_investor_id = nil)
│   │   └── title, sequence, days, tasks_csv, notify flags
│   │
│   ├── DealInvestor (1:many)
│   │   ├── status (Active/Pending/Declined), amounts, source, deal_lead
│   │   ├── DealActivity copies (1:many, deal_investor_id = set)
│   │   │   └── investor's progress through each step
│   │   ├── Tasks (polymorphic owner)
│   │   └── Documents (via WithFolder)
│   │
│   ├── Tasks (polymorphic owner — deal-level tasks)
│   ├── KanbanBoard (1:1, via KanbanManager)
│   │   └── KanbanCards (1 per DealInvestor, via KanbanCardManager)
│   ├── Documents Folder (via WithFolder / WithDataRoom)
│   └── AccessRights (polymorphic)
│
└── SupportAgent (1:many — AI agents configured for this entity)
    ├── DealManagementAgent
    ├── DealsReportAgent
    └── SupportAgentReport (per-deal results)
```

### Key Associations in Code

**Deal model:**
```
belongs_to :entity
has_many   :deal_investors,  dependent: :destroy
has_many   :investors,       through: :deal_investors
has_many   :deal_activities, dependent: :destroy
has_many   :tasks,           as: :owner, dependent: :destroy
has_many   :access_rights,   as: :owner, dependent: :destroy
has_one    :kanban_board,    as: :owner, dependent: :destroy  (via KanbanManager)
```

**DealInvestor model:**
```
belongs_to :deal,           touch: true
belongs_to :investor
belongs_to :entity
belongs_to :deal_activity,  optional: true   (current step template)
has_many   :deal_activities, -> { order(sequence: :asc) }, dependent: :destroy
has_many   :tasks,           as: :owner, dependent: :destroy
has_rich_text :notes
```

**DealActivity model:**
```
belongs_to :deal,           touch: true
belongs_to :deal_investor,  optional: true   (nil for templates)
belongs_to :entity
has_many   :derived_activities, class_name: "DealActivity",
           foreign_key: :template_id, dependent: :destroy
has_rich_text :details
acts_as_list scope: %i[deal_id deal_investor_id], column: :sequence
```

### Money Fields

All monetary amounts use the Money gem with `amount_cents` storage:

- `Deal.amount_cents` — target amount (monetized with `deal.currency`)
- `DealInvestor.primary_amount_cents` — primary investment
- `DealInvestor.secondary_investment_cents` — secondary investment
- `DealInvestor.fee_cents` — fees
- `DealInvestor.total_amount_cents` — computed via `calc_total_amount` (before_validation callback): `primary + secondary + fee`
- `DealInvestor.pre_money_valuation_cents` — pre-money valuation

---

## 5. Deal Lifecycle — End to End

### Step 1: Create a Deal

The fund manager fills out the deal form:
- Name, target amount, currency, start/end dates
- Optionally clone steps from an existing deal (`clone_from_id`)
- Define custom fields for tracking

**Code flow:**
1. `DealsController#create` → `CreateDeal` service
2. Creates the Deal record
3. Sets it as `entity.active_deal_id`
4. Creates DealActivity **templates** from:
   - Environment config (`DEAL_ACTIVITIES` or `FUND_DEAL_ACTIVITIES`), or
   - Cloned from another deal's templates
5. Creates a `KanbanBoard` (via KanbanManager `after_create` callback)
6. Syncs kanban columns from the activity template titles

### Step 2: Add Investors to the Deal

The fund manager adds investors one by one or via bulk import (Excel upload).

**Single add — code flow:**
1. `DealInvestorsController#create` → `DealInvestorCreate` service
2. Creates the DealInvestor record (status, amounts, source, deal_lead, etc.)
3. `after_commit` → `create_activities_later` → enqueues `GenerateDealActivitiesJob`
4. Job replicates every template step into **investor-specific DealActivity records**:
   - Each gets a `template_id` pointing back to the template
   - `by_date` computed: cumulative `days` from deal's `start_date`
   - Copies `tasks_csv`, notification flags, doc requirements from template
5. Sets `deal_investor.deal_activity_id` to the first incomplete template (current step)
6. Creates a KanbanCard (via KanbanCardManager `after_commit`)

**Bulk import:**
- `ImportDealInvestorService` parses an Excel file with 3 sheets:
  - "Deal Investors" — main investor data
  - "Deal Steps" — activity status overrides (optional)
  - "Notes" — note records (optional)
- Each investor is created via the service (respects callbacks)

### Step 3: Progress Investors Through Steps

The fund manager moves investors through steps as conversations progress.

**Code flow (PerformActivityAction service):**
1. Validates investor is on the expected step
2. Marks current investor-specific activity as `Complete`
3. Updates `deal_investor.deal_activity_id` to the next template
4. Updates `kanban_column_id` — moves the card to the next column
5. Sends notifications:
   - To employees (if `notify_employees` on the template)
   - To investor (if `notify_investor` on the template)
   - Via `DealActivityMoveNotifier` → custom email templates
6. Generates tasks from `tasks_csv` (via `GenerateDealStepTasksJob`):
   - Parses comma/newline-separated task titles
   - Creates Task records (due: today + 7 days, assigned to user who moved)
7. Broadcasts kanban update via Turbo

Activities can also be:
- **Skipped** (status = "Skip")
- **Toggled** back to Incomplete (via `toggle_completed` action)

### Step 4: Track Status Changes

DealInvestor status can change at any time:
- `Active` → `Declined` (investor said no)
- `Pending` → `Active` (investor is now engaged)
- Any → `Declined`

**Code flow:**
1. `DealInvestorsController#update` → `DealInvestorUpdate` service
2. `before_save` → `track_status_change` callback sets `status_changed_at`
3. `Trackable` concern (audited gem) records the change in the `audits` table

**Bulk status update:**
- `DealInvestorsController#bulk_update_status`
- Uses `update_all` (raw SQL) — **bypasses callbacks**
- `status_changed_at` is NOT updated
- Audit records may be incomplete

### Step 5: Close the Deal

When the fundraise is complete:
- Status changed to `Closed`
- Deal agents (DealManagementAgent) skip closed deals automatically
- Historical data is preserved for reporting

---

## 6. The Board: Kanban & AG Grid

### Kanban Board

Each deal gets its **own KanbanBoard** (created automatically via `KanbanManager` concern).

- **Columns** = the deal's activity step templates (each template title becomes a column)
- **Cards** = DealInvestors (via `KanbanCardManager` concern)
- Card data shows: investor name, formatted money amounts, notes, tags
- Card data fields are configurable via `deal.card_view_attrs`

Visual representation:
```
Fund II Raise — Kanban View
| Outreach     | First Call  | Due Diligence | Term Sheet  | Commitment |
| [Blackstone] | [Tiger]     | [Sequoia]     | [SoftBank]  |            |
| [NewCo]      |             |               |             |            |
```

When an investor advances a step, their card moves to the next column automatically.

**Key concern methods:**
- `KanbanManager`:
  - `after_create :create_kanban_board` — auto-creates board with Deal as owner
  - `after_update :update_kanban_board` — syncs board name + card data on deal changes
- `KanbanCardManager`:
  - `after_commit :create_or_update_kanban_card` — auto-creates/updates cards
  - `after_destroy :destroy_kanban_card` — removes card on investor deletion
  - `deal_investor_data` — builds card data (title, info fields, notes, tags, column)

### AG Grid (Spreadsheet View)

A spreadsheet-like view where:
- Each **row** = DealInvestor
- **Columns** include: investor name, status, amounts, tier, source, deal_lead, health score, each step's completion status, custom fields
- All columns are **inline-editable**
- Column configuration stored in `deal.grid_columns` (JSON)
- Custom field columns auto-merged via `grid_columns_for_js`
- Supports Ransack filtering + Elasticsearch search

Standard columns (15): Investor Name, Status, Primary Amount, Secondary Investment, Pre Money Valuation, Fee, Total Amount, Tier, Deal Lead, Source, Investor Advisor, Company Advisor, Notes, Tags, Health Score

### Navigation Structure

```
Deals Index Page (list of all deals for the entity)
  └── Click on a deal
        └── Deal Detail Page
              ├── Tab: Board (Kanban view)
              ├── Tab: Grid (AG Grid spreadsheet)
              ├── Tab: Charts (analytics — funnel, velocity, mix charts)
              ├── Tab: Activities (step templates — configure/reorder)
              ├── Tab: Access Rights (who can see this deal)
              └── Tab: Agent Settings (configure AI agents)
```

---

## 7. Step Progression System (DealActivity)

### Templates vs Investor Copies

```
Deal "Fund II Raise"
│
├── Template Activities (deal_investor_id = nil):
│   ├── Seq 1: "Outreach"        (status: template)
│   ├── Seq 2: "First Call"       (status: template)
│   └── Seq 3: "Due Diligence"   (status: template)
│
├── Sequoia's Activities (deal_investor_id = 101):
│   ├── Seq 1: "Outreach"        (status: complete,   template_id → Outreach template)
│   ├── Seq 2: "First Call"       (status: complete,   template_id → First Call template)
│   └── Seq 3: "Due Diligence"   (status: incomplete, template_id → DD template)
│
└── Tiger's Activities (deal_investor_id = 102):
    ├── Seq 1: "Outreach"        (status: complete,   template_id → Outreach template)
    ├── Seq 2: "First Call"       (status: incomplete, template_id → First Call template)
    └── Seq 3: "Due Diligence"   (status: incomplete, template_id → DD template)
```

### How `deal_investor.deal_activity_id` Works

This field points to the **template** (not the investor copy) of the investor's current step:

- Sequoia's `deal_activity_id` → "Due Diligence" template (she's at step 3)
- Tiger's `deal_activity_id` → "First Call" template (he's at step 2)

The method `current_deal_activity_id` returns the investor-specific activity ID for the current template.

### Health Score Computation

```ruby
def health_score
  return 0 if deal_activities.blank?
  total_count = deal_activities.size
  completed_count = deal_activities.count { |a| a.status == "Complete" }
  ((completed_count.to_f / total_count) * 100).round
end
```

Not a persisted field — computed on-the-fly. Sequoia with 2/3 complete = 67%. Tiger with 1/3 complete = 33%.

### Template Modification Cascading

When a template is added, removed, or reordered:
1. `DealActivity#after_save` → `recreate_activities`
2. Enqueues `GenerateDealActivitiesJob` for the entire deal
3. Job regenerates investor-specific activities for **all investors** to match the new template structure

### Task Auto-Generation from Steps

When a template has `tasks_csv` (e.g., `"Request financials, Schedule site visit"`):

1. Investor advances to this step (via `PerformActivityAction`)
2. `GenerateDealStepTasksJob` fires
3. Parses comma/newline-separated task titles
4. Creates Task records:
   - `owner: deal_investor`
   - `due_date: today + 7 days`
   - `assigned_to: user who moved the step`
   - Deduplicates by title

---

## 8. Tasks on Deals

### Two Sources of Tasks

**Manual tasks** — created by the fund manager directly:
```
Task:
  Title:       "Send updated term sheet to Sequoia"
  Due Date:    30 Jun 2026
  Assigned To: Alex Morgan
  Owner:       Sequoia (DealInvestor)  — or the Deal itself
```

**Auto-generated tasks** — created when an investor reaches a step with `tasks_csv`:
```
Step "Due Diligence" has tasks_csv: "Request financials, Schedule site visit"

When Tiger moves to Due Diligence:
  Task 1: "Request financials"    (due: +7 days, assigned to: user who moved)
  Task 2: "Schedule site visit"   (due: +7 days, assigned to: user who moved)
```

### Task Scopes

| Scope | Query |
|---|---|
| Overdue | `completed: false, due_date < today` |
| Upcoming pending | `completed: false, due_date: today..end_of_week` |
| Completed this week | `completed: true, updated_at: this_week_range` |
| All incomplete | `completed: false` |

### Task Ownership

Tasks can be owned by:
- A **Deal** (deal-level to-do): `owner_type: "Deal", owner_id: deal.id`
- A **DealInvestor** (investor-specific to-do): `owner_type: "DealInvestor", owner_id: di.id`

To get all tasks for a deal (including investor-level tasks):
```
deal_tasks = Task.where(owner: deal)
investor_tasks = Task.where(owner_type: "DealInvestor", owner_id: deal.deal_investor_ids)
all_tasks = deal_tasks + investor_tasks
```

---

## 9. Status Tracking & Audit Trail

### DealInvestor Status Values

Three allowed statuses: `Active`, `Pending`, `Declined`

### How Status Changes Are Tracked

**1. `status_changed_at` timestamp:**
- `before_save` callback `track_status_change` sets `status_changed_at = Time.current` when `status_changed?`
- Used by the commitment velocity chart (cumulative amounts over time)

**2. Audited gem (via Trackable concern):**
- Every field change on Deal, DealInvestor, and DealActivity is recorded in the `audits` table
- Stores: old value, new value, action type (create/update/destroy), user who made the change, timestamp
- Query example: "which DealInvestors had status change to 'Declined' this week?"

**3. UI: Step Movements Timeline:**
- DealInvestor detail page shows audit trail filtered to `["status", "deal_activity_id"]` changes
- Displays a timeline of when the investor moved between steps and status changes

### Audit Trail Component

`AuditTrail` component (`app/packs/core/components/audit_trail.rb`):
- Renders audit history as a table: Time, User, Attribute, Old Value, New Value
- Can filter to specific keys
- Supports graphical timeline view

### Bulk Operations Caveat

`DealInvestorsController#bulk_update_status` uses `update_all` (raw SQL):
- **Bypasses** `track_status_change` callback → `status_changed_at` NOT updated
- **Bypasses** ActiveRecord callbacks → audit gem records may be incomplete
- Returns JSON: `{ success: true, updated_count: N, status: new_status }`

This is a known gap. For accurate weekly reporting, the `audits` table is more reliable than `status_changed_at`, but even audits may miss bulk operations.

---

## 10. Stagnation Detection

### Model-Level (DealInvestor)

```ruby
def stagnant?
  return false if %w[Declined Complete].include?(status)
  updated_at < 7.days.ago
end

def stagnant_reason
  return nil unless stagnant?
  "No activity for more than 7 days"
end
```

Hardcoded 7-day rule on `updated_at`. Excludes Declined and Complete investors.

### Agent-Level (DealManagementAgent)

Configurable via `SupportAgent.json_fields["stagnant_days"]` (defaults to agent minimum of 1 day).

Two-part check — investor is flagged stagnant only if **both**:
1. `deal_investor.updated_at < stagnant_days.days.ago`
2. **AND** all `deal_activities.updated_at < stagnant_days.days.ago`

This is more sophisticated than the model-level check — an investor with a recently updated activity isn't flagged even if the investor record itself is old.

**Note:** There is no `stagnant_days` field on the Deal model itself. Stagnation thresholds are configured only in the SupportAgent's `json_fields`.

---

## 11. Charts & Analytics

All chart methods are defined in `app/packs/startups/deals/helpers/deals_helper.rb`. They return data hashes ready for chart rendering.

### Per-Deal Charts

| Chart Method | What It Shows | Data Source |
|---|---|---|
| `deal_investors_money(deal)` | Grouped bar: Pre Money, Primary, Secondary per investor | DealInvestor amount fields |
| `deal_investors_status(deal)` | Pie chart: Active/Pending/Declined counts | DealInvestor.status |
| `deal_activities_completion(deal)` | Pie: Incomplete/Complete/Skip counts | DealActivity.status |
| `deal_conversion_funnel(deal)` | Bar chart: investor count by status | DealInvestor.status |
| `deal_commitment_velocity(deal)` | Area chart: cumulative invested amount over time | DealInvestor.status_changed_at (for Active/Committed/Complete) |
| `deal_weighted_pipeline(deal)` | Bar: target vs weighted pipeline | Deal.amount_cents vs weighted DealInvestor amounts |
| `deal_activity_efficiency(deal)` | Bar: average days to complete per step | DealActivity completion timestamps |
| `deal_investor_concentration(deal)` | Donut: investment amounts grouped by `source` | DealInvestor.source |
| `deal_investor_concentration_by_tier(deal)` | Donut: amounts grouped by `tier` | DealInvestor.tier |
| `deal_investor_concentration_by_lead(deal)` | Donut: amounts grouped by `deal_lead` | DealInvestor.deal_lead |
| `deal_days_in_stage(deal)` | Histogram: 0-7, 8-14, 15-30, 30+ days at current step | DealInvestor.updated_at |
| `deal_activities_funnel_data(deal)` | Funnel: completed investors per template step | DealActivity completion per template |

### Aggregate Charts (Across All Deals)

| Chart Method | What It Shows |
|---|---|
| `deals_status_chart(deals)` | Deal status distribution (Open/Closed) |
| `deals_by_currency_chart(deals)` | Total amount by currency |
| `deals_by_tag_chart(deals)` | Top 10 tags across deals |
| `global_investor_pipeline_chart(deals)` | Pipeline distribution across all deals |
| `deals_volume_trend_chart(deals)` | Deal creation trend over time |
| `top_deals_chart(deals)` | Top 5 deals by target amount |
| `aggregate_investor_sources_chart(deals)` | Investor source breakdown across all deals |

### Charts Relevant to Khushali's Weekly Report

Three charts from the spec map directly to existing helpers:

1. **"Deal funnel showing current status"** → `deal_activities_funnel_data(deal)` — investors completed per step
2. **"Mix by source"** → `deal_investor_concentration(deal)` — amounts by source
3. **"Mix by lead"** → `deal_investor_concentration_by_lead(deal)` — amounts by deal_lead

The data computation already exists. Rendering them in the email report is the only work needed.

---

## 12. Custom Fields

Deals and DealInvestors both include the `WithCustomField` concern.

### How Custom Fields Work

- `json_fields` column (JSON) stores custom field values
- `FormType` association defines available field types for the entity
- `FormCustomField` records define individual fields (name, type, validation rules)
- Field types: TextField, TextArea, NumberField, Money, DateField, MultiSelect, CheckBox, File

### Deal-Level Custom Fields

- `enable_notifications` (in json_fields) — controls deal activity move notifications (defaults enabled)
- Fund managers can add any custom fields they need for tracking

### DealInvestor Custom Fields

- Extended via `properties` (in json_fields)
- Accessible via `deal_investor.properties.field_name`
- Custom fields appear as additional columns in the AG Grid
- Searchable via Ransack JSON path queries

### Custom Fields in AG Grid

Custom fields are automatically merged into AG Grid column definitions via `grid_columns_for_js`. They appear alongside standard columns and are fully sortable/filterable.

---

## 13. Access Control & Policies

### DealPolicy (Pundit)

| Permission | Who Can |
|---|---|
| `index?` | User has `enable_deals` flag |
| `show?` | Permissioned employee with `enable_deals` |
| `overview?` | Permissioned employee OR permissioned investor |
| `create?` / `new?` / `edit?` | User with `enable_deals` |
| `update?` | Permissioned employee with `:update` permission |
| `destroy?` | Permissioned employee with `:destroy` permission |
| `agent_settings?` / `run_now?` | Permissioned employee with `:update` permission |

**Scope resolution by role:**
- **RM** — deals via access_rights (for_rm)
- **Investor** — deals they're a participant in (for_investor)
- **Group Company** — child entity deals
- **Employee (Company Admin)** — all entity deals
- **Employee (with access)** — deals via access_rights (for_employee)
- **Support** — all entity deals

### DealInvestorPolicy

- `show?` — user's entity matches investor entity, OR permissioned employee
- `create?` — deal update permission + investor entity match
- `update?` / `destroy?` — create permission OR permissioned employee with specific permission

### DealActivityPolicy

- `index?` / `show?` — employee OR (investor matches AND not a template)
- `create?` / `update?` / `destroy?` — permissioned employee
- `toggle_completed?` / `perform_activity_action?` — permissioned employee

---

## 14. Search & Indexing

### Elasticsearch via Chewy

**DealIndex:**
```
Search fields: name, status, entity_name
Indexed fields: entity_name, name, status, entity_id, amount_cents,
                start_date, end_date, currency
```

**DealInvestorIndex:**
```
Search fields: deal_name, status, entity_name, investor_name, tags, notes
Indexed fields: entity_name, deal_name, status, entity_id, investor_name,
                pre_money_valuation_cents, primary_amount_cents,
                secondary_investment_cents, tags, notes (plain text from ActionText)
```

### Ransack Search

Both Deal and DealInvestor expose `ransackable_attributes` and `ransackable_associations` for server-side filtering. DealInvestor also uses `RansackerAmounts` for money field filtering (total_amount, primary_amount, etc.).

---

## 15. Notifications

### DealActivityMoveNotifier

Triggered by `PerformActivityAction` when an investor advances a step:

- Looks up `CustomNotification` by `email_method: "deal_activity_move"` + activity title tag
- Notifies:
  - **Company admins** (if `notify_employees: true` on the template)
  - **Investor users** with 'Deal' tag (if `notify_investor: true`)
- Email subject/body from custom template or default

### Deal Mailer

`DealMailer` handles general deal-related emails.

### Deal Management Reminder Mailer

`DealManagementReminderMailer` — sends reminder emails for overdue/approaching DealActivity due dates. Configured per-agent with:
- `days_until_due` (negative = overdue, 0 = due today, positive = upcoming)
- Dynamic subject based on urgency

---

## 16. AI Agents on Deals

### Agent 1: DealManagementAgent

**File:** `app/packs/ai/support_agents/services/deal_management_agent.rb` (922 lines)

**Scope:** Single deal, on-demand or scheduled

**Purpose:** Deep-dive analysis of one deal — stagnation detection, document verification, LLM-powered term extraction and investor scoring.

**Steps (7):**

| Step | What It Does | Toggle |
|---|---|---|
| `initialize_agent` | Validates deal is Open, loads config | Always |
| `check_deal_progress` | Flags stagnant investors + overdue activities | `check_progress` (Yes/No) |
| `check_document_checklist` | Verifies required docs in data room | `check_documents` (Yes/No) |
| `extract_deal_terms` | LLM extracts terms from data room documents (cached) | `extract_terms` (Yes/No) |
| `run_investor_pipeline` | Per-investor: collect docs, summarize notes, score 0-100 via LLM | `summarize_notes` / `score_investors` |
| `send_email_digest` | Sends pipeline digest to notify_email | If notify_email configured |
| `generate_progress_reports` | Saves deal-level SupportAgentReport | Always |

**Configuration (json_fields):**

| Key | Purpose | Default |
|---|---|---|
| `check_progress` | Toggle progress/overdue checks | — |
| `check_documents` | Toggle document checklist | — |
| `required_docs` | Comma-separated doc names to verify | — |
| `extract_terms` | Toggle LLM term extraction | — |
| `term_extraction_prompt` | Custom extraction prompt | Built-in prompt |
| `summarize_notes` | Toggle investor note summarization | — |
| `score_investors` | Toggle investor LLM scoring | — |
| `scoring_skill_file` | Custom scoring rubric document | DEFAULT_SCORING_RUBRIC |
| `notify_email` | Email for digest + reminders | — |
| `stagnant_days` | Days threshold for stagnation | min 1 |
| `note_period` | Period for note collection (Month/Quarter) | Quarter |
| `min_points_per_section` | Minimum scoring detail points | 3 |

**Outputs:**
- Deal-level SupportAgentReport with: extracted_terms, score_leaderboard, health_scores, progress_issues, document_issues
- Per-DealInvestor SupportAgentReport with: summary_text, score data, document_count, activity_count
- DealInvestor fields updated: `ai_score` (integer 0-100), `ai_grade` (varchar, e.g., "B+")

**Scoring rubric (default):** 4 dimensions — Engagement & Responsiveness (0.30), Document Readiness (0.25), Commitment Signals (0.25), Pipeline Health (0.20). Scores 0-100 with letter grades.

**Mailers:**
- `DealManagementDigestMailer` — pipeline digest (stagnant investors, overdue activities, scores, terms)
- `DealManagementReminderMailer` — individual activity due-date reminders

### Agent 2: DealsReportAgent

**File:** `app/packs/ai/support_agents/services/deals_report_agent.rb` (302 lines)

**Scope:** All open deals for an entity (or configured subset)

**Purpose:** Entity-level fundraising snapshot — point-in-time status of all deals with amounts, fill rates, investor pipeline distribution.

**Steps (6):**

| Step | What It Does |
|---|---|
| `initialize_agent` | Loads config, sets stale threshold |
| `load_deals` | Queries all Open deals (or filtered by deal_ids) |
| `calculate_deal_summary` | Per-deal: target vs committed/pending/declined, fill rate, step distribution, top investors, staleness |
| `generate_deal_reports` | Saves HTML reports to deal folders + SupportAgentReport per deal |
| `send_report_email` | Queues email to report_recipients via DealsReportMailer |
| `generate_progress_reports` | Finalizes SupportAgentReport status |

**Configuration (json_fields):**

| Key | Purpose | Default |
|---|---|---|
| `deal_ids` | Comma-separated Deal IDs to include | All Open deals |
| `report_recipients` | Comma-separated email addresses | — |
| `stale_days` | Days threshold for staleness | 30 |
| `include_greeting` | Include greeting in email | true |
| `include_updates` | Include updates section | true |
| `include_tasks_due` | Include tasks due section | true |
| `include_tasks_overdue` | Include overdue tasks | true |
| `include_stale_items` | Include stale items warning | true |

**Per-deal summary data:**
```
deal_id, deal_name, currency, deal_status (on_track/needs_attention/complete/closed)
target_cents, committed_cents, pending_cents, declined_cents, remaining_cents
fill_rate (%), total_investors, active_count, pending_count, declined_count
stale (boolean), stale_days, last_activity_at
step_distribution: [{ step_title, investor_count, sequence }]
top_investors: [{ investor_name, status, tier, total_amount_cents, current_step }]
```

**Supporting infrastructure:**
- `DealsReportRenderer` — renders standalone HTML report, saves as Document in deal's Reports folder
- `DealsReportMailer` — sends consolidated email with deal table, task sections, stale warnings
- Email template: `send_report.html.erb` (132 lines) — banner, action callouts, per-deal summary table

### Comparison: DealManagement vs DealsReport

| Dimension | DealManagementAgent | DealsReportAgent |
|---|---|---|
| Scope | Single deal | All open deals |
| LLM usage | Yes (term extraction, scoring, summaries) | No (pure computation) |
| Focus | Deep analysis + investor scoring | Fundraising status snapshot |
| Time window | Point-in-time (no deltas) | Point-in-time (no deltas) |
| Email | Pipeline digest to notify_email | Summary report to report_recipients |
| Output | Per-deal + per-investor reports | Per-deal reports |
| Typical use | On-demand deep dive | Scheduled weekly overview |

### Agent Configuration UI

Accessed via `DealsController#agent_settings`:
- View: `_deal_agent_settings.html.erb`
- Form for configuring json_fields (toggle steps, set emails, thresholds)
- Agent schedule configuration (via AgentSchedule)
- "Run Now" button (via `DealsController#run_now`)

---

## 17. Key File Reference

### Models
| File | Purpose |
|---|---|
| `app/packs/startups/deals/models/deal.rb` | Deal model — pipeline container |
| `app/packs/startups/deals/models/deal_investor.rb` | DealInvestor — pipeline participant |
| `app/packs/startups/deals/models/deal_activity.rb` | DealActivity — step/stage |
| `app/packs/startups/deals/models/deal_index.rb` | Chewy search index for deals |
| `app/packs/startups/deals/models/deal_investor_index.rb` | Chewy search index for investors |
| `app/packs/core/tasks/models/task.rb` | Task model (polymorphic owner) |

### Controllers
| File | Purpose |
|---|---|
| `app/packs/startups/deals/controllers/deals_controller.rb` | Deal CRUD, charts, agent settings |
| `app/packs/startups/deals/controllers/deal_investors_controller.rb` | Investor CRUD, bulk ops, kanban |
| `app/packs/startups/deals/controllers/deal_activities_controller.rb` | Activity CRUD, step progression |

### Services (Trailblazer Operations)
| File | Purpose |
|---|---|
| `app/packs/startups/deals/services/create_deal.rb` | Deal creation with templates |
| `app/packs/startups/deals/services/update_deal.rb` | Deal update |
| `app/packs/startups/deals/services/deal_investor_create.rb` | Investor creation |
| `app/packs/startups/deals/services/deal_investor_update.rb` | Investor update |
| `app/packs/startups/deals/services/deal_investor_destroy.rb` | Investor soft delete |
| `app/packs/startups/deals/services/complete_deal_activity.rb` | Activity completion |
| `app/packs/startups/deals/services/perform_activity_action.rb` | Step advancement (core workflow) |
| `app/packs/startups/deals/services/update_sequences.rb` | Activity reordering |
| `app/packs/startups/deals/services/import_deal_investor_service.rb` | Bulk Excel import |

### Jobs
| File | Purpose |
|---|---|
| `app/packs/startups/deals/jobs/generate_deal_activities_job.rb` | Replicate templates to investor activities |
| `app/packs/startups/deals/jobs/generate_deal_step_tasks_job.rb` | Auto-generate tasks from step tasks_csv |

### AI Agents
| File | Purpose |
|---|---|
| `app/packs/ai/support_agents/services/deal_management_agent.rb` | Single-deal deep analysis + LLM scoring |
| `app/packs/ai/support_agents/services/deals_report_agent.rb` | Entity-level fundraising snapshot |
| `app/packs/ai/support_agents/services/deals_report_renderer.rb` | HTML report renderer |

### Mailers
| File | Purpose |
|---|---|
| `app/packs/ai/support_agents/mailers/deals_report_mailer.rb` | Consolidated deals report email |
| `app/packs/ai/support_agents/mailers/deal_management_digest_mailer.rb` | Single-deal pipeline digest |
| `app/packs/ai/support_agents/mailers/deal_management_reminder_mailer.rb` | Activity due-date reminders |
| `app/packs/startups/deals/mailers/deal_mailer.rb` | General deal emails |
| `app/packs/startups/deals/mailers/deal_activity_move_notifier.rb` | Step advancement notifications |

### Mailer Views
| File | Purpose |
|---|---|
| `app/packs/ai/support_agents/views/deals_report_mailer/send_report.html.erb` | Deals report email template (132 lines) |
| `app/packs/ai/support_agents/views/deal_management_digest_mailer/pipeline_digest.html.erb` | Pipeline digest email (111 lines) |
| `app/packs/ai/support_agents/views/deal_management_reminder_mailer/deal_activity_reminder.html.erb` | Activity reminder email |
| `app/packs/ai/support_agents/views/support_agents/_deals_report_html.html.erb` | Standalone HTML report (173 lines) |

### Views
| File | Purpose |
|---|---|
| `app/packs/startups/deals/views/deals/index.html.erb` | Deals listing page |
| `app/packs/startups/deals/views/deals/list_view.html.erb` | Deal detail with tabs |
| `app/packs/startups/deals/views/deals/deal_charts.html.erb` | Deal analytics charts |
| `app/packs/startups/deals/views/deals/_deal_agent_settings.html.erb` | Agent config form |
| `app/packs/startups/deals/views/deals/_list_view_charts.html.erb` | Chart partials |

### Helpers
| File | Purpose |
|---|---|
| `app/packs/startups/deals/helpers/deals_helper.rb` | 15+ chart methods, data formatting |
| `app/packs/startups/deals/helpers/deal_investors_helper.rb` | Investor display helpers |
| `app/packs/startups/deals/helpers/deal_activities_helper.rb` | Activity display helpers |

### Concerns
| File | Purpose |
|---|---|
| `app/packs/misc/kanbans/models/concerns/kanban_manager.rb` | Auto-creates KanbanBoard per deal |
| `app/packs/misc/kanbans/models/concerns/kanban_card_manager.rb` | Auto-creates KanbanCard per investor |
| `app/packs/misc/form_custom_fields/models/concerns/with_custom_field.rb` | Custom fields with validation |
| `app/packs/core/users/models/concerns/trackable.rb` | Audit trail via audited gem |
| `app/packs/core/investors/models/concerns/for_investor.rb` | Investor scope filtering |

### Policies
| File | Purpose |
|---|---|
| `app/packs/startups/deals/policies/deal_policy.rb` | Deal access control |
| `app/packs/startups/deals/policies/deal_investor_policy.rb` | Investor access control |
| `app/packs/startups/deals/policies/deal_activity_policy.rb` | Activity access control |
| `app/packs/startups/deals/policies/deal_base_policy.rb` | Base policy for deals |

---

## 18. Routes Reference

All deal routes are defined in `config/routes/startup.rb`:

```ruby
resources :deals do
  get    :search
  get    :overview
  get    :investor_deals
  get    :consolidated_access_rights
  get    :analytics
  put    :restore_deleted
  get    :show_deleted
  get    :agent_settings
  patch  :agent_settings, action: :update_agent_settings
  post   :run_now
end

resources :deal_investors do
  get    :search
  get    :kanban_search
  patch  :bulk_update_status
  patch  :bulk_advance_activity
end

resources :deal_activities do
  get    :search
  get    :update_sequence
  post   :update_sequences
  post   :toggle_completed
  post   :perform_activity_action
  put    :restore_deleted
  get    :show_deleted
end
```
