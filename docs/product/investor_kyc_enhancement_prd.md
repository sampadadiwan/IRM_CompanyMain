# Investor KYC Enhancement PRD

**Status:** Part 1 in design; Part 2 implemented (branch: feature/investor-kyc-status-workflow)  
**Author:** thimmaiah  
**Date:** 2026-05-22  
**Relates to:** `InvestorKyc`, `KycDocExtractorAgent`, `KycOnboardingAgent`, `SupportAgent`, `FormType`

---

## Overview

This PRD covers a two-part enhancement to the InvestorKYC feature:

| Part | Summary | Status |
|------|---------|--------|
| **Part 1** | Document-first wizard: upload docs → AI extracts data → pre-populate form → user completes | In design |
| **Part 2** | Investor send workflow: magic-link email, status tracking, fund ↔ investor collaboration (mirrors KpiReport portco workflow) | Implemented |

---

## Part 1: Document-First KYC with AI Extraction

### Problem

The current KYC wizard asks the form-filler (fund admin or investor) to type all data manually before uploading supporting documents. This is tedious and error-prone — the data is already present in the documents (PAN card, passport, Aadhaar, etc.). The filler has to re-enter what the documents already contain.

### Proposed Flow

```
Old flow:  [Wizard step 1: fill fields] → [Wizard step N: upload docs] → Submit

New flow:  [Step 1: upload docs]
               ↓
           [Move to Step 2] ← triggers KycDocExtractorAgent asynchronously
               ↓
           [Step 2: review pre-filled form, complete remaining fields] → Submit
```

**Trigger point:** When the user moves from the "Upload Documents" step to the "Fill Form" step, extraction is triggered automatically in the background. The form renders immediately with an `Extracting data from documents…` notice. Fields populate as the job completes via **Turbo Stream broadcast** — the job broadcasts field-level updates to a `kyc_extraction_#{investor_kyc.id}` stream that the form page subscribes to.

Extracted values are editable — they are suggestions, not locked. The user can override any pre-populated field.

---

### New Agent: `KycDocExtractorAgent`

A new `agent_type` added to `SupportAgent::AGENT_TYPES`. Separate from `KycOnboardingAgent` (which validates after completion) — this agent runs *before* the form is filled.

**Responsibility:** Given an `InvestorKyc` record with uploaded documents, read each document, apply configured extraction rules, and write extracted values back to the KYC record's standard columns and `json_fields`.

**Key differences from `KycOnboardingAgent`:**

| | `KycDocExtractorAgent` | `KycOnboardingAgent` |
|--|--|--|
| Runs | Before form fill (doc-first step) | After `completed_by_investor = true` |
| Purpose | Extract + pre-populate fields | Validate fields & docs, trigger AML |
| Writes to | `investor_kyc` columns + `json_fields` | `SupportAgentReport` issues |
| Trigger | Wizard step transition | Scheduled / event-driven |

---

### Extraction Rule Configuration

Rules are **per KYC FormType**. Each `FormType` record associated with `InvestorKyc` (e.g. "Individual KYC - Domestic", "Non Individual KYC - FPI") gets its own independent rule set. This means the same `KycDocExtractorAgent` can serve all KYC form types in an entity, with different extraction rules for each.

Rules live in `SupportAgent.json_fields["extraction_rules"]`, keyed by `form_type.id` (integer, stable and unambiguous — unlike `tag` which can be blank).

#### Structure

```json
{
  "extraction_rules": {
    "42": [
      {
        "doc_label": "PAN Card",
        "target_field": "PAN",
        "prompt": "Extract the 10-character alphanumeric PAN number"
      },
      {
        "doc_label": "PAN Card",
        "target_field": "full_name",
        "prompt": "Extract the full name printed on the PAN card"
      },
      {
        "doc_label": "PAN Card",
        "target_field": "birth_date",
        "prompt": "Extract the date of birth in YYYY-MM-DD format"
      },
      {
        "doc_label": "Passport",
        "target_field": "address",
        "prompt": "Extract the permanent address from the address page"
      }
    ],
    "43": [
      {
        "doc_label": "Certificate of Incorporation",
        "target_field": "full_name",
        "prompt": "Extract the registered company name"
      }
    ]
  }
}
```

Keys are `form_type.id.to_s` (JSON keys must be strings). Each key maps to the rules for that specific KYC `FormType` record.

