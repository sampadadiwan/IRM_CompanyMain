# PRD: Folder Workflows

## 1. Overview

This feature lets a folder be associated with a reusable workflow. Every document added to that folder automatically enters the workflow and advances through a configurable series of steps. Each step has a set of allowable states (e.g. Approved, Rejected, Tentative) and one or more actors who can change those states. Actors can optionally add a note with each state change. Step transitions trigger email notifications with magic links so actors can respond without logging in.

---

## 2. Background & Problem Statement

Documents in the system today have no formal review or approval lifecycle. Teams rely on out-of-band email threads, Slack messages, or manual status fields to coordinate review. This creates gaps in audit trails, inconsistent outcomes, and no enforcement of who must act before a document is considered final.

A structured workflow tied directly to a folder gives every document a defined path from submission to completion, with a clear record of who did what and when.

---

## 3. Goals

- Allow admins to define reusable **workflow templates** with ordered steps.
- Allow any folder to be assigned one of those templates.
- A workflow instance is launched for the **folder as a whole** — it represents a review/approval cycle over all documents in that folder together, not per-document.
- Each step has: allowable states, actors, quorum rule, on-reject behavior, and optional notes.
- State changes send email notifications to actors; emails contain **magic links** so actors can respond without logging in.
- Emails link actors to the folder (not an individual document) so they can review all contents before responding.
- Provide a full audit trail of every state change (who, when, from→to, via which channel).

---

## 4. Non-Goals

- Parallel/branching workflows (steps are strictly ordered in this version).
- Workflow versioning / migration of in-flight documents when a template changes.
- Mobile push notifications (email only for now).
- Bulk-actioning many documents at once through a workflow step.
- Integration with external e-signature providers.

---

## 5. Key Concepts

| Term | Definition |
|---|---|
| **Workflow template** | A named, reusable ordered list of steps. Shared across folders. |
| **Workflow instance** | A running copy of a template attached to one **folder**. Represents one full review cycle over all documents in that folder. |
| **Step** | A single stage in the workflow. Has states, actors, quorum rule, on-reject rule, and optional notes. |
| **State** | A label an actor can assign to a step for a document (e.g. Approved, Rejected, Tentative). States are a configurable comma-separated list per step. |
| **Actor** | An individual employee of the entity who can set the state on a step. |
| **Quorum rule** | How many actor responses are needed to consider a step complete: `any_one`, `all`, or `majority`. Configurable per step; default is `any_one`. |
| **On-reject rule** | What the workflow does when the resolved state for a step is a rejection: `stop`, `previous_step`, `restart`, or `go_to_step_N`. Configurable per step; default is `stop`. |
| **Tiebreaker** | When quorum rule is `all` and actors submit conflicting states, a `company_admin` manually overrides by setting the step to a definitive state. |
| **Auto-reminder** | An email re-sent to pending actors after N days of inactivity. Interval defined at the workflow level; overridable per step. |
| **Magic link** | A multi-use, expiry-free (until step advances) signed URL embedded in the notification email. Allows the actor to set a state without logging in. |

---

## 6. User Stories

**As an admin**, I want to define a workflow template (e.g. "Two-Stage LP Review") with named steps, states, and actors so I can reuse it across multiple data rooms.

**As an admin**, I want to assign a workflow template to a folder and then launch a review cycle so that all documents in that folder are reviewed together as a batch.

**As a reviewer (actor)**, I want to receive an email when it's my turn to review a folder's contents, and I want to click a link in that email to approve, reject, or mark it tentative — without having to log in.

**As a reviewer**, I want to optionally add a note when I change a step's state so my reasoning is captured alongside the decision.

**As an admin or folder manager**, I want to see the current step, current state, and history of all state changes for the folder's active workflow so I always know where it stands.

**As an admin**, I want rejected documents to follow a configurable path (stop, return to prior step, restart) rather than a one-size-fits-all behavior.

**As a `company_admin`**, when actors on an `all`-quorum step submit conflicting states, I want to be able to break the tie by manually setting the resolved state so the workflow can continue.

**As an admin**, I want auto-reminder emails sent to actors who haven't responded after N days, so stalled workflows surface without manual tracking. I want to set the default reminder interval on the template and override it on individual steps where the SLA differs.

---

## 7. Functional Requirements

### 7.1 Workflow Templates

- A workflow template has: `name`, `description`, and an ordered list of steps.
- Templates are created and edited by admins only (not folder managers).
- A template can be assigned to multiple folders simultaneously.
- Editing a template does **not** affect in-flight workflow instances (instances snapshot the template at assignment time).

### 7.2 Steps

