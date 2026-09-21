# PRD: Customer Success Dashboard & QBR Platform

**Status:** Draft  
**Date:** 2026-05-03  
**Scope:** `entity_type = "Investment Fund"` only

---

## 1. Overview & Goals

### Problem

Customer success today lives in spreadsheets, email threads, and individual CSM memory. There is no single source of truth for account health, no structured way to run QBRs, and no mechanism for customers to see the commitments IRM has made to them. At 25 customers this is manageable; at 100 it will be a liability.

The goal is to build customer obsession directly into the product — making health visible, reviews structured, and commitments trackable by both sides.

### Goals

| Goal | Metric |
|------|--------|
| CSMs can assess full portfolio health in <2 minutes | Portfolio dashboard loads with health scores for all accounts |
| QBRs are documented and searchable | 100% of quarterly reviews logged in the system within 1 quarter of launch |
| Customers can see open commitments and progress | Customer-visible action items updated within 48h of status change |
| Health score predicts churn signals | Validated by CSM team against actual churn events after 2 quarters |

### Non-Goals

- No Slack/email alerting when health drops (Phase 1 scope decision)
- No NPS / CSAT survey tooling
- LP (`entity_type = "Investor"`) entities — not in scope
- Automated outreach triggered by health score

---

## 2. User Personas

### CSM (Internal)
Manages 5–15 Investment Fund accounts. Needs to: triage portfolio health at a glance, prepare for QBRs without manual data gathering, log action items and follow through on them, and demonstrate to the customer that IRM is reliable and responsive.

### GP Admin / Fund Manager (Customer-Facing)
Runs an investment fund on IRM. Wants to see: how well their team is using the platform, what IRM has committed to doing for them, and whether those commitments are being kept. Does not want to dig through email threads to find out what was promised.

---

## 3. Health Score Design

Score range: **0–100**. RAG thresholds: Green ≥ 70, Yellow 40–69, Red < 40.

Calculated nightly and stored in `CsHealthSnapshot`. Five dimensions:

### 3.1 Engagement (Weight: 25%)

*Are users actually logging in and using the product?*

| Signal | Source | Calculation |
|--------|--------|-------------|
| Days since any user last signed in | `User.last_sign_in_at` where `entity_id = X` | |
| Active user ratio | `User.where(entity_id: X, active: true)` with `last_sign_in_at > 30.days.ago` / total active users | |
| Monthly sign-in frequency | Avg `sign_in_count` growth over last 30 days (via Audit on users) | |

**Scoring:**
- Green (18–25): Any user logged in ≤7 days ago AND active user ratio ≥ 50%
- Yellow (9–17): Last login 8–30 days ago OR active ratio 25–49%
- Red (0–8): No login in >30 days OR active ratio < 25%

### 3.2 Platform Adoption (Weight: 20%)

*Are they using the core features they paid for?*

| Signal | Source |
|--------|--------|
| Funds configured | `Fund.where(entity_id: X).count > 0` |
| Capital calls issued (last 90 days) | `CapitalCall.where(entity_id: X, created_at: 90.days.ago..)` |
| Reports run (last 90 days) | `Report.where(entity_id: X, last_run_at: 90.days.ago..)` |
| DocGen / documents uploaded (last 90 days) | `Document.where(owner_id: X, created_at: 90.days.ago..)` |
| Notifications configured | `EntitySetting.where(entity_id: X).where.not(from_email: nil)` |

**Scoring:** 4 points per signal active (5 signals = 20 max). Each signal is binary (active/inactive) based on criteria above.

### 3.3 Operational Health (Weight: 25%)

*Are there overdue or stuck items that need attention?*

| Signal | Source | Penalty |
|--------|--------|---------|
| Overdue capital calls | `CapitalCall.where(entity_id: X, due_date: ..Date.today, approved: false)` | -5 per overdue call (max -15) |
| Incomplete esigns | `CapitalCommitment.where(entity_id: X, esign_required: true, esign_completed: false)` | -3 per (max -12) |
| Non-compliant commitments | `CapitalCommitment.where(entity_id: X, compliant: false, onboarding_completed: true)` | -3 per (max -9) |
| Failed esign documents | `Document.where(owner_id: X, esign_status: 'failed')` | -2 per (max -6) |

**Scoring:** Start at 25, apply penalties, floor at 0.

### 3.4 Data Completeness (Weight: 15%)

*Is the account properly set up?*