- `doc_label` — matches `Document#name`; same labels used in `FormCustomField` File fields for this `FormType`
- `target_field` — either a standard `InvestorKyc` column name (`full_name`, `PAN`, `address`, `birth_date`, `bank_name`, `ifsc_code`, etc.) or a custom field name from `json_fields`
- `prompt` — natural-language instruction passed to the LLM alongside the document file URL

#### Admin UI for Rule Configuration

The `SupportAgent` edit page shows each KYC `FormType` as a separate **named section** (accordion or tabs). The admin navigates to the FormType they want to configure and edits its rules independently.

```
Extraction Rules

  ▼ Individual KYC — Domestic  (FormType id: 42)
  ┌──────────────────────┬──────────────────────────────────────────────────┬────────────────────┐
  │ Document             │ Extraction prompt                                │ Target field       │
  ├──────────────────────┼──────────────────────────────────────────────────┼────────────────────┤
  │ [PAN Card       ▾]   │ Extract the 10-char alphanumeric PAN number      │ [PAN           ▾]  │
  │ [PAN Card       ▾]   │ Extract full name printed on the PAN card        │ [full_name     ▾]  │
  │ [Passport       ▾]   │ Extract the permanent address from address page  │ [address       ▾]  │
  └──────────────────────┴──────────────────────────────────────────────────┴────────────────────┘
  [+ Add Rule]

  ▶ Non Individual KYC — Corporate  (FormType id: 43)
  [+ Add Rule]
```

- Section headers — all `FormType` records for `InvestorKyc` / `IndividualKyc` / `NonIndividualKyc` on the entity, rendered as expandable sections
- Document dropdown — populated from `FormCustomField` File fields belonging to **that section's FormType**
- Target field dropdown — populated from InvestorKyc standard columns + non-File `FormCustomField`s belonging to **that section's FormType**
- Prompt — free-text input

---

### Agent Pipeline Steps

```ruby
class KycDocExtractorAgent < SupportAgentService
  step :initialize_agent       # load investor_kyc, resolve form_type tag, load rules
  step :select_applicable_docs # filter investor_kyc.documents by doc_labels in rules
  step :extract_fields         # for each rule, call LLM with doc URL + prompt → extracted value
  step :write_fields           # write extracted values to investor_kyc (standard + json_fields)
  step :generate_report        # save SupportAgentReport with extraction summary (field, source doc, value)
end
```

- `initialize_agent`: resolves the `form_type_id` from the `InvestorKyc#form_type` association → looks up `extraction_rules[form_type_id.to_s]` array from `json_fields`. Returns false (halts) if no rules configured for this FormType.
- `extract_fields`: calls LLM with `doc.file.url` and the rule's `prompt`. Parses plain-text response (not JSON — simpler for short extractions). Stores raw responses in ctx.
- `write_fields`: writes to standard columns via `public_send("#{field}=", value)` and to `json_fields` for custom fields. Uses `save(validate: false)` to avoid triggering full validations mid-wizard.
- `generate_report`: saves a `SupportAgentReport` recording what was extracted from which doc into which field, plus any fields it could not extract (so the user knows what still needs manual input).

---

### Opt-In: Entity Setting

**This feature is opt-in per tenant.** The existing KYC wizard remains completely unchanged for tenants that do not opt in.

The feature is enabled via an `EntitySetting` flag: `kyc_doc_first_wizard` (boolean, default `false`).

```
EntitySetting#kyc_doc_first_wizard = false  →  existing wizard, no change
EntitySetting#kyc_doc_first_wizard = true   →  document-first wizard + extraction
```

All conditional logic gates on `entity.entity_setting.kyc_doc_first_wizard?`. No existing code paths are altered when the flag is off.

---

### Wizard Changes

Only applies when `entity.entity_setting.kyc_doc_first_wizard?` is true.

The KYC wizard gains a new **first step** (or a distinct pre-step if using Stimulus-based wizard):

```
Step 0: Upload Documents
  → Shows only File-type FormCustomFields for the current form_type
  → "Continue to Fill Form" button moves to Step 1 and triggers KycDocExtractorAgent job
  → If no KycDocExtractorAgent is configured for this form_type, step 0 is skipped

Step 1+: Fill Form (existing wizard steps, unchanged)
  → Fields pre-populated where extraction succeeded
  → Extraction notice banner: "Fields pre-filled from your documents. Please review and complete."
  → Per-field indicator (e.g. subtle highlight or "auto-filled" badge) shows which values were extracted
  → All fields remain editable
```

