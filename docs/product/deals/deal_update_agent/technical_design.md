# Deal Update Agent — Technical Design

## Architecture Overview

The Deal Update Agent is an email ingestion pipeline that processes inbound emails via SendGrid webhook, parses them with an LLM, matches stakeholders using fuzzy string matching, and creates Notes or Tasks on the deal board.

```
Email → SendGrid → Webhook POST → Auth → Sidekiq Job → LLM Parse → Match → Create Note/Task → Reply Email
                                    ↓ (fail)                           ↓ (no match)
                                  Drop silently                     Warehouse → Manual filing UI
```

---

## Data Model

### New Tables

#### `deal_ingest_addresses`
Per-(deal, user) unguessable email address.

| Column | Type | Notes |
|--------|------|-------|
| `deal_id` | bigint, not null | FK → deals |
| `user_id` | bigint, not null | FK → users |
| `address` | string(16), not null | `SecureRandom.hex(8)`, unique index |
| `revoked_at` | datetime, nullable | Set on access revocation, never deleted |
| `created_at` | datetime | |
| `updated_at` | datetime | |

Indexes: unique on `address`, unique on `[deal_id, user_id]`.

#### `agent_ingested_emails`
Audit log of every authenticated inbound email.

| Column | Type | Notes |
|--------|------|-------|
| `deal_id` | bigint, not null | FK → deals |
| `sender_user_id` | bigint, not null | FK → users |
| `message_id` | string, not null | RFC-822 Message-ID for deduplication, unique index |
| `raw_payload` | text | Email body (HTML or plain text) |
| `received_at` | datetime, not null | |
| `status` | string(20), default "pending" | `pending` → `filed` / `warehoused` / `dropped` |
| `parse_json` | json | LLM structured output |
| `confidence` | decimal(5,2) | Match confidence score (0.00–1.00) |
| `match_tier` | string(2) | `A` (auto), `M` (manual), future: `B`/`C` |

#### `warehouse_items`
Parking lot for emails that couldn't be auto-filed.

| Column | Type | Notes |
|--------|------|-------|
| `agent_ingested_email_id` | bigint, not null | FK → agent_ingested_emails |
| `deal_id` | bigint, not null | FK → deals (denormalized for query performance) |
| `parsed_intent` | string(20) | `meeting_note` / `task` / `unknown` |
| `candidate_stakeholder_ids` | json | Array of DealInvestor IDs that partially matched |
| `resolved_at` | datetime, nullable | Null until manually resolved |
| `resolved_by_id` | bigint, nullable | FK → users |
| `resolution` | string(20) | `filed` / `discarded` |

### Polymorphic Link on `agent_ingested_emails`

The agent-to-item link lives on `agent_ingested_emails` via a polymorphic `filed_as` association — the agent email points to the Note or Task it created. No columns are added to the `notes` or `tasks` tables; core models have zero knowledge of the agent system.

| Column | Type | Notes |
|--------|------|-------|
| `filed_as_type` | string, nullable | `"Note"` or `"Task"` (set on filing) |
| `filed_as_id` | bigint, nullable | FK to the created note or task record |

- `filed_as` is `nil` when the email is warehoused or dropped
- To check if a note was agent-created: `AgentIngestedEmail.where(filed_as: note).exists?`

---

## Key Files

### Models
| File | Purpose |
|------|---------|
| `app/packs/startups/deals/models/deal_ingest_address.rb` | Address model — generation, revocation, lookup |
| `app/packs/startups/deals/models/agent_ingested_email.rb` | Email audit record — status machine, parse storage |
| `app/packs/startups/deals/models/warehouse_item.rb` | Warehouse item — resolution, scopes |
| `app/packs/startups/deals/models/concerns/with_deal_ingest_address.rb` | AccessRight concern — auto-generate/revoke on access changes |

### Services
| File | Purpose |
|------|---------|
| `app/packs/startups/deals/services/deal_ingest_authenticator.rb` | Auth: address lookup, sender match, SPF/DKIM/DMARC, dedup, enqueue |
| `app/packs/ai/deal_update_agent/services/deal_email_parser.rb` | LLM parsing — structured JSON output (intent, stakeholder, body, due date) |
| `app/packs/startups/deals/services/deal_stakeholder_matcher.rb` | Tier A matching — Dice coefficient fuzzy, entity suffix stripping |
| `app/packs/startups/deals/services/deal_ingest_processor.rb` | Orchestrator — parse → match → create/warehouse → reply |