Each step contains:

| Field | Type | Default | Notes |
|---|---|---|---|
| `name` | string | — | e.g. "Initial Review" |
| `description` | text | — | Optional context for actors |
| `states` | CSV string | `"Approved,Rejected,Needs Info"` | Fully free-form. First value is the displayed default. |
| `actors` | list of entity employee user IDs | — | At least one required. Individual employees of the owning entity only. |
| `quorum_rule` | enum | `any_one` | `any_one` \| `all` \| `majority` |
| `on_reject_rule` | enum | `stop` | `stop` \| `previous_step` \| `restart` \| `go_to_step_N` |
| `on_reject_target_step` | integer | — | Only used when rule is `go_to_step_N` |
| `reminder_interval_days` | integer | inherits from template | Override the template-level auto-reminder interval for this step. `nil` disables reminders on this step. |

### 7.3 Folder–Workflow Association

- A folder has an optional `workflow_template_id` field.
- Assigning a template to a folder does **not** automatically start a workflow. An admin must explicitly **launch** a workflow instance for the folder once the folder's documents are ready for review.
- A folder can only be associated with one template at a time.
- A folder can have multiple workflow instances over time (e.g. annual review cycles), but only one `active` instance at a time.
- Launching a workflow creates a `WorkflowInstance` for the folder at step 1 and notifies all step 1 actors.
- Removing the template from a folder is **blocked** if there is an active workflow instance. The admin must wait for the instance to complete, reject, or manually archive it before the template can be unassigned.

### 7.4 Workflow Instance Lifecycle

```
Admin assigns template to folder
        │
Admin clicks "Launch Workflow" (folder is ready for review)
        │
        ▼
   Step 1 starts
        │
   Emails sent to step 1 actors (link to folder)
        │
   Actors review folder contents and respond via magic link or UI
        │
   Quorum met?  ──No──► wait for more responses
        │Yes
   State = rejection?
        │Yes               │No
   On-reject rule      Advance to next step
        │                   │
   stop/restart/         Repeat until
   prev/go_to_N          final step complete
                              │
                         Workflow complete
```

### 7.5 State Changes

- An actor may change the state of the current step for the active workflow instance (not past steps, not future steps).
- State changes are recorded in `WorkflowStateChange`: actor, timestamp, from_state, to_state, channel (`email_magic_link` or `ui`), optional note.
- A step's **resolved state** is computed from individual actor responses according to the quorum rule:
  - `any_one`: first response wins; step resolves immediately.
  - `all`: step is not resolved until every assigned actor has responded. If all actors agree, that state is the resolved state. If actors submit conflicting states, the step enters **tiebreaker mode** — no automatic resolution. A `company_admin` must visit the step and manually set the final state to unblock the workflow.
  - `majority`: whichever state has more than half the actor responses. If no state achieves majority after all actors respond, the step enters tiebreaker mode (same as `all` conflict above).

### 7.6 Rejection Handling

When a step's resolved state is a rejection state:

| `on_reject_rule` | Behavior |
|---|---|
| `stop` | Workflow is halted; document is marked `rejected`. No further emails. |
| `previous_step` | Workflow reverts to the immediately preceding step. Actors are re-notified. |
| `restart` | Workflow resets to step 1. All prior responses are archived (not deleted). |
| `go_to_step_N` | Workflow jumps to the specified step. |

### 7.7 Email Notifications

Emails are sent to all **pending** actors of a step (those who have not yet responded) when:
- The step becomes active (workflow advances to it).
- An auto-reminder fires (see §7.7b).
- A reminder is manually triggered by an admin.

Email content includes:
- Folder name and a link to the folder.
- Current step name and description.
- Per-actor magic links for each available state (one link per state, e.g. "Click here to **Approve**", "Click here to **Reject**").

### 7.7a Document Attachment in Emails

- The workflow template has an `attach_document_in_email` boolean flag (default: `false`).
- Since the workflow is folder-level, emails always link to the folder. When this flag is enabled, the notification email additionally attaches all documents in the folder (subject to the size cap) so actors can review them without logging in.
- If the total attachment size exceeds the configured threshold (suggested default: 10 MB per file), the email falls back to a secure folder link with a note explaining that attachments were skipped.
- Attachment is at the template level (applies to all steps). Individual steps cannot override this in v1.
- The `WorkflowTemplate` data model gains: `attach_document_in_email` (boolean, default false).

### 7.7b Auto-Reminders