---

### Data Flow

```
InvestorKyc created (shell)
       │
       ▼
[Doc upload step] — investor/admin uploads PAN Card, Passport, etc.
       │
       ▼ (step transition)
KycDocExtractorJob.perform_later(investor_kyc_id, support_agent_id)
       │
       ▼
KycDocExtractorAgent#call(target: investor_kyc, support_agent: agent)
  for each rule matching doc_label present in investor_kyc.documents:
    → llm.ask(prompt, with: [doc.file.url]) → extracted_value
    → write extracted_value to investor_kyc.PAN / .full_name / .json_fields[field]
    → record result in SupportAgentReport
       │
       ▼
investor_kyc pre-populated
       │
       ▼
[Fill Form step] — user sees pre-filled fields, completes remaining ones
       │
       ▼
investor_kyc.completed_by_investor = true
       │
       ▼
KycOnboardingAgent validates (existing flow, unchanged)
```

---

### Model / Schema Changes

| Change | Detail |
|--------|--------|
| `SupportAgent::AGENT_TYPES` | Add `"KycDocExtractorAgent"` |
| `SupportAgent.json_fields` | New key `"extraction_rules"` keyed by `form_type.id.to_s` — no migration needed |
| `SupportAgent` custom fields | New `overwrite_mode` custom field (Select: `blank_only` / `always`, default `blank_only`) |
| `InvestorKyc` | No schema change — existing `json_fields` and columns absorb extracted values |
| New job | `KycDocExtractorJob` — calls `KycDocExtractorAgent` for a single `InvestorKyc` |
| New service | `app/packs/ai/support_agents/services/kyc_doc_extractor_agent.rb` |
| SupportAgentReport | Re-use existing model — report tracks extraction results per field |

---

### Edge Cases

| Scenario | Handling |
|----------|---------|
| `kyc_doc_first_wizard` entity setting is off (default) | Standard wizard shown, zero code change |
| No `KycDocExtractorAgent` configured for entity | Skip doc-first step entirely; show standard wizard |
| Agent configured but no rules for this form_type tag | Skip extraction; proceed to form with empty fields |
| Doc uploaded but extraction returns blank value | Leave field empty; report shows "could not extract" — user fills manually |
| Doc not yet uploaded for a rule's `doc_label` | Skip that rule; field stays empty |
| Extraction overwrites a value user already typed | Controlled by `overwrite_mode` custom field on the agent — see below |
| LLM error / timeout | Catch, log, continue with remaining rules; report shows error per field |

---

### Overwrite Behaviour (Configurable via Agent Custom Field)

The `KycDocExtractorAgent` respects an `overwrite_mode` custom field on the `SupportAgent` record (configured via `WithCustomField`, same as other agent settings):

| `overwrite_mode` value | Behaviour |
|------------------------|-----------|
| `blank_only` *(default)* | Only write extracted value if the target field is currently blank. Never overwrite user-typed data. |
| `always` | Always write extracted value, overwriting any existing value. Useful when re-running extraction after uploading a corrected document. |

This is set on the `SupportAgent` form just like other agent custom fields — no special UI needed.

---

## Part 2: Investor Send Workflow — Status Tracking & Magic Link

### Problem

The current `send_kyc_form_to_user` flag is boolean and stateless. Once the email fires the flag is cleared — there is no record of whether the investor opened the link, started filling, or submitted. Fund admins have no status visibility beyond `completed_by_investor` (a single boolean). There is no magic link: investors must log in to fill the form.

This part upgrades the existing send mechanism to mirror the KpiReport portco workflow: rich status tracking, signed magic links (investor can fill without logging in), investor-side save-draft and submit, and fund-admin-side status badges and reminders.

**The existing `send_kyc_form_to_user` flag and mechanism are preserved as the trigger.** The upgrade layers status tracking and magic link on top — it does not replace the send mechanism, only enriches what happens after it fires.

---

### Status State Machine

Add a `submission_status` string enum to `InvestorKyc`:

```ruby
enum :submission_status, {
  not_sent:     'not_sent',
  link_sent:    'link_sent',
  draft_saved:  'draft_saved',
  completed:    'completed',
  verified:     'verified'
}, prefix: :submission
```