| Signal | Source |
|--------|--------|
| At least 1 fund with commitments | `Fund` with `capital_commitments_count > 0` |
| At least 1 investor KYC completed | Via `CapitalCommitment.where(onboarding_completed: true)` |
| Entity has `from_email` configured | `EntitySetting.from_email.present?` |
| Primary email set on Entity | `Entity.primary_email.present?` |
| At least 1 document uploaded | `Entity.documents_count > 0` |

**Scoring:** 3 points per signal met (5 signals = 15 max).

### 3.5 CSM Coverage (Weight: 15%)

*Is the CSM keeping up with the account?*

| Signal | Scoring |
|--------|---------|
| Days since last QBR | Green: <95 days (quarterly). Yellow: 95–180. Red: >180 or never |
| Open action items overdue | -3 per overdue `CsActionItem` (due_date < today, status != done/cancelled), max -9 |
| QBR conducted in last quarter | +15 if yes, +0 if no |

**Scoring:** 15 if QBR recent + no overdue items, scale down from there.

### 3.6 Score Calculation

```
health_score = (
  engagement_score(0-25) +
  adoption_score(0-20) +
  operational_score(0-25) +
  completeness_score(0-15) +
  csm_coverage_score(0-15)
).clamp(0, 100)
```

---

## 4. CSM Portfolio Dashboard (Internal)

**Route:** `/cs/dashboard` — visible only to users with `enable_support = true`

**Primary table — one row per assigned Investment Fund client:**

| Column | Source |
|--------|--------|
| Client name | `Entity.name` |
| Health badge (RAG + score) | `CsHealthSnapshot.latest` |
| Health trend | Sparkline of last 4 quarterly snapshots |
| Last user login | `MAX(User.last_sign_in_at)` for entity users |
| Last capital event | `MAX(CapitalCall.created_at)` or distribution |
| Days since last QBR | Computed from `SupportClientMapping.last_qbr_date` |
| Open action items | `CsActionItem.where(entity_id: X, status: [open, in_progress]).count` |
| Overdue action items | Count where `due_date < today` |
| Next QBR date | `SupportClientMapping.next_qbr_date` |
| CSM name | `SupportClientMapping.user.name` |

**Filters:** Health status (green/yellow/red), CSM name, has overdue items, next QBR within 30 days.

**Quick actions per row:** "Start QBR", "Add Action Item", "View Client".

**Top summary bar:** Total accounts / Green count / Yellow count / Red count / Total overdue action items.

---

## 5. Client Detail Page (Internal CSM View)

**Route:** `/cs/clients/:entity_id`

### Account Header
- Entity name, logo (if set), entity created_at
- CSM name + assignment date
- Health score badge + 4-quarter trend line (from `CsHealthSnapshot`)
- GitHub Project URL (from `SupportClientMapping.github_project_url`) — clickable external link
- Next QBR date + "Schedule QBR" button
- "Start New QBR" CTA

### Key Metrics Panel (auto-computed)

| Metric | Calculation |
|--------|-------------|
| Active users / Total users | Users with `last_sign_in_at > 30.days.ago` / all entity users |
| Total funds | `Fund.where(entity_id:).count` |
| Total committed AUM | `SUM(Fund.committed_amount_cents)` |
| Capital calls YTD | `CapitalCall.where(entity_id:, created_at: beginning_of_year..)` |
| Collection rate | `SUM(collected_amount_cents) / SUM(call_amount_cents)` across all calls |
| KYC completion | `onboarding_completed = true` / total commitments |
| Esign completion | `esign_completed = true` / `esign_required = true` commitments |
| Last login | `MAX(User.last_sign_in_at)` |

### Activity Timeline

Consolidated feed, most-recent-first. Sources:
- `Audit` records for this entity's funds, commitments, capital calls — show "Fund X updated by [user]"
- `CapitalCall` created/due events
- `Document` created, esign status changes
- `User` logins (from `last_sign_in_at` changes via Audit)
- `CsActionItem` status changes
- `CsQbr` created/shared events

Display: timestamp, event type icon, description, actor name.

### Open Action Items Table

Columns: Title | Status | Due Date | Owner | Days Overdue | Customer Visible | GitHub Issue | Actions

Filter: All / Open / Overdue / Done

Inline status update (open → in_progress → done) without page reload.

### QBR History

List of past `CsQbr` records: Date | Health Score at time | Status | Prepared by | View link

---

## 6. QBR Module

**Route:** `/cs/clients/:entity_id/qbrs/new` and `/cs/clients/:entity_id/qbrs/:id`

