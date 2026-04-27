# E-Signing System

IRM supports electronic signatures on documents via two integrated providers — **Digio** (default) and **DocuSign**. This document covers the data model, workflow, provider integration, and infrastructure.

---

## Table of Contents

1. [Overview](#overview)
2. [Data Models](#data-models)
3. [Document–ESignature Relationship](#document-esignature-relationship)
4. [Provider Configuration](#provider-configuration)
5. [End-to-End Workflow](#end-to-end-workflow)
6. [Sending for Signature](#sending-for-signature)
7. [Status Updates](#status-updates)
8. [Completion Flow](#completion-flow)
9. [Template System](#template-system)
10. [Capital Commitment Integration](#capital-commitment-integration)
11. [Routes & API](#routes--api)
12. [Background Jobs](#background-jobs)
13. [Authorization & Permissions](#authorization--permissions)
14. [Status Reference](#status-reference)

---

## Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                         IRM E-Signing System                         │
│                                                                      │
│  Document ──has_many──► ESignature (one per signer)                  │
│     │                                                                │
│     ├── sent_for_esign: bool                                         │
│     ├── esign_status: string                                         │
│     ├── provider_doc_id: string                                      │
│     └── force_esign_order: bool (sequential signing)                 │
│                                                                      │
│  EsignLog ──belongs_to──► Document  (audit: request/response/webhook)│
│                                                                      │
│  Provider config lives in EntitySetting.esign_provider               │
│  (per-entity: "Digio" or "Docusign")                                 │
└──────────────────────────────────────────────────────────────────────┘
```

The system supports:
- **Sequential signing** (each signer must sign before the next is notified)
- **Parallel signing** (all signers notified simultaneously)
- **Aadhaar** and **DSC** signature types
- **E-stamp** integration (Indian stamp paper embedded in PDF)
- **Webhook** callbacks for real-time status updates
- **Polling** fallback via scheduled jobs

---

## Data Models

### `ESignature`

**File:** `app/packs/core/documents/models/e_signature.rb`

Represents one signatory slot for a document.

| Column         | Type    | Description                                         |
|----------------|---------|-----------------------------------------------------|
| `document_id`  | bigint  | Parent document                                     |
| `entity_id`    | bigint  | Entity (fund manager) scoping                       |
| `user_id`      | bigint  | Linked IRM user (optional — nil for template slots) |
| `email`        | string  | Signer's email address (max 60 chars)               |
| `label`        | string  | Human label e.g. "Investor Signatory" (max 50)      |
| `signature_type`| string | `"aadhaar"` or `"dsc"`                              |
| `status`       | string  | See [Status Reference](#status-reference)           |
| `position`     | integer | Signing order (via `acts_as_list`)                  |
| `notes`        | text    | Notes / fallback email for template slots           |
| `api_updates`  | text    | Cumulative raw API callback payloads                |

Key behaviors:
- Email is normalised (whitespace stripped).
- Emails must be unique per document.
- Labels must be unique per document+signature_type on template documents.
- Changing `signature_type` clears `status`.
- Saving an ESignature sets `document.signature_enabled = true`.

### `Document` (esign fields)

**Concern:** `app/packs/core/documents/models/concerns/with_e_signatures.rb`

| Column              | Type     | Description                                              |
|---------------------|----------|----------------------------------------------------------|
| `sent_for_esign`    | boolean  | Whether send has been triggered (guards re-sends)        |
| `sent_for_esign_date` | datetime | Timestamp of send                                      |
| `esign_status`      | string   | Aggregate document status                               |
| `provider_doc_id`   | string   | Provider's identifier for the document                  |
| `force_esign_order` | boolean  | Sequential (true) vs parallel (false) signing           |
| `display_on_page`   | string   | Where to place signature — `"last"` or `"first"`        |
| `signature_enabled` | boolean  | Whether e-signatures are configured                     |

Document scopes:
```ruby
Document.sent_for_esign
Document.not_sent_for_esign
Document.esign_status_completed
Document.esign_status_failed
Document.esign_status_requested
Document.esign_status_all
Document.signed  # owner_tag: "Signed"
```

Helper predicates:
```ruby
document.esign_completed?          # status == "completed"
document.esign_expired?            # status in ["expired", "cancelled"]
document.esign_failed?             # status == "failed"
document.esign_voided?             # status == "voided"
document.eligible_for_esign_update?  # status NOT in SKIP list
document.resend_for_esign?         # validates eligibility for resend
document.to_be_esigned?            # ready for signing check
```

### `EsignLog`

**File:** `app/packs/core/documents/models/esign_log.rb`

Audit trail — one log per document, updated in-place.

| Column               | Type | Description                             |
|----------------------|------|-----------------------------------------|
| `document_id`        | bigint | Parent document                       |
| `entity_id`          | bigint | Entity scoping                        |
| `request_data`       | json | Payload sent to provider (send)         |
| `response_data`      | json | Provider response to send              |
| `webhook_data`       | json | Incoming webhook payloads              |
| `manual_update_data` | json | Results from manual status polls       |

Retention:
- Logs older than **91 days** are deleted (all states).
- Logs for **completed** documents are deleted after **10 days** from completion.

---

## Document–ESignature Relationship

```
Document
  │
  ├── has_many :e_signatures   (ordered by :position)
  │     ├── ESignature [position=1, email="lp@fund.com",  label="Investor Signatory", status="signed"]
  │     ├── ESignature [position=2, email="gp@fund.com",  label="Fund Signatory",     status="requested"]
  │     └── ESignature [position=3, email="ops@fund.com", label="Other",              status=nil]
  │
  ├── has_many :stamp_papers
  └── has_one  :esign_log
```

When `force_esign_order: true`, the provider (Digio) notifies each signer only after the previous has signed. Position determines the order.

---

## Provider Configuration

Provider is configured **per entity** in `EntitySetting`:

```
EntitySetting
  ├── esign_provider: "Digio" | "Docusign"   (default: "Digio")
  ├── digio_client_id
  ├── digio_client_secret
  ├── digio_cutover_date       (switch auth token at this date)
  └── digio_auth_token         (post-cutover entity-specific token)
```

The `EsignHelper` factory resolves the provider at runtime:

```ruby
# app/packs/core/investor_kycs/models/helper/esign_helper.rb

EsignHelper.new(doc)
# → reads doc.entity.entity_setting.esign_provider
# → instantiates DigioEsignHelper or DocusignEsignHelper
```

---

## End-to-End Workflow

### Single Document

```
User clicks "Send for eSign"
         │
         ▼
DocumentsController#send_for_esign
 - Authorises via ESignaturePolicy
 - Calls document.send_for_esign(force:, user_id:)
         │
         ▼
Document#send_for_esign
 - Guards: signature_enabled? AND (!sent_for_esign OR force)
 - Enqueues EsignJob.perform_later(doc.id, user_id)
         │
         ▼
EsignJob#perform
 - Calls EsignHelper.new(doc, user_id:).sign
 - Sends user notification (success/danger UserAlert)
         │
         ▼
EsignHelper#sign
 - Calls DigioEsigning.call(...) or DocusignEsigning.call(...)
         │
         ├─── DIGIO ─────────────────────────────────────────────┐
         │    DigioEsigning (Trailblazer operation)              │
         │      step :validate_doc_size   (<25 MB check)        │
         │      step :send_document_for_esign                   │
         │        - Downloads file, Base64 encodes               │
         │        - POST to Digio API                            │
         │        - Stores request/response in EsignLog          │
         │      step :update_document                            │
         │        - doc.sent_for_esign = true                    │
         │        - doc.esign_status   = "requested"             │
         │        - doc.provider_doc_id = response[:id]          │
         │        - doc.sent_for_esign_date = Time.now           │
         └───────────────────────────────────────────────────────┘
         │
         └─── DOCUSIGN ──────────────────────────────────────────┐
              DocusignEsigning (Trailblazer operation)           │
                - DocusignSigningViaEmailService                 │
                - JWT auth via JwtAuth::JwtCreator               │
                - Creates envelope, adds PDF + recipients        │
                - doc.esign_status = "requested"                 │
                - doc.provider_doc_id = envelope_id              │
              └──────────────────────────────────────────────────┘
```

### Folder / Bulk Send

```
User clicks "Send All for eSign" (folder-level)
         │
         ▼
DocumentsController#send_all_for_esign
 - Enqueues EsignJob.perform_later(nil, user_id, folder_id:)
         │
         ▼
EsignJob#send_documents_for_esign(folder_id, user_id)
 - Finds all descendant folder_ids
 - Filters: not_template, not_sent_for_esign, generated, approved
 - Excludes: esign_status in SKIP_ESIGN_UPDATE_STATUSES
 - For each doc:
     EsignJob.set(wait: rand(count * 15).seconds).perform_later(doc.id, user_id)
     (randomised delay to avoid provider rate limits)
```

---

## Sending for Signature

### Digio API Request

```json
{
  "signers": [
    { "identifier": "investor@example.com", "sign_type": "aadhaar" },
    { "identifier": "gp@fund.com",          "sign_type": "dsc"     }
  ],
  "expire_in_days": 90,
  "notify_signers": true,
  "send_sign_link": true,
  "generate_access_token": false,
  "display_on_page": "last",
  "file_name": "Subscription Agreement - ABC Fund",
  "file_data": "<BASE64_ENCODED_PDF>",
  "sequential": true,
  "estamp_request": {
    "tags": { ... },
    "sign_on_page": "LAST"
  }
}
```

Authentication: `Authorization: Basic <base64(client_id:secret)>`

### DocuSign Flow

1. JWT token obtained via RSA private key.
2. Envelope created with PDF attachment and recipient list.
3. DocuSign sends email to each recipient with a signing link.
4. Each recipient signs via DocuSign's hosted UI.

---

## Status Updates

### Webhook (Automatic)

Providers POST to `POST /documents/signature_progress`:

```
Provider Webhook
        │
        ▼
DocumentsController#signature_progress
        │
        ▼
EsignHelper.update_signature_progress(params)
 - Detects provider by payload shape:
     DIGIO:    params['payload']['document']['id']  present
     DOCUSIGN: params['data']['envelopeId'] AND params['data']['accountId'] present
        │
        ├─ DigioEsignHelper#update_signature_progress(params)
        │    - Finds document by provider_doc_id
        │    - Updates each e_signature.status from signing_parties[]
        │    - Logs webhook to EsignLog.webhook_data
        │    - Calls check_and_update_document_status
        │
        └─ DocusignEsignHelper#update_signature_progress(params)
             - Routes on event type:
                 "envelope-completed"   → all signed
                 "envelope-voided"      → cancelled
                 "recipient-completed"  → individual signed
                 "recipient-sent"       → individual notified
             - Updates e_signature.status
             - Calls check_and_update_document_status
```

**Digio webhook payload shape:**
```json
{
  "payload": {
    "document": {
      "id": "<provider_doc_id>",
      "status": "completed",
      "signing_parties": [
        { "identifier": "investor@example.com", "status": "signed"   },
        { "identifier": "gp@fund.com",          "status": "requested" }
      ],
      "error_code": null
    }
  }
}
```

**DocuSign webhook events:**
| Event                 | Meaning                          |
|-----------------------|----------------------------------|
| `envelope-completed`  | All signers have signed          |
| `envelope-voided`     | Envelope cancelled               |
| `recipient-completed` | Individual signer completed      |
| `recipient-sent`      | Individual signer notified       |

### Manual Polling (User-triggered)

```
User clicks "Fetch eSign Updates"
        │
        ▼
DocumentsController#fetch_esign_updates
        │
        ▼
DocumentEsignUpdateJob.perform_later(doc.id, user_id)
        │
        ▼
EsignUpdateJob#perform
 - Calls EsignHelper.new(doc).update_esign_status
 - GET <provider>/status/<provider_doc_id>
 - Updates e_signature.status for each signer
 - Saves result in EsignLog.manual_update_data
 - Calls check_and_update_document_status
```

### Automatic Daily Polling

`DocumentEsignUpdateJob` runs every day at **2:01 am**:
- Fetches all `sent_for_esign` documents created in the last **10 days**.
- Skips documents with status in `SKIP_ESIGN_UPDATE_STATUSES`.
- Enqueues `EsignUpdateJob` for each eligible document.

---

## Completion Flow

```
check_and_update_document_status(document)
        │
        ├─ Are all e_signatures signed?
        │    NO  → nothing happens
        │    YES ↓
        │
        ▼
EsignHelper#check_and_update_document_status
        │
        ▼
helper.signature_completed(document)
   (DigioEsignHelper or DocusignEsignHelper)
        │
        ├─ Downloads signed PDF from provider
        ├─ Saves to tmp file
        │
        ▼
Document#signature_completed(signed_doc_from_provider)
        │
        ├─ Marks original document:  esign_status = "completed"
        │
        ├─ Creates NEW Document:
        │    name        = original.name
        │    file        = downloaded signed PDF
        │    from_template = original document
        │    owner       = original.owner  (CapitalCommitment / InvestorKyc / Offer)
        │    owner_tag   = "Signed"
        │    approved    = true
        │    locked      = true
        │    send_email  = false
        │
        └─ Both documents persist (original + signed copy)
```

---

## Template System

Fund-level documents can be **templates**. Template ESignatures are placeholder slots with a `label` but no email. When a document is generated for a specific commitment, slots are resolved to real email addresses.

```
Template Document
  └── ESignature [label="Investor Signatory", email=nil, notes=nil]
  └── ESignature [label="Fund Signatory",     email=nil, notes="ops@fund.com"]

                  ▼ document generation ▼

Generated Document
  └── ESignature [label="Investor Signatory", email="lp@abc.com"]   ← from commitment.esign_emails
  └── ESignature [label="Fund Signatory",     email="ops@fund.com"] ← from notes fallback
```

Resolution logic in `WithESignatures#e_signatures_for(model)`:

| Template label            | Resolved from                                       |
|---------------------------|-----------------------------------------------------|
| `investor_signatories`    | `model.investor_signatories` (array of emails)      |
| `fund_signatories`        | `model.fund_signatories`                            |
| `buyer_signatories`       | `model.buyer_signatories`                           |
| `seller_signatories`      | `model.seller_signatories`                          |
| Any other label           | `e_signature.notes` (static email in template)      |

---

## Capital Commitment Integration

```
CapitalCommitment
  ├── esign_emails      (comma-separated signer emails)
  ├── esign_completed   (boolean — mirrors signed document existence)
  └── documents         (polymorphic: owner_type="CapitalCommitment")
          │
          └── Document (subscription agreement, side letter, etc.)
                └── ESignature × N
```

- `esign_emails` populates investor-side ESignature records when documents are generated.
- If blank, falls back to `investor_kyc.esign_emails`.
- Policy guard: `generate_documentation?` is blocked when `esign_completed` is true — prevents overwriting a signed document.

Similarly for `InvestorKyc` and `Offer` (both have `esign_emails` and `esign_completed`).

---

## Routes & API

```
# Document-level actions
PATCH  /documents/:id/send_for_esign          # Normal send
PATCH  /documents/:id/force_send_for_esign    # Force resend (clears sent_for_esign flag)
PATCH  /documents/:id/resend_for_esign        # Resend if failed/cancelled/expired
PATCH  /documents/:id/cancel_esign            # Cancel signing with provider

# Status updates
POST   /documents/:id/fetch_esign_updates     # Manual poll for one document
PATCH  /documents/send_all_for_esign          # Bulk send by folder_id

# Provider webhook
POST   /documents/signature_progress          # Digio & DocuSign callbacks (no auth token)

# Admin
GET    /admin/e_signatures                    # Administrate dashboard
GET    /investor_kycs/:id/esign_emails        # Fetch esign emails for KYC
```

---

## Background Jobs

| Job                       | Queue   | Trigger                                              | Purpose                                              |
|---------------------------|---------|------------------------------------------------------|------------------------------------------------------|
| `EsignJob`                | default | Controller / folder send                             | Sends one document (or all in a folder) to provider  |
| `EsignUpdateJob`          | default | Manual fetch / DocumentEsignUpdateJob                | Fetches status for one document from provider        |
| `DocumentEsignUpdateJob`  | low     | Sidekiq cron — daily at 2:01am; or manual            | Bulk status poll for docs <10 days old               |
| `EsignLogCleanupJob`      | low     | Sidekiq cron                                         | Purges EsignLog rows (91 days all; 10 days completed)|

### Job Dependency Diagram

```
Sidekiq Cron (2:01am)
        │
        ▼
DocumentEsignUpdateJob
  - Queries: sent_for_esign docs created < 10 days ago
  - For each eligible doc:
        │
        ▼
  EsignUpdateJob (per doc)
        │
        ▼
  EsignHelper#update_esign_status
        │
        ▼
  Provider status API
        │
        ▼
  check_and_update_document_status
        │
        └── (if all signed) → signature_completed → new "Signed" Document
```

---

## Authorization & Permissions

**Policy:** `app/packs/core/documents/policies/e_signature_policy.rb`

- User must have `enable_documents` permission on the entity.
- ESignature records can only be **created/edited/destroyed** before the document is sent (`!record.document.sent_for_esign`).
- Once a document is sent, signatories are locked — only the provider can update statuses.

---

## Status Reference

### ESignature status (per signer)

| Status      | Meaning                                     | Badge   |
|-------------|---------------------------------------------|---------|
| `nil` / `""`| Not yet sent to provider                    | (none)  |
| `requested` | Sent to provider, awaiting signer action    | warning |
| `sent`      | Provider notified signer via email          | warning |
| `signed`    | Signer has completed signing                | success |
| `failed`    | Signing attempt failed                      | danger  |
| `cancelled` | Signing request cancelled                   | danger  |
| `expired`   | Signing window expired (90 days for Digio)  | danger  |
| `voided`    | Envelope voided (DocuSign)                  | danger  |

### Document `esign_status` (aggregate)

| Status      | Meaning                                     |
|-------------|---------------------------------------------|
| `""`        | Not yet sent                                |
| `requested` | Sent to provider, in progress               |
| `completed` | All signers signed; signed PDF created      |
| `failed`    | Provider rejected or signing failed         |
| `cancelled` | Cancelled by user or provider               |
| `expired`   | Signing window expired                      |
| `voided`    | Voided (DocuSign)                           |

`SKIP_ESIGN_UPDATE_STATUSES = ["cancelled", "completed", "expired", "voided"]` — documents in these states are never polled for updates.

---

## Key File Locations

| Component                   | Path                                                                              |
|-----------------------------|-----------------------------------------------------------------------------------|
| ESignature model            | `app/packs/core/documents/models/e_signature.rb`                                  |
| Document esign concern      | `app/packs/core/documents/models/concerns/with_e_signatures.rb`                   |
| EsignLog model              | `app/packs/core/documents/models/esign_log.rb`                                    |
| EsignHelper factory         | `app/packs/core/investor_kycs/models/helper/esign_helper.rb`                      |
| Digio helper                | `app/packs/core/investor_kycs/models/concerns/digio_esign_helper.rb`              |
| Digio operation             | `app/packs/core/investor_kycs/services/digio/digio_esigning.rb`                   |
| DocuSign helper             | `app/packs/core/investor_kycs/models/concerns/docusign_esign_helper.rb`           |
| DocuSign utils              | `app/packs/core/investor_kycs/models/concerns/docusign_esign_utils.rb`            |
| DocuSign operation          | `app/packs/core/investor_kycs/services/docusign/docusign_esigning.rb`             |
| EsignJob                    | `app/packs/core/documents/jobs/esign_job.rb`                                      |
| EsignUpdateJob              | `app/packs/core/documents/jobs/esign_update_job.rb`                               |
| DocumentEsignUpdateJob      | `app/packs/core/documents/jobs/document_esign_update_job.rb`                      |
| ESignaturePolicy            | `app/packs/core/documents/policies/e_signature_policy.rb`                         |
| Admin controller            | `app/controllers/admin/e_signatures_controller.rb`                                |
| Routes                      | `config/routes/core.rb` (lines 209–216)                                           |
| Schema (documents)          | `db/schema.rb` lines 1283–1308                                                    |
| Schema (e_signatures)       | `db/schema.rb` lines 1328–1344                                                    |
| Schema (esign_logs)         | `db/schema.rb` lines 1471–1482                                                    |