### Controllers
| File | Purpose |
|------|---------|
| `app/packs/misc/incoming_emails/controllers/incoming_emails_controller.rb` | SendGrid webhook — routes by DealIngestAddress lookup on local part |
| `app/packs/startups/deals/controllers/warehouse_items_controller.rb` | Warehouse UI — index (pending items), resolve (file/discard) |
| `app/packs/startups/deals/controllers/deals_controller.rb` | Deal show — lazy ingest address generation via `ensure_deal_ingest_address` |

### Jobs
| File | Purpose |
|------|---------|
| `app/packs/startups/deals/jobs/process_deal_ingest_job.rb` | Sidekiq wrapper — Chewy strategy, discard on RecordNotFound |

### Mailers
| File | Purpose |
|------|---------|
| `app/packs/startups/deals/mailers/deal_ingest_mailer.rb` | Confirmation + warehoused reply emails |

### Views
| File | Purpose |
|------|---------|
| `app/packs/startups/deals/views/deals/_deal_ingest_address.html.erb` | Address display with copy button and tooltip |
| `app/packs/startups/deals/views/deals/_list_view_header.html.erb` | Deal header — renders ingest address partial |
| `app/packs/startups/deals/views/warehouse_items/index.html.erb` | Warehouse items table with Turbo Frame |
| `app/packs/startups/deals/views/warehouse_items/_resolve_form.html.erb` | File/discard controls for each item |

### JavaScript
| File | Purpose |
|------|---------|
| `app/javascript/controllers/clipboard_controller.js` | Copy-to-clipboard with HTTP fallback |

### Cucumber Features
| File | Purpose |
|------|---------|
| `features/deal/deal_update_agent.feature` | 11 scenarios — happy path, security drops, warehouse, resolution |
| `features/step_definitions/deal_update_agent/shared_setup_steps.rb` | Before/After hooks, LLM stub, fixture setup |
| `features/step_definitions/deal_update_agent/authentication_steps.rb` | Webhook simulation, drop assertions |
| `features/step_definitions/deal_update_agent/processing_steps.rb` | LLM stubbing, job execution, Note/Task assertions |
| `features/step_definitions/deal_update_agent/warehouse_steps.rb` | Warehouse preconditions, resolve/discard assertions |

---

## Processing Pipeline

### Step 1: Inbound Webhook
The SendGrid webhook POST hits `IncomingEmailsController#sendgrid`. The controller extracts the local part (16-hex token) from the `to` address and checks for a matching `DealIngestAddress` record. If found, it delegates to `DealIngestAuthenticator` and returns `200 OK`. This address-based routing allows the deal update pipeline to share the same email domain as regular incoming emails.

### Step 2: Authentication (`DealIngestAuthenticator`)
1. Look up the `to` address in `deal_ingest_addresses` → get `(deal_id, user_id)`
2. Not found or revoked → **drop silently** (never reply, FR-4)
3. Match the `from` email against the address owner's email (case-insensitive)
4. Mismatch → **drop silently**
5. Check SPF/DKIM/DMARC from SendGrid payload headers
6. Fail → **drop silently**
7. Dedupe on RFC-822 `Message-ID` (unique index on `agent_ingested_emails.message_id`)
8. Duplicate → **skip**
9. Create `AgentIngestedEmail` record (status: `pending`)
10. Enqueue `ProcessDealIngestJob`

### Step 3: LLM Parsing (`DealEmailParser`)
Sends the email body to the LLM with a structured prompt. Returns:
```json
{
  "intent": "meeting_note | task | unknown",
  "stakeholder_string": "Sequoia Capital",
  "body": "cleaned note text",
  "due_date": "2026-09-01",
  "due_date_source_text": "in two weeks"
}
```
If intent is `unknown` → **warehouse** immediately.

### Step 4: Stakeholder Matching (`DealStakeholderMatcher`)
Tier A only (MVP): match against the deal's `DealInvestors`.

**Normalization** (both sides):
- Lowercase, strip diacritics, remove punctuation
- Strip entity suffixes: Ltd, LLC, Inc, LP, GmbH, Capital, Partners, Ventures, etc.

