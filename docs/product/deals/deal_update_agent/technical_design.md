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
One address per deal — readable, optionally customizable by admins.

| Column | Type | Notes |
|--------|------|-------|
| `deal_id` | bigint, not null | FK → deals |
| `address` | string(100), not null | Default = `deal.id.to_s`, unique index |
| `created_at` | datetime | |
| `updated_at` | datetime | |

Indexes: unique on `address`, unique on `deal_id`.

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
| `app/packs/startups/deals/models/deal_ingest_address.rb` | Address model — generation, lookup, custom address validation |
| `app/packs/startups/deals/models/agent_ingested_email.rb` | Email audit record — status machine, parse storage |
| `app/packs/startups/deals/models/warehouse_item.rb` | Warehouse item — resolution, scopes |
| `app/packs/startups/deals/models/concerns/with_deal_ingest_address.rb` | Deal concern — auto-generates one address per deal on creation, lazy generation on page visit |

### Services
| File | Purpose |
|------|---------|
| `app/packs/startups/deals/services/deal_ingest_authenticator.rb` | 5-step auth: address→deal, From→user, deal access check (AccessRight or role), SPF/DKIM/DMARC, dedupe |
| `app/packs/ai/deal_update_agent/services/deal_email_parser.rb` | LLM parsing — structured JSON output (intent, stakeholder, body, due date) |
| `app/packs/startups/deals/services/deal_stakeholder_matcher.rb` | Tier A matching — Dice coefficient fuzzy, entity suffix stripping |
| `app/packs/startups/deals/services/deal_ingest_processor.rb` | Orchestrator — parse → match → create/warehouse → reply |

### Controllers
| File | Purpose |
|------|---------|
| `app/packs/misc/incoming_emails/controllers/incoming_emails_controller.rb` | SendGrid webhook — routes by `DealIngestAddress` lookup on local part |
| `app/packs/startups/deals/controllers/warehouse_items_controller.rb` | Warehouse UI — index (pending items), resolve (file/discard) |
| `app/packs/startups/deals/controllers/deals_controller.rb` | Deal show — lazy ingest address generation via `ensure_deal_ingest_address` |

### Jobs
| File | Purpose |
|------|---------|
| `app/packs/startups/deals/jobs/process_deal_ingest_job.rb` | Sidekiq wrapper — Chewy strategy, discard on RecordNotFound |

### Mailers
| File | Purpose |
|------|---------|
| `app/packs/startups/deals/mailers/deal_ingest_mailer.rb` | Confirmation reply email only (warehouse notification removed) |

### Policies
| File | Purpose |
|------|---------|
| `app/packs/startups/deals/policies/deal_policy.rb` | Pundit policy — includes `update_ingest_address?` for admin address editing |

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
| `app/javascript/controllers/inline_edit_controller.js` | Stimulus controller for inline address editing |

### Cucumber Features
| File | Purpose |
|------|---------|
| `features/deal/deal_update_agent_v2.feature` | 14 scenarios — happy path, security drops, warehouse, resolution, address management |
| `features/step_definitions/deal_update_agent_v2/setup_steps.rb` | Before/After hooks, LLM stub, fixture setup |
| `features/step_definitions/deal_update_agent_v2/authentication_steps.rb` | Webhook simulation, drop assertions |
| `features/step_definitions/deal_update_agent_v2/processing_steps.rb` | LLM stubbing, job execution, Note/Task assertions |
| `features/step_definitions/deal_update_agent_v2/warehouse_steps.rb` | Warehouse preconditions, resolve/discard assertions |
| `features/step_definitions/deal_update_agent_v2/address_steps.rb` | Address generation, custom address editing assertions |

---

## Processing Pipeline

### Step 1: Inbound Webhook
The SendGrid webhook POST hits `IncomingEmailsController#sendgrid`. The controller extracts the local part from the `to` address and checks for a matching `DealIngestAddress` record. If found, it delegates to `DealIngestAuthenticator` and returns `200 OK`. This address-based routing allows the deal update pipeline to share the same email domain as regular incoming emails.

### Step 2: Authentication (`DealIngestAuthenticator`)
5-step authentication pipeline — each failure drops silently (never reply, FR-4):