- Each workflow template has a `reminder_interval_days` field (e.g. `3`). A background job checks daily and sends a reminder to all pending actors on any active step whose last notification was ≥ `reminder_interval_days` ago.
- Individual steps can override this interval with their own `reminder_interval_days`. Setting a step's value to `nil` disables auto-reminders for that step.
- Auto-reminder emails are identical in format to the step-activation email (same magic links).
- The `WorkflowStateChange` log records each auto-reminder dispatch with channel = `auto_reminder`.

### 7.8 Magic Links

- A magic link encodes: `workflow_instance_id`, `step_id`, `actor_id`, `target_state`, and an HMAC signature.
- Clicking a link does **not** immediately change state. It opens a confirmation page showing:
  - The folder name and a list of documents in the folder
  - The current step name
  - The selected state (pre-filled from the link, but visible to the actor)
  - An optional notes textarea
  - A **Submit** button — state change only occurs on explicit submit
- Links are valid until the step itself advances or the workflow is reset/stopped.
- Clicking a link that is no longer valid shows a friendly "this step has already moved on" message.
- An actor can click a different state link from the same email before submitting to change their mind; last submitted response wins.
- Magic link responses are logged with channel = `email_magic_link`.

### 7.9 Notes

An actor may optionally add a free-text note when submitting a state change, both via the magic-link response page and the in-app UI. Notes are always optional. Each note is stored on the `WorkflowActorResponse` record and displayed in the audit trail.

### 7.10 Audit Trail

- `WorkflowStateChange` records every state change with: actor, timestamp, channel, from_state, to_state, note.
- The document viewer shows a timeline of the workflow history.
- Export of the full audit trail as CSV from the document's workflow panel.

---

## 8. Permissions & Access Control

| Role | Can do |
|---|---|
| `company_admin` | Create/edit/delete workflow templates; assign templates to folders; view all workflow instances; manually advance, reset, or break tiebreaker on any step |
| Folder manager | View workflow instances for their folder; send manual reminders; cannot edit the template |
| Actor (assigned employee) | Set state on steps they are assigned to; add optional notes; respond via magic link without login |
| Viewer | View current workflow state and history for documents they can access |

---

## 9. Data Model (Conceptual)

```
WorkflowTemplate
  id, name, description, entity_id, reminder_interval_days,
  attach_document_in_email (boolean, default false)

WorkflowStep (belongs_to WorkflowTemplate)
  id, position, name, description, states (CSV), quorum_rule,
  on_reject_rule, on_reject_target_step,
  reminder_interval_days (nullable; nil = inherit from template)

WorkflowStepActor (belongs_to WorkflowStep)
  id, user_id  # individual entity employee only

Folder
  ... existing fields ...
  workflow_template_id (FK, nullable)

WorkflowInstance (belongs_to Folder)
  id, folder_id, workflow_template_id, template_snapshot (JSON),
  current_step_position, status, launched_by_id
  (status: active | complete | rejected | archived)
  # template_snapshot preserves the template/steps at launch time so edits don't affect in-flight instances

WorkflowActorResponse (belongs_to WorkflowInstance, step_position, actor)
  id, workflow_instance_id, step_position, actor_id, state, note,
  channel (ui | email_magic_link), responded_at

WorkflowStateChange (event log)
  id, workflow_instance_id, step_position, actor_id, from_state, to_state,
  note, channel, created_at
```

---

## 10. Email & Magic Link Flow

```mermaid
sequenceDiagram
    participant System
    participant Mailer
    participant Actor
    participant MagicLinkController

    System->>Mailer: step becomes active (step N, actors A1..An)
    Mailer->>Actor: email with magic links (one per state) + folder link + doc attachments if enabled

    Actor->>MagicLinkController: GET /workflow/respond?token=<signed_token>
    MagicLinkController->>MagicLinkController: verify HMAC signature
    MagicLinkController->>MagicLinkController: check step still active
    alt step still active
        MagicLinkController->>Actor: show confirmation page (folder name, doc list, step name, selected state, optional notes textarea)
        Actor->>MagicLinkController: POST submit (optional note)
        MagicLinkController->>System: record WorkflowActorResponse
        System->>System: evaluate quorum
        alt quorum met
            System->>System: resolve step state
            alt resolved state is rejection
                System->>System: apply on_reject_rule
            else
                System->>System: advance to next step
                System->>Mailer: notify next step actors
            end
        end
        MagicLinkController->>Actor: "Thank you, your response has been recorded."
    else step no longer active
        MagicLinkController->>Actor: "This step has already moved on."
    end
```

---

## 11. UI Touchpoints