| Status | Meaning | Maps to existing boolean |
|--------|---------|--------------------------|
| `not_sent` | KYC created, not yet sent to investor | `send_kyc_form_to_user = false`, `completed_by_investor = false` |
| `link_sent` | Email with magic link dispatched | `send_kyc_form_to_user` just fired and cleared |
| `draft_saved` | Investor opened link, saved progress | `completed_by_investor = false` |
| `completed` | Investor submitted form | `completed_by_investor = true` |
| `verified` | Fund admin verified KYC | `completed_by_investor = true`, `verified = true` |

**Backward compatibility**: `completed_by_investor` and `verified` booleans are kept as-is. They are synced by callbacks when `submission_status` transitions:
- `→ completed` sets `completed_by_investor = true`
- `→ verified` sets `verified = true`
- `→ draft_saved / link_sent` ensures `completed_by_investor = false`

All existing scopes (`.completed`, `.verified`, etc.) continue to work without change.

---

### Magic Link

Reuses the existing `ApplicationRecord.signed_id_for_user` / `find_by_signed_id_for_user` infrastructure already in place for `KpiReport`.

**Changes required:**

1. Add `"InvestorKyc"` to `SIGNED_ID_ALLOWED_MODELS` in `application_record.rb`
2. `InvestorKycsController`: skip `authenticate_user!` on `edit` and `update` when `params[:signed_id]` present (same pattern as `KpiReportsController`)
3. `InvestorKycsController`: override `pundit_user` to return `@signed_id_user || current_user`
4. `InvestorKycPolicy`: recognise `user.signed_id_access?` for edit/update permissions — same as KpiReportPolicy

Link generation in `InvestorKycNotifier`:
```ruby
signed_id = ApplicationRecord.signed_id_for_user(investor_kyc, user, expires_in: 30.days)
edit_investor_kyc_url(investor_kyc, signed_id: signed_id)
```

Expiry: **30 days** (KpiReport uses 15 days; KYC is more heavyweight so longer expiry is appropriate).

---

### Send Flow

```
Fund admin clicks "Send to Investor" (existing notify_kyc_required action)
    │
    ▼
investor_kyc.submission_status = 'link_sent'
investor_kyc.link_sent_at = Time.current
InvestorKycNotifier → email to all notification_users
  email includes: magic link (signed URL), expiry date, entity name
    │
    ▼
Investor clicks link (or logs in normally)
    │
    ▼
[Doc upload step if kyc_doc_first_wizard enabled — Part 1]
    │
    ▼
[KYC form — pre-filled if extraction ran, otherwise blank]
  → "Save Draft" button  → submission_status: draft_saved
  → "Submit KYC" button  → confirmation dialog → submission_status: completed
                                                → completed_by_investor = true
                                                → fund admin notified
    │
    ▼
Fund admin reviews, clicks "Verify"
    → submission_status: verified
    → verified = true
    → existing verified_by / expiry_date flow unchanged
```

---

### Investor-Facing Form Changes

When accessed via magic link or as a logged-in investor:

| State | Form behaviour |
|-------|----------------|
| `link_sent` | Fully editable, shows "Link Sent" status badge |
| `draft_saved` | Fully editable, shows "Draft Saved" status badge, "Last saved" timestamp |
| `completed` | Read-only. Shows "Submitted" badge, submitted_at timestamp. "KYC already submitted" notice. No Save/Submit buttons. |
| `verified` | Read-only. Shows "Verified" badge. |

Two action buttons (investor-facing only, hidden for fund admin):
- **Save Draft** — saves current values, sets status to `draft_saved`, redirects back to edit page
- **Submit KYC** — confirmation dialog ("This cannot be undone. Are you sure?"), sets status to `completed`, notifies fund admin

Fund admin's own Save button is **not** affected by the investor submit-guard — same pattern as KpiReport.

---

### Fund Admin Views

**Status badge** on KYC show page and index list:

| Status | Badge colour |
|--------|-------------|
| `not_sent` | Grey — "Not Sent" |
| `link_sent` | Blue — "Link Sent" |
| `draft_saved` | Yellow — "Draft Saved" |
| `completed` | Green — "Completed" |
| `verified` | Dark green — "Verified" |

**Actions available to fund admin per status:**

| Status | Available actions |
|--------|------------------|
| `not_sent` | Send Link |
| `link_sent` | Resend Link, Send Reminder |
| `draft_saved` | Send Reminder |
| `completed` | Verify, Request Updates (→ regresses to link_sent + fresh email) |
| `verified` | (none — locked) |