**Matching**:
- Exact normalized match → auto-file
- Single fuzzy match ≥ 0.85 (Dice coefficient) → auto-file
- Multiple matches above threshold or no match → **warehouse**

### Step 5: Create Note/Task
Wrapped in `ActiveRecord::Base.transaction` with `Chewy.strategy(:atomic)`:
- Create `Note` or `Task` on the matched `DealInvestor` (clean creation — no agent columns on the record)
- Mark email as `filed` with confidence score, match tier `"A"`, and `filed_as:` pointing to the created item

### Step 6: Reply Email
- **Success** → confirmation email with what was created
- **Warehouse** → warehouse notification with reason

---

## Address Generation

### Two Triggers

1. **`WithDealIngestAddress` concern** (on `AccessRight`) — auto-generates on `after_commit :create`, revokes on `after_destroy_commit`. Only for user-level AccessRights on Deal owners.

2. **Lazy generation** (in `DealsController#show`) — `ensure_deal_ingest_address` creates the address on first deal page visit. Uses `ActiveRecord::Base.connected_to(role: :writing)` to bypass read replica. Covers role-based access (e.g., `company_admin`) where no AccessRight exists.

### Revocation
When an AccessRight is destroyed, the address is soft-revoked (`revoked_at` set). If access is later re-granted, the existing row is reactivated (MySQL's unconditional unique index on `[deal_id, user_id]` prevents creating a new row).

---

## Security Rules

| Rule | Implementation |
|------|----------------|
| FR-2: Unknown/revoked address → drop | `DealIngestAuthenticator#authenticate_address` — `for_lookup` scope excludes revoked |
| FR-3: Sender must match + SPF/DKIM/DMARC | `verify_sender` + `verify_email_auth` in authenticator |
| FR-4: Failed auth → no reply | Early return with `Result.new(status: :dropped)`, no mailer call |
| FR-5: Revoking access revokes address | `WithDealIngestAddress#revoke_deal_ingest_address` in same `after_destroy_commit` |
| FR-15: Message-ID dedup | Unique index on `agent_ingested_emails.message_id` |

---

## Idempotency & Error Handling

- **Job retry safety**: `DealIngestProcessor#process` checks `@email.reload.status != "pending"` before processing. Sidekiq retries are safe.
- **Transaction wrapping**: Note/Task creation + `mark_filed!` are in a single transaction. Partial state is impossible.
- **Deleted records**: `discard_on ActiveRecord::RecordNotFound` on the job prevents 25 futile retries.
- **LLM failures**: Caught by the rescue block in `process`, email marked as `dropped`.
- **Chewy indexing**: Job wraps processing in `Chewy.strategy(:atomic)`.

---

## Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `DEAL_INGEST_DOMAIN` | Domain for ingest email addresses. Used to compose the `full_address` shown on the deal page and in confirmation emails. **No fallback** — when not set, the feature is completely hidden (no addresses shown, no generation callbacks fire). | None |

**Feature gate behavior:** `DealIngestAddress.domain` returns `nil` when the env var is absent. All callers guard on `DealIngestAddress.domain.present?` / `.blank?` — the deal page and AccessRight callbacks skip agent logic silently. This ensures the feature is invisible on any environment where SendGrid is not configured.

**Routing note:** The inbound webhook does NOT check the domain. It extracts the local part (hex token) from the To field and looks up `DealIngestAddress` directly. This allows the deal update pipeline to share the same email domain as regular incoming emails — no separate subdomain or MX record is needed.

| Environment | Value | Effect |
|-------------|-------|--------|
| Staging | `dev.caphive.app` | Feature active, shares existing SendGrid Inbound Parse setup |
| Production | *(not set until ready)* | Feature hidden — no addresses shown, no ingest processing |
| Production (future) | `prod.caphive.app` | Feature active, shares existing SendGrid Inbound Parse setup |

---

## DNS / Infrastructure Setup

No additional DNS or SendGrid configuration is required. The deal update pipeline reuses the existing Inbound Parse setup:

| Environment | Existing Domain | Existing Webhook | Shared? |
|-------------|----------------|------------------|---------|
| Staging | `dev.caphive.app` | `https://dev.altconnects.com/incoming_emails/sendgrid` | Yes |
| Production | `prod.caphive.app` | `https://app.caphive.com/incoming_emails/sendgrid` | Yes |

The controller routes by address lookup (one indexed DB query per inbound email) rather than by domain. Emails whose local part matches a `DealIngestAddress` go to the deal update pipeline; all others fall through to the existing `IncomingEmail` flow.

---

## Testing

### Cucumber Features (`features/deal/deal_update_agent.feature`)

11 scenarios tagged `@deal_update_agent`, organized into four groups:

| Group | Scenarios | What's Tested |
|-------|-----------|---------------|
| **Happy path** | 2 | Meeting note creation, task creation with due date |
| **Security drops** | 5 | Unknown address, sender mismatch, SPF/DKIM fail, duplicate Message-ID, revoked address |
| **Warehouse** | 2 | Unknown stakeholder → warehouse, unknown intent → warehouse |
| **Resolution** | 2 | Manual file from warehouse, discard from warehouse |

### Test Setup

- **LLM**: Stubbed via `allow(DealEmailParser).to receive(:call)` — returns controlled JSON per scenario
- **Queue**: Uses ActiveJob `:test` adapter so jobs are not executed immediately; explicit `DealIngestProcessor.call` in "When the job is performed" step
- **Chewy**: Bypassed via `Chewy.strategy(:bypass)`
- **Mailers**: Verified via `ActionMailer::Base.deliveries` inspection

### Running

```bash
bundle exec cucumber features/deal/deal_update_agent.feature          # all 11 scenarios
bundle exec cucumber features/deal/deal_update_agent.feature:16       # single scenario by line
bundle exec cucumber --tags @deal_update_agent                        # by tag
```

---

## Phase 2 — Building

### Tier B Matching — Disambiguation (FR-17, §6.2)
- When 2+ deal-attached stakeholders score ≥ 0.75 (or single 0.75–0.90), reply with a numbered list
- User replies with "1", "2", "0" (none) from their email client
- New status on `AgentIngestedEmail`: `pending_disambiguation`
- Track reply chain via `In-Reply-To` header matching against pending emails
- No reply within 48h → warehouse, sender notified once
- New mailer template: `DealIngestMailer#disambiguation`

### Tier C Matching — Global Search (FR-17-20, §6.3)
- If no match among deal-attached DealInvestors, search Investor table scoped by sender's org_id
- Higher threshold (≥ 0.95) — global table has thousands of records vs 5–40 on a deal
- Single global match → reply asking user to confirm attach + file (never auto-attach)
- New status on `AgentIngestedEmail`: `pending_attach_confirm`
- On "YES" reply: create DealInvestor association + file the note/task as one atomic action
- New mailer template: `DealIngestMailer#attach_confirm`
- New `match_tier: "C"` for audit trail
- Confirmation shows stakeholder name, known domains, and how many other deals they appear on

### Signature/Reply Chain Stripping (FR-11)
- New `EmailBodySanitizer` service (or method in DealEmailParser) runs before the LLM call
- Strips: quoted reply chains (`On Mon, ... wrote:`), signature blocks (`--`), legal disclaimers, "Sent from my iPhone/Android", tracking pixels
- Raw original preserved on `agent_ingested_emails.raw_payload` for reference

### Auto-Reply Detection (FR-23)
- New check in `DealIngestAuthenticator` after dedupe step
- Inspect `Auto-Submitted:` and `Precedence:` headers
- Auto-generated emails → drop silently (prevents mail loops with OOO responders)

### Rate Limiting (FR-6)
- Max 30 emails/hour per address
- Counter in Redis (per address key, 1-hour TTL window)
- Check in `DealIngestAuthenticator` after address lookup
- Excess emails queued (not dropped), processed when window resets
- Sender notified once per rate-limit event
- New mailer template: `DealIngestMailer#rate_limited`

### Leak Alert (FR-3)
- When `verify_sender` fails (From email doesn't match address owner), alert the address owner
- New mailer template: `DealIngestMailer#leak_alert`
- Sent to the address owner (not the sender) — "Someone tried to use your deal update address from a different email"
- Email is still dropped per existing FR-4 rules

### Undo — 30-day (FR-31-32)
- Confirmation email includes a signed "Undo" link (MessageVerifier token with 30-day expiry)
- New controller action: `DealIngestUndoController#undo`
- Undo returns the item to warehouse rather than deleting
- New field on `AgentIngestedEmail`: `undone_at` (datetime)
- Compound undo: if the email also attached a stakeholder via Tier C, undo reverses both — unless the stakeholder has since acquired other activity on the deal (then undo item only, explain in response)

### Agent-Created Badge (FR-30)
- New field on `AgentIngestedEmail`: `agent_reviewed_at` (datetime, null until human views/edits)
- Board partials show "AI" badge when `filed_as` exists and `agent_reviewed_at.nil?`
- Badge cleared when a user views the note/task detail page (set via controller callback)

### Attachments (FR-33)
- Extract attachments from SendGrid webhook payload
- Upload to deal's document store via existing Shrine + S3 infrastructure
- Link documents to the created Note/Task
- Respect existing file type/size limits
- Rejected attachments noted in confirmation reply ("1 attachment skipped — exceeds 10MB limit")
- Attachment metadata stored on `AgentIngestedEmail` for audit

### 72h Warehouse Digest (FR-27)
- New sidekiq-cron job (daily): `WarehouseDigestJob`
- Query `warehouse_items.pending.where("created_at < ?", 72.hours.ago)`, group by deal + sender
- New mailer: `DealIngestMailer#warehouse_digest` — "You have 3 items waiting for Deal X"
- Badge/counter on deal page next to the warehouse tab

### VCF Contact Card (FR-7)
- New controller action on `DealsController`: `download_vcf`
- Generates a `.vcf` file with display name "[Deal Name] — Deal Board" and the user's ingest address
- Download button on deal page next to the copy button
- Makes the address autocomplete on phones — key adoption driver

---

## Phase 3 — Planned

### New Stakeholder Creation (PRD §11)
- If no match at any tier, offer to create a new Investor via email domain dedupe
- Domain matches existing stakeholder → Tier C flow (confirm attach, don't create)
- No domain match → create as pending/unverified, one confirmation tap to promote
- Free-mail domains (gmail.com, outlook.com) → warehouse for manual creation
- New `match_tier: "N"` (new)
- Depends on: stakeholders.email_domains, merge tool

### Warehouse Bulk Actions
- Select multiple warehouse items via checkboxes
- Batch file (same stakeholder) or batch discard
- Turbo Stream updates for real-time UI

### Admin UI
- View all ingest addresses for an entity
- Usage stats: emails received, filed, warehoused, dropped per deal
- Address rotation: revoke and regenerate addresses
- Dropped-mail log for admin review

### Merge Tool
- Stakeholder merge (not warehouse item merge) — safety net for domain-based creation
- Required because stakeholders are org-wide: a bad duplicate pollutes every deal

### Multi-item Per Email (FR-10)
- Single email producing multiple notes/tasks
- Parser returns `items[]` array instead of single item

### Additional Parsing Enhancements
- @name assignee parsing (FR-13) — assign to another deal team member
- Sender timezone date resolution (FR-12) — resolve relative dates in sender's TZ
- mailto: button on deal page (FR-7) — "Email this deal" producing mailto link
- Address rotation from admin UI (FR-8)

---

## Phase 4 — Vision

### WhatsApp Channel (PRD §9.2)
- WhatsApp forward ingestion — new channel adapter
- Phone number → user mapping (verified phone → user_id)
- Same processor pipeline, different input adapter
- Shorter/more elliptical messages — per-channel confidence thresholds

### Slack Channel
- Slack bot integration: post to a deal-specific Slack channel
- Map Slack user → platform user via email match
- Strip surrounding thread context (similar to quoted reply stripping)

### Known Limitations (to validate with real clients)

- **Malformed due dates in warehouse filing:** If the LLM stored an unparseable date string in `parse_json["due_date"]` (e.g. "TBD", "next Friday" unresolved), the warehouse resolution path creates the Task with `due_date: nil` silently. The user is not warned that the date was dropped. Acceptable for MVP since the LLM parser resolves relative dates at ingestion time, but should be revisited once real client usage reveals whether malformed dates occur in practice. Options: flash warning, inline date picker in the resolve form, or re-parse the date at filing time.

### AI Queries via MCP
- Surface the deal update agent as an MCP tool
- Users can ask: "What updates came in for Fund II this week?"
- Query across `agent_ingested_emails` and generated Notes/Tasks
- Integrate with the existing CapHive MCP server