1. Look up the `to` address in `deal_ingest_addresses` → get `deal_id`
2. Not found → **drop silently**
3. Look up user by `From` email in the deal's entity (`User.find_by(email:, entity_id:)`)
4. Not found → **drop silently**
5. Check user has deal access (`AccessRight` for the deal, or `company_admin` role on the entity)
6. No access → **drop silently**
7. Check SPF/DKIM/DMARC from SendGrid payload headers
8. Fail → **drop silently**
9. Dedupe on RFC-822 `Message-ID` (unique index on `agent_ingested_emails.message_id`)
10. Create `AgentIngestedEmail` record (status: `pending`), enqueue `ProcessDealIngestJob`

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
- **Warehouse** → no notification (sender is NOT notified; users check warehouse tab themselves)

---

## Address Generation

### One Address Per Deal

The `WithDealIngestAddress` concern is included in `Deal` (not `AccessRight`). Each deal has exactly one ingest address (`has_one :deal_ingest_address`).

### Two Triggers

1. **Auto-generation on deal creation** — `after_commit :create` on the deal generates a `DealIngestAddress` with `address = deal.id.to_s`.

2. **Lazy generation on page visit** — `ensure_deal_ingest_address` in `DealsController#show` creates the address if it does not exist (covers deals created before the feature was deployed). Uses `ActiveRecord::Base.connected_to(role: :writing)` to bypass read replica.

### Custom Addresses

- Only `company_admin` users can edit a deal's address via inline edit UI on the deal page
- Address is validated for uniqueness and format (alphanumeric, hyphens, underscores, max 100 chars)
- Authorized via `DealPolicy#update_ingest_address?`
- No revocation concept — the address is per-deal and is never revoked or soft-deleted

---

## Security Rules

| Rule | Implementation |
|------|----------------|
| FR-2: Unknown address → drop | `DealIngestAuthenticator#authenticate_address` — address → deal lookup, unknown address → drop |
| FR-3: Sender auth + deal access | From → user lookup in entity, then check deal access (AccessRight or `company_admin` role), then SPF/DKIM/DMARC |
| FR-4: Failed auth → no reply | Early return with `Result.new(status: :dropped)`, no mailer call |
| FR-5: Only company_admin can edit deal address | `DealPolicy#update_ingest_address?` — enforced in controller and inline edit UI |
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

**Feature gate behavior:** `DealIngestAddress.domain` returns `nil` when the env var is absent. All callers guard on `DealIngestAddress.domain.present?` / `.blank?` — the deal page and deal creation callbacks skip address generation silently. This ensures the feature is invisible on any environment where SendGrid is not configured.

**Routing note:** The inbound webhook does NOT check the domain. It extracts the local part from the To field and looks up `DealIngestAddress` directly. This allows the deal update pipeline to share the same email domain as regular incoming emails — no separate subdomain or MX record is needed.

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

### Cucumber Features (`features/deal/deal_update_agent_v2.feature`)

14 scenarios tagged `@deal_update_agent`, organized into five groups:

| Group | Scenarios | What's Tested |
|-------|-----------|---------------|
| **Happy path** | 2 | Meeting note creation, task creation with due date |
| **Security drops** | 5 | Unknown address, unknown sender, no deal access, SPF/DKIM fail, duplicate Message-ID |
| **Warehouse** | 2 | Unknown stakeholder → warehouse, unknown intent → warehouse |
| **Resolution** | 2 | Manual file from warehouse, discard from warehouse |
| **Address management** | 3 | Auto-generation on deal creation, lazy generation on page visit, custom address editing |

### Test Setup

- **LLM**: Stubbed via `allow(DealEmailParser).to receive(:call)` — returns controlled JSON per scenario
- **Queue**: Uses ActiveJob `:test` adapter so jobs are not executed immediately; explicit `DealIngestProcessor.call` in "When the job is performed" step
- **Chewy**: Bypassed via `Chewy.strategy(:bypass)`
- **Mailers**: Verified via `ActionMailer::Base.deliveries` inspection

### Running

```bash
bundle exec cucumber features/deal/deal_update_agent_v2.feature          # all 14 scenarios
bundle exec cucumber features/deal/deal_update_agent_v2.feature:16       # single scenario by line
bundle exec cucumber --tags @deal_update_agent                           # by tag
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
- When authentication fails (sender has no deal access), alert the deal's admin users
- New mailer template: `DealIngestMailer#leak_alert`
- Sent to deal admins (not the sender) — "Someone tried to use the deal update address from an unauthorized email"
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
- Generates a `.vcf` file with display name "[Deal Name] — Deal Board" and the deal's ingest address
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
- Address reset: change a deal's custom address back to the default (deal ID)
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
- Address reset from admin UI (FR-8)

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