1. **Admin: Workflow Templates CRUD** — `/admin/workflow_templates` — list, create, edit, delete templates and their steps.
2. **Folder settings panel** — "Workflow" tab — assign or remove a template; shows history of workflow instances; "Launch Workflow" button starts a new instance.
3. **Folder workflow panel** — shows current step, each actor's response, timeline of all state changes for the active instance, and admin controls (advance, reset, send reminder).
4. **Magic link response page** — minimal, no-login page — shows folder name, list of documents in the folder, step name, pre-selected state, optional notes textarea, and a **Submit** button. State change is recorded only on submit.
5. **Actor dashboard widget** (future) — lists all folders awaiting the current user's response across all workflows.

---

## 13. Implementation Phases

The feature is split into four phases. Each phase ships independently and adds a layer of capability on top of the previous one. The pack lives at `app/packs/core/workflow_templates/`.

---

### Phase 1 — Data Model & Admin Template CRUD

**Goal:** Admins can create, edit, and delete workflow templates with ordered steps. Nothing fires yet.

**Migrations / Models**
- `WorkflowTemplate` — `name`, `description`, `entity_id`, `reminder_interval_days`, `attach_document_in_email`
- `WorkflowStep` — `workflow_template_id`, `position`, `name`, `description`, `states` (CSV, default `"Approved,Rejected,Needs Info"`), `quorum_rule` (enum, default `any_one`), `on_reject_rule` (enum, default `stop`), `on_reject_target_step`, `reminder_interval_days` (nullable)
- `WorkflowStepActor` — `workflow_step_id`, `user_id`
- `Folder` — add `workflow_template_id` FK (nullable migration)

**Controllers / Policies**
- `WorkflowTemplatesController` (CRUD) under `/admin/workflow_templates`
- `WorkflowStepsController` (nested under template) for step ordering via drag-and-drop position
- `WorkflowTemplatePolicy` — only `company_admin` can create/edit/delete

**Views**
- Template list + form (steps nested with Stimulus reorder controller)
- Step form: states CSV field, actor multi-select (entity employees only), quorum/reject enums
- Folder settings panel — "Workflow" tab: dropdown to assign/remove template

**Tests (Cucumber)**
- Admin creates a template with two steps and assigns it to a folder
- Non-admin cannot access `/admin/workflow_templates`
- Folder settings save and display the assigned template name

---

### Phase 2 — Workflow Instance Lifecycle (No Email)

**Goal:** An admin can launch a workflow instance for a folder. The instance advances through steps based on actor responses via the in-app UI. Email comes in Phase 3.

**Migrations / Models**
- `WorkflowInstance` — `folder_id`, `workflow_template_id`, `template_snapshot` (JSON), `current_step_position`, `launched_by_id`, `status` (enum: `active | complete | rejected | archived`)
- `WorkflowActorResponse` — `workflow_instance_id`, `step_position`, `actor_id`, `state`, `note`, `channel` (enum: `ui | email_magic_link | auto_reminder`), `responded_at`
- `WorkflowStateChange` (event log) — `workflow_instance_id`, `step_position`, `actor_id`, `from_state`, `to_state`, `note`, `channel`, `created_at`

**Service Objects**
- `WorkflowInstanceService#launch(folder, launched_by:)` — called from the "Launch Workflow" action; snapshots the template + steps into `template_snapshot`; creates the instance at step 1; raises if folder has no template or already has an active instance
- `WorkflowStepResolver#resolve(instance)` — evaluates quorum (`any_one` / `all` / `majority`) against current `WorkflowActorResponse` records; returns resolved state or `:tiebreaker` or `:pending`
- `WorkflowAdvancer#advance(instance)` — called after `resolve` succeeds; applies `on_reject_rule` or advances `current_step_position`; sets `status` to `complete` / `rejected` when done; archives responses on restart/revert
- `WorkflowArchiver#archive(instance)` — called by admin to manually archive a stalled instance (unlocks template removal)

**Controllers / Policies**
- `WorkflowInstancesController` — `create` (launch, admin only), `show` (timeline), `advance` (admin only), `reset` (admin only)
- `WorkflowActorResponsesController` — `create` (actor sets state + optional note via UI)
- `WorkflowInstancePolicy` — actors can only respond to their assigned step; admin can launch/advance/reset/break tie

**Views**
- Folder "Workflow" tab: active instance status panel (current step, per-actor response status, state-change timeline, admin controls); "Launch Workflow" button when no active instance; instance history list
- Actor response UI: dropdown of step states + optional notes textarea + submit button