### QBR Lifecycle

`draft` → `reviewed` → `shared` (with customer)

Only CSM can move to `shared`. Once shared, customer can see the customer-visible sections.

### QBR Sections

**Section 1: Period Summary** *(auto-populated on create)*
- Review period (from/to dates, default last quarter)
- Health score at start of period vs. end of period
- Metrics snapshot (same as Key Metrics Panel above, snapshotted at QBR creation time)

**Section 2: Platform Health Breakdown** *(auto-populated)*
- Each health dimension score displayed with brief explanation
- Auto-generated talking points: e.g., "Operational Health dropped 8 points — 2 capital calls are overdue"
- CSM can edit/annotate each section

**Section 3: Wins / What Went Well** *(free text, customer-visible)*

**Section 4: Challenges & Open Issues** *(free text + structured)*
- Free text narrative
- Table of linked GitHub issues (title, URL, status label from URL — just stored text)
- Customer visibility toggle per item

**Section 5: Action Items** *(structured — creates `CsActionItem` records)*
- Inline table: add new rows during QBR editing
- Each row: Title | Owner (CSM or GP user) | Due Date | GitHub Issue URL | Customer Visible (checkbox)
- Saves as `CsActionItem` linked to this QBR and entity

**Section 6: Next QBR**
- Date picker → saves to `SupportClientMapping.next_qbr_date`
- Updates `last_qbr_date` when QBR is marked `reviewed`

### Auto-Generated Talking Points

When QBR is created, system generates plain-text talking points based on health signals:

```
- 3 investors have incomplete KYC — onboarding follow-up needed
- Last capital call was 47 days ago, collection rate is 94%
- 2 users have not logged in for 45+ days (out of 5 total)
- 1 action item from last QBR is overdue (due 2026-03-15): "Set up WhatsApp notifications"
```

These are read-only suggestions; CSM edits the narrative sections manually.

---

## 7. Next Actions / Commitment Tracker

The commitment layer — what makes trust visible to the customer.

### Behavior
- Action items can be created during a QBR (linked to `cs_qbr_id`) or ad-hoc from the Client Detail page
- Items with `customer_visible = true` appear on the customer-facing Account Health page
- Status changes are timestamped (`completed_at` when status → done)
- Overdue items (past `due_date`, not done/cancelled) surface in portfolio dashboard and health score

### Customer-Facing View of Action Items
GP Admin sees a table: What IRM committed to → Status → Due Date → Completed On (if done)

This is the "receipt" of commitments. Completed items stay visible for 90 days after `completed_at` so the customer can see the history.

---

## 8. Customer-Facing Account Health Page

**Route:** `/account/health` — visible to GP Admin role users of Investment Fund entities only

### Sections

**Health Score Card**
- Score (0-100) with RAG color
- Plain-language breakdown: "Your platform adoption is strong. 2 investors have incomplete KYC. No overdue capital calls."
- Trend: last 4 quarters (if snapshots exist)

**Key Metrics**
Same metrics as internal panel, excluding CSM-internal data (no CSM coverage dimension shown).

**Operational Checklist**
Progress bars:
- Investor KYC completion: X of Y complete
- Esign completion: X of Y signed
- Capital call collection: X% collected

**Commitments from IRM** *(customer-visible action items only)*
Table: Title | Status badge | Due Date | Completed On

This is the section the founder specifically called out — customers see what IRM committed to and whether it was done.

**Your CSM**
- CSM name, email
- "Last review: X days ago"
- "Next scheduled review: [date]"

---

## 9. Data Model Changes

### New Model: `CsQbr`

```
Table: cs_qbrs
- id
- entity_id          integer  (FK → entities, Investment Fund only)
- csm_user_id        integer  (FK → users — the CSM who created it)
- status             string   default: "draft"  enum: draft, reviewed, shared
- review_period_from date
- review_period_to   date
- health_score_at_review integer  (snapshot of score at creation)
- metrics_snapshot   json     (snapshot of key metrics at creation time)
- wins_notes         text     (customer-visible)
- challenges_notes   text     (customer-visible)
- internal_notes     text     (internal only — never shown to customer)
- shared_at          datetime
- created_at, updated_at, deleted_at

Indexes: entity_id, csm_user_id, status, review_period_from
```

### New Model: `CsActionItem`