"Resend Link" re-uses `notify_kyc_required` action, regenerates a fresh signed link, resets `link_sent_at`.

"Request Updates" sets status back to `link_sent`, regenerates a fresh signed link, and emails the investor. The fund admin may include an **optional message** (free-text field shown in a modal before sending) that is included in the email body — e.g. "Please update your bank details and re-upload your PAN card." Mirrors the existing `updates_requested_notification` method but with status regression and a new magic link.

---

### Bulk Send

In addition to per-KYC send (existing `notify_kyc_required` action), fund admins can bulk-send from the KYC index.

- Multi-select KYC records on the index (existing bulk-action checkbox pattern)
- Bulk action: "Send KYC Link" — enqueues `SendKycFormJob` for each selected KYC that is in `not_sent`, `link_sent`, or `draft_saved` state
- KYCs in `completed` or `verified` state are silently skipped (same as KpiReport bulk-send skipping submitted portcos)
- A summary notice reports how many links were dispatched and how many were skipped

---

### Pending Dashboard (Investor-Facing)

New action `investor_pending` on `InvestorKycsController`, analogous to `portco_pending` on `KpiReportsController`.

Shows the logged-in investor all KYCs in `link_sent` or `draft_saved` state across all entities they have access to. Columns: entity name, form type, link sent date, current status, "Fill KYC" button.

Excludes `completed` and `verified` KYCs.

---

### Reminder Flow

`KycReminderJob` (already exists) is updated to:
- Skip KYCs in `completed` or `verified` state (no need to remind)
- For `link_sent` and `draft_saved`: send reminder email with a **fresh** signed link (existing link may be approaching expiry)
- Set `reminder_sent = true`, `reminder_sent_date = Time.current` (existing columns, unchanged)

---

### Notification on Investor Submission

When investor submits (status → `completed`), fund admin is notified via `InvestorKycNotifier` with `email_method: :notify_kyc_updated`. This reuses the existing `updated_notification` method — no new notifier class needed.

---

### Model / Schema Changes

| Change | Detail |
|--------|--------|
| `InvestorKyc` | New `submission_status` string column, default `'not_sent'` |
| `InvestorKyc` | New `link_sent_at` datetime column |
| `InvestorKyc` | New `submitted_at` datetime column (set when status → `completed`) |
| `InvestorKyc` | `completed_by_investor` and `verified` booleans — kept, synced by after_transition callbacks |
| `ApplicationRecord::SIGNED_ID_ALLOWED_MODELS` | Add `"InvestorKyc"` |
| `InvestorKycsController` | `skip_before_action :authenticate_user!` on `edit`/`update` when `params[:signed_id]` present |
| `InvestorKycsController` | `pundit_user` override |
| `InvestorKycPolicy` | Allow `edit?`/`update?` for `signed_id_access?` users on their own KYC |
| `InvestorKyc#send_kyc_form` | Set `submission_status = 'link_sent'`, `link_sent_at = Time.current` when email fires |
| `InvestorKycsController#update` | Resolve status transition from `params[:submit_action]` (same pattern as `KpiReportsController#resolve_status_transition`) |
| New scope | `InvestorKyc.pending_investor` → `where(submission_status: %w[link_sent draft_saved])` |
| `KycReminderJob` | Skip `completed` and `verified`; regenerate fresh signed link |

---

### Opt-In

**No opt-in required.** Status tracking and magic links apply to all tenants. The additions are purely additive — no existing behaviour is removed or altered. Fund admins gain status badges and the new action buttons; investors gain the option to fill via magic link without logging in.

---

### Edge Cases

| Scenario | Handling |
|----------|---------|
| Investor submits, fund admin clicks "Request Updates" | Status → `link_sent`, fresh magic link emailed with optional custom message; `completed_by_investor` reset to false |
| Expired magic link | Same inline error page as KpiReport: "This link has expired or is invalid" |
| Tampered magic link | `find_by_signed_id_for_user` returns nil → same inline error page |
| Investor submits, then tries to re-submit via magic link | Form shows locked "Submitted" state; no second notification fired |
| Fund admin edits a completed KYC (non-magic-link, authenticated) | Allowed; does not regress status to draft_saved |
| `reminder_sent` / `send_kyc_form_to_user` flag | Both preserved; `send_kyc_form_to_user` continues to trigger the send mechanism as before |