**Tests (Cucumber)**
- Admin launches workflow for folder → instance created at step 1
- Launching when active instance exists → blocked with error
- Actor submits `any_one` quorum step → step resolves and advances
- `all` quorum: conflicting responses → tiebreaker mode; admin breaks tie
- `on_reject_rule: stop` → instance becomes `rejected`
- `on_reject_rule: restart` → instance resets to step 1, prior responses archived
- `on_reject_rule: previous_step` → instance reverts one step
- Final step approved → instance becomes `complete`
- Removing template from folder while active instance exists → blocked with validation error
- Removing template from folder when no active instance → succeeds

---

### Phase 3 — Email Notifications & Magic Links

**Goal:** Actors receive emails when a step activates; magic links let them respond without logging in.

**Service Objects**
- `WorkflowMagicLinkService#generate(instance, step_position, actor_id, target_state)` — uses `ActiveSupport::MessageVerifier` (same pattern as `DocShareTokenService`) with no expiry; payload: `{ workflow_instance_id:, step_position:, actor_id:, target_state: }`; links expire implicitly when step advances
- `WorkflowMagicLinkService#verify(token)` — verifies signature; returns payload or `nil`; caller checks instance step still matches

**Mailer**
- `WorkflowMailer#step_activation(instance, step_position, actor_id)` — sends per-actor email with one magic link per available state (one link = one target state); includes folder name, list of documents, step name/description
- `WorkflowMailer#reminder(instance, step_position, actor_id)` — identical format; triggered by auto-reminder job (Phase 4) or manual admin trigger
- When `attach_document_in_email` is `true`: attach each document file from the folder if ≤ configured size threshold (default 10 MB per file); otherwise include a secure folder link with a note

**Controllers**
- `WorkflowMagicLinkController` — `GET /workflow/respond?token=<signed>` → verify token → check step active → render confirmation page (folder name, document list, step name, pre-selected state, notes textarea, Submit button)
- `POST /workflow/respond` → record `WorkflowActorResponse` with `channel: :email_magic_link` → call `WorkflowStepResolver` → call `WorkflowAdvancer` → render "Thank you" or redirect; expired/advanced step → "This step has already moved on"
- Route lives outside Devise auth scope (no login required)

**Tests (Cucumber)**
- Step activation email sent to all actors when step becomes active
- Magic link token verifies correctly and renders confirmation page
- Submitting via magic link records response with `channel: email_magic_link` and advances step
- Clicking a link for an already-advanced step shows the "moved on" message
- Actor changes their mind by using a different state link before submitting — last submit wins
- `attach_document_in_email: true` → folder documents attached (each under 10 MB); falls back to folder link when any file exceeds threshold

---

### Phase 4 — Auto-Reminders & Audit Trail Export

**Goal:** Stalled steps surface automatically; full audit trail is exportable.

**Background Job**
- `WorkflowAutoReminderJob` — runs daily (cron); queries `WorkflowInstance` where `status: :active`; for each active step checks the last notification timestamp (`WorkflowStateChange` where `channel: :auto_reminder`) against the effective `reminder_interval_days` (step override → template default → skip if nil); calls `WorkflowMailer#reminder` for each pending actor; logs each dispatch as a `WorkflowStateChange` with `channel: :auto_reminder`

**Controllers / Views**
- `WorkflowInstancesController#export_audit_trail` — streams CSV of `WorkflowStateChange` records (actor, timestamp, channel, from_state, to_state, note) for the document's workflow panel
- Admin manual reminder button → calls same `WorkflowMailer#reminder` path

**Tests (Cucumber)**
- Auto-reminder job sends email to pending actors after `reminder_interval_days` of inactivity
- Step with `reminder_interval_days: nil` is skipped by the job
- Step-level override takes precedence over template-level interval
- CSV export contains correct columns and all state change rows
- Manual reminder button triggers reminder email immediately

---

## 12. Decided Design Choices

| # | Question | Decision |
|---|---|---|
| 1 | Conflict resolution for `all`/`majority` quorum | `company_admin` manually breaks the tie via the UI — no automatic resolution |
| 2 | Role-based vs. individual actors | Individual entity employees only; no role references |
| 3 | Template versioning / in-flight warning | Not required; instances snapshot the template silently |
| 4 | Auto-reminders | Yes — interval defined at template level (`reminder_interval_days`); overridable per step; `nil` on a step disables reminders for that step |
| 5 | States taxonomy | Fully free-form CSV; no canonical enum |
| 6 | Step field defaults | `states` defaults to `"Approved,Rejected,Needs Info"`; `quorum_rule` defaults to `any_one`; `on_reject_rule` defaults to `stop` |
| 7 | Document delivery | Workflow template can opt in to attaching the document to notification emails so actors can review without logging in (see §7.7b) |
