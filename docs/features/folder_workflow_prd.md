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
- When a document is added to a workflow-enabled folder, it automatically enters the workflow at step 1.
- Each step has: allowable states, actors, quorum rule, on-reject behavior, and optional notes.
- State changes send email notifications to actors; emails contain **magic links** so actors can respond without logging in.
- Optionally attach the document to the notification email so actors can review and respond entirely from their inbox — no app login required.
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
| **Workflow instance** | A running copy of a template attached to one document. |
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

**As an admin**, I want to assign a workflow template to a folder so that every document added to that folder automatically enters the workflow.

**As a reviewer (actor)**, I want to receive an email when it's my turn to review a document, and I want to click a link in that email to approve, reject, or mark it tentative — without having to log in.

**As a reviewer**, I want to optionally add a note when I change a step's state so my reasoning is captured alongside the decision.

**As a document owner**, I want to see the current step, current state, and history of all state changes for my document so I always know where it stands.

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
- When a document is added to the folder (uploaded or moved), a `WorkflowInstance` is created for that document starting at step 1.
- Removing a document from a folder does **not** delete the workflow instance; it is archived.
- A folder can only be associated with one template at a time.

### 7.4 Workflow Instance Lifecycle

```
Document added to folder
        │
        ▼
   Step 1 starts
        │
   Emails sent to step 1 actors
        │
   Actor responds via magic link or UI
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

- An actor may change the state of the current step for a document (not past steps, not future steps).
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
- Document name and a link to the document viewer.
- Current step name and description.
- Per-actor magic links for each available state (one link per state, e.g. "Click here to **Approve**", "Click here to **Reject**").

### 7.7a Document Attachment in Emails

- The workflow template has an `attach_document_in_email` boolean flag (default: `false`).
- When enabled, the notification email (step activation and auto-reminders) attaches the document file so actors can review it inline in their email client, without needing to log in or click through to the app.
- This removes any login requirement from the review flow: actors receive the document + magic-link response buttons in a single email.
- Attachment is at the template level (applies to all steps). Individual steps cannot override this in v1.
- If the document is too large to attach (configurable threshold, suggested default: 10 MB), the email falls back to a secure inline preview link instead, with a note explaining why the file wasn't attached.
- The `WorkflowTemplate` data model gains: `attach_document_in_email` (boolean, default false).

### 7.7b Auto-Reminders

- Each workflow template has a `reminder_interval_days` field (e.g. `3`). A background job checks daily and sends a reminder to all pending actors on any active step whose last notification was ≥ `reminder_interval_days` ago.
- Individual steps can override this interval with their own `reminder_interval_days`. Setting a step's value to `nil` disables auto-reminders for that step.
- Auto-reminder emails are identical in format to the step-activation email (same magic links).
- The `WorkflowStateChange` log records each auto-reminder dispatch with channel = `auto_reminder`.

### 7.8 Magic Links

- A magic link encodes: `workflow_instance_id`, `step_id`, `actor_id`, `target_state`, and an HMAC signature.
- Clicking a link does **not** immediately change state. It opens a confirmation page showing:
  - The document name
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

WorkflowInstance (belongs_to Document, belongs_to WorkflowTemplate snapshot)
  id, document_id, template_snapshot (JSON), current_step_position, status
  (status: active | complete | rejected | archived)

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
    Mailer->>Actor: email with magic links (one per state) + document attachment if enabled

    Actor->>MagicLinkController: GET /workflow/respond?token=<signed_token>
    MagicLinkController->>MagicLinkController: verify HMAC signature
    MagicLinkController->>MagicLinkController: check step still active
    alt step still active
        MagicLinkController->>Actor: show confirmation page (step name, selected state, optional notes textarea)
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
2. **Folder settings panel** — "Workflow" tab — assign or remove a template; shows active instance counts.
3. **Document viewer — Workflow panel** — shows current step, each actor's response, timeline of all state changes, and admin controls (advance, reset, send reminder).
4. **Magic link response page** — minimal, no-login page — shows document name, step name, pre-selected state, optional notes textarea, and a **Submit** button. State change is recorded only on submit.
5. **Actor dashboard widget** (future) — lists all documents awaiting the current user's response across all workflows.

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