```
Table: cs_action_items
- id
- entity_id          integer  (FK → entities)
- cs_qbr_id          integer  (FK → cs_qbrs, nullable — can be ad-hoc)
- csm_user_id        integer  (FK → users — owner/assignee)
- title              string   not null
- description        text
- status             string   default: "open"  enum: open, in_progress, done, cancelled
- priority           string   default: "normal"  enum: low, normal, high
- due_date           date
- completed_at       datetime
- customer_visible   boolean  default: false
- github_issue_url   string
- created_at, updated_at, deleted_at

Indexes: entity_id, cs_qbr_id, status, due_date, customer_visible
```

### New Model: `CsHealthSnapshot`

```
Table: cs_health_snapshots
- id
- entity_id              integer  (FK → entities)
- score                  integer  (0-100)
- rag_status             string   enum: green, yellow, red
- engagement_score       integer
- adoption_score         integer
- operational_score      integer
- completeness_score     integer
- csm_coverage_score     integer
- signals_json           json     (raw input data used — for debugging/audit)
- calculated_at          datetime
- created_at

Indexes: entity_id + calculated_at (composite), entity_id + rag_status
```

One snapshot per entity per day (upsert on entity_id + DATE(calculated_at)).

### Changes to `SupportClientMapping`

Add columns:
```
- github_project_url   string    (URL of the GitHub Project for this client)
- next_qbr_date        date
- last_qbr_date        date
- csm_notes            text      (internal scratch pad — not customer-visible)
```

### Changes to `Entity` (or `EntitySetting`)

No changes needed for Phase 1. The entity scope filter (`entity_type = "Investment Fund"`) is already available.

---

## 10. Implementation Phases

### Phase 1 — CSM Portfolio View & Health Score (Week 1–3)

Goal: CSMs can open one page and immediately triage all 25 accounts.

1. `CsHealthSnapshot` model + migration
2. `CsHealthSnapshotCalculator` service — computes score nightly via Sidekiq cron job
3. Add 4 columns to `SupportClientMapping` (github_project_url, next_qbr_date, last_qbr_date, csm_notes)
4. `/cs/dashboard` — portfolio table with health scores, last login, last capital event, open action item counts
5. Basic `/cs/clients/:entity_id` page — header + key metrics panel only

**Deliverable:** CSM can assess all accounts in one view. Health score is running.

---

### Phase 2 — QBR Module & Action Items (Week 4–6)

1. `CsActionItem` model + migration + controller
2. `CsQbr` model + migration + controller
3. QBR create/edit form (all 6 sections)
4. Auto-populate talking points on QBR create
5. Action items table on Client Detail page with inline status updates
6. Activity timeline on Client Detail page (query Audit + CapitalCall + Document events)
7. QBR history list on Client Detail page

**Deliverable:** CSMs can run structured QBRs and log action items.

---

### Phase 3 — Customer-Facing Views & Health Trends (Week 7–9)

1. `/account/health` route and page (GP Admin access only, Investment Fund entities)
2. Customer-visible action items section on `/account/health`
3. Health score trend sparklines (using 4-quarter `CsHealthSnapshot` history)
4. QBR "shared" state — customer sees wins, challenges, and their action items from the QBR
5. "Your CSM" card on `/account/health`
6. Access control: ensure GP users can only see their own entity's data; CSM dashboard restricted to `enable_support = true`

**Deliverable:** Customers can log in and see their own health, commitments, and QBR summaries.

---

## 11. Open Questions

1. **Health score visibility to customer:** Should GPs see the numeric score (e.g., "72/100") or only the qualitative breakdown without a number? A number can be awkward if it's low.

2. **Action item ownership:** Can a GP Admin user be assigned an action item (i.e., something the customer needs to do)? Or are action items always IRM/CSM commitments to the customer?

3. **QBR frequency enforcement:** Should the system warn or block if a CSM tries to create a second QBR within the same quarter for the same client? Or allow freely?

4. **Health score weights:** The weights above (25/20/25/15/15) are a starting proposal. CSMs should validate these against their intuitions before we commit them in code — do they match what actually predicts at-risk accounts?

5. **GitHub integration depth:** Currently designed as a stored URL (link only). Do you want to pull live issue data from the GitHub API (open/closed count, issue titles)? This requires a GitHub API token and adds scope.

6. **Historical health data:** The first snapshot can only be taken going forward. Should we back-fill historical snapshots by running the calculator against historical Audit data? Or accept that trends only start from launch?

7. **Who can mark action items done?** CSM only, or can the GP Admin user also mark items done on their end? If GP can mark done, it changes the workflow significantly.
