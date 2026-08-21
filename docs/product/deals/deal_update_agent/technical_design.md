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

### Columns Added to Existing Tables

**`notes`** and **`tasks`**:
| Column | Type | Notes |
|--------|------|-------|
| `source_email_id` | bigint, nullable | FK → agent_ingested_emails |
| `created_by_agent` | boolean, default false | Audit flag |
| `match_tier` | string(2) | `A` (auto-filed), `M` (manually filed from warehouse) |

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
| `app/packs/misc/incoming_emails/controllers/incoming_emails_controller.rb` | SendGrid webhook — branches on `@updates.caphive.com` domain |
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
The SendGrid webhook POST hits `IncomingEmailsController#sendgrid`. The controller checks if the `to` address contains `@{DEAL_INGEST_DOMAIN}`. If yes, it delegates to `DealIngestAuthenticator` and returns `200 OK`.

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
- Create `Note` or `Task` on the matched `DealInvestor`
- Set `created_by_agent: true`, `match_tier: "A"`, `source_email: @email`
- Mark email as `filed` with confidence score

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
| `DEAL_INGEST_DOMAIN` | Domain for ingest email addresses | `updates.caphive.com` |

---

## DNS / Infrastructure Setup

1. **MX record**: `updates.caphive.com MX 10 mx.sendgrid.net`
2. **SendGrid Inbound Parse**: Add `updates.caphive.com` → webhook URL `https://app.caphive.com/incoming_emails/sendgrid`
3. Separate from existing `prod.caphive.app` inbound email domain

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

## Phase 2 — Planned Changes

### WhatsApp Channel
- Add a WhatsApp webhook handler alongside the email pipeline
- Reuse the same `DealIngestProcessor` orchestrator
- New `WhatsAppIngestAuthenticator` for sender verification via WhatsApp Business API
- Address mapping: phone number → (deal, user) instead of email address → (deal, user)

### Tier B Matching — Disambiguation
- When multiple stakeholders match above threshold, reply with a numbered list
- User replies with "1", "2", etc. to pick the correct match
- New status on `AgentIngestedEmail`: `awaiting_disambiguation`
- Track reply chain via `In-Reply-To` header matching

### Tier C Matching — Global Search
- If no match in deal's investors, search globally across the entity's Investor table
- If found, offer to attach the investor to the deal first, then create the note
- New `match_tier: "C"` for audit trail

### Attachments
- Extract attachments from SendGrid payload (`params[:attachments]`)
- Upload to S3 via Shrine, attach as Documents to the created Note
- Size/type validation (max 10MB, common document formats)

### Undo (30-day)
- Reply "undo" to a confirmation email within 30 days
- Match via `In-Reply-To` header → find the original `AgentIngestedEmail`
- Soft-delete the created Note/Task, mark email as `undone`

---

## Phase 3 — Future Changes

### New Stakeholder Creation
- If no match at any tier, offer to create a new Investor and DealInvestor
- Confirmation flow: "Create 'Goldman Sachs' as a new investor on this deal? Reply YES"
- New `match_tier: "N"` (new)

### Warehouse Bulk Actions
- Select multiple warehouse items via checkboxes
- Batch file (same stakeholder) or batch discard
- Turbo Stream updates for real-time UI

### Admin UI
- View all ingest addresses for an entity
- Usage stats: emails received, filed, warehoused, dropped per deal
- Address rotation: revoke and regenerate addresses
- Rate limiting configuration (Phase 2 PRD: 30/hour)

### Merge Tool
- Detect duplicate warehouse items (same sender + similar content within 24h)
- Offer to merge into a single note/task

---

## Phase 4 — Vision

### Slack Channel
- Slack bot integration: post to a deal-specific Slack channel
- Map Slack user → platform user via email match
- Same processor pipeline, different input adapter

### Known Limitations (to validate with real clients)

- **Malformed due dates in warehouse filing:** If the LLM stored an unparseable date string in `parse_json["due_date"]` (e.g. "TBD", "next Friday" unresolved), the warehouse resolution path creates the Task with `due_date: nil` silently. The user is not warned that the date was dropped. Acceptable for MVP since the LLM parser resolves relative dates at ingestion time, but should be revisited once real client usage reveals whether malformed dates occur in practice. Options: flash warning, inline date picker in the resolve form, or re-parse the date at filing time.

### AI Queries via MCP
- Surface the deal update agent as an MCP tool
- Users can ask: "What updates came in for Fund II this week?"
- Query across `agent_ingested_emails` and generated Notes/Tasks
- Integrate with the existing CapHive MCP server
