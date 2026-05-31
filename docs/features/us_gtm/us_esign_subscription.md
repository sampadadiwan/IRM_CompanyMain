# US E-Sign Integration & Subscription Packet Engine

**Approach:** Enhance existing `ESignature` / `Document` models + Integrate US providers (DocuSign, Dropbox Sign)
**Phase:** P0 — required for subscription document execution

---

## What This Is

CapHive has a working e-sign module built around Indian providers (Aadhaar OTP, DSC). For the US market, the module needs to be extended with DocuSign and Dropbox Sign integration — the two providers US private funds actually use — and complemented by a Subscription Packet Engine that manages the full workflow: determining which documents each investor needs, pre-filling them from investor data, routing them for signature in the correct order, tracking countersignature by the GP, and archiving the final executed package.

---

## Who Uses It

| Persona | When | What They Need |
|---------|------|----------------|
| **Operations / IR Team** | Sending subscription packets to new investors | Select the correct documents for each investor type and fund; send for signature in one action |
| **Fund Counsel** | Approving subscription document templates | Upload and version-control counsel-approved templates; review legal exceptions |
| **LP (self) via portal** | Receiving and signing subscription documents | Sign from any device without creating an account; see all required documents in one place |
| **GP / Authorized Signatory** | Countersigning executed subscription agreements | Receive routing for countersignature after LP has signed |
| **COO / Closing Room** | Tracking subscription completion | See which investors have signed, partially signed, or not yet started |

---

## Use Cases

### UC-1: Standard Subscription Packet — US LLC Investor
Operations creates a new investor (US LLC). The system determines required documents: subscription agreement, investor questionnaire, and W-9. Documents are pre-filled with the investor's name, entity type, and EIN. The packet is sent to the LP's authorized signatory via DocuSign. Signing order: (1) LP signs all documents; (2) GP authorized signatory countersigns the subscription agreement.

### UC-2: Foreign Investor Packet — Additional Forms Required
A Cayman fund-of-funds investor requires: subscription agreement, investor questionnaire, W-8BEN-E, beneficial owner certification, and a FATCA-specific exhibit. The packet engine determines the additional forms based on the investor's `us_investor_type` custom field value (stored in `investor.json_fields`, set via FormCustomField on the `Investor` record), adds them to the standard packet, and routes for signature.

### UC-3: Counsel Template Update Mid-Fundraise
Counsel uploads a revised subscription agreement template (version 2.1) after a first close. The system marks version 2.0 as archived. New investors going through onboarding after the template update receive version 2.1. Investors who already signed version 2.0 are unaffected.

### UC-4: Multi-Signatory Institutional LP
A pension fund requires two authorized signatories to sign the subscription agreement. The packet engine sends to both signatories in sequence: first signatory signs, then the document routes to the second signatory. GP countersignature only triggers after both LP signatories have completed.

### UC-5: Wet-Sign Fallback
An investor (typically an older institutional LP) declines to use e-sign. Operations downloads the pre-filled document package as a PDF, sends it by email/courier, and uploads the wet-signed executed copy manually. The system records the document as "wet-signed" and marks e-sign as not applicable for this investor.

### UC-6: Exception — Missing Initial on Page 12
An investor submits their subscription agreement via DocuSign but missed initialling one page. The fund admin reviews the completion certificate, identifies the missing initial, and sends the document back to the LP for correction. The system tracks this as a resubmission cycle.

---

## Current CapHive State

| Capability | Status | Notes |
|------------|--------|-------|
| E-sign model (`ESignature`, `EsignLog`) | ✅ Exists | Full e-sign lifecycle with signatories, status tracking, logs |
| Aadhaar OTP / Digio e-sign (India) | ✅ Exists | India-specific; not applicable for US |
| DSC (Digital Signature Certificate) e-sign | ✅ Exists | India-specific; not applicable for US |
| Provider adapter pattern (`EsignHelper`) | ✅ Exists | `EsignHelper` reads `entity_setting.esign_provider` and dynamically dispatches to the correct helper (e.g. `DocusignEsignHelper`); webhook routing auto-detects provider from payload |
| DocuSign integration | ✅ Exists | Full implementation: JWT auth, envelope creation via DocuSign eSignature API, multi-signer routing with configurable order (`force_esign_order`), webhook handling for all envelope and recipient events, completion certificate download, cancel/void — see `core/investor_kycs/services/docusign/` |
| Dropbox Sign (HelloSign) integration | ❌ Missing | No Dropbox Sign API integration |
| Document template versioning | ⚠️ Partial | Templates exist as documents with `template = true` flag; no formal version history or counsel approval state |
| Subscription packet engine (multi-doc routing) | ❌ Missing | E-sign sends one document at a time; no packet assembly or document determination logic |
| Investor-type-based document determination | ❌ Missing | No logic to select required documents based on investor type |
| Pre-fill document fields from investor data | ❌ Missing | No field mapping from investor/KYC records into document templates |
| Countersignature routing after LP signs | ⚠️ Partial | Multiple signatories supported; `force_esign_order` enforces signing sequence — LP-then-GP ordering needs to be configured in packet generation |
| Wet-sign fallback with manual upload | ✅ Exists | Manual document upload always available |
| Completion certificate / audit trail storage | ⚠️ Partial | DocuSign `envelope-completed` webhook downloads the completed document via `signature_completed`; no separate completion certificate PDF archived alongside it |
| Counsel-approved template workflow | ❌ Missing | No approval state on templates; no counsel review role for templates |

---

## Build Approach: Enhance `core/documents` pack + new subscription packet module

### E-Sign Provider Abstraction — Already Built

The provider adapter pattern is already implemented as `EsignHelper` (`core/investor_kycs/models/helper/esign_helper.rb`). It reads `entity_setting.esign_provider`, instantiates the matching helper class (e.g. `DocusignEsignHelper`), and dispatches `sign`, `cancel_esign`, `update_esign_status`, and `update_signature_progress` through it. The webhook router auto-detects DocuSign vs. Digio from the payload shape.

**DocuSign — Already Built** (`core/investor_kycs/services/docusign/`):
- JWT authentication via `JwtAuth::JwtCreator`
- Envelope creation with per-signer `SignHere` tabs, configurable page placement, and routing order
- Webhook handling: `envelope-completed`, `recipient-completed`, `recipient-sent`, `envelope-voided`
- Completion: completed document downloaded from DocuSign and stored via `signature_completed`
- Cancel/void via DocuSign Envelope API

**What still needs to be added for US subscription packets (small):**
- `esign_provider` should include `dropbox_sign` as an option in `EntitySetting`
- Dropbox Sign adapter (`DropboxSignEsignHelper` + `DropboxSignEsigning`) — same interface as DocuSign helper
- `docusign_account_id` / `docusign_integration_key` are already stored in Rails credentials; move to `EntitySetting` per-entity if multi-tenant DocuSign accounts are needed

**Dropbox Sign Adapter (to build):**
- Same lifecycle as DocuSign: envelope creation → webhook → completion download
- Fallback option for firms that prefer simpler pricing

### Subscription Packet Engine

New model: **`SubscriptionPacket`** (belongs to CapitalCommitment)
- `capital_commitment_id` FK
- `status` — enum: `draft`, `sent`, `partially_signed`, `fully_signed`, `countersigned`, `archived`
- `template_version` — tracks which template version was used
- `sent_at`, `fully_signed_at`, `countersigned_at`
- `notes` text

New model: **`SubscriptionPacketDocument`** (belongs to SubscriptionPacket)
- `subscription_packet_id`, `document_id` FKs
- `document_role` — enum: `subscription_agreement`, `investor_questionnaire`, `tax_form`, `beneficial_owner_cert`, `side_letter`, `other`
- `required` — boolean
- `signature_status` — enum: `not_sent`, `pending`, `signed`
- `countersignature_required` — boolean
- `countersignature_status` — enum: `not_required`, `pending`, `signed`

**Document Determination Logic:**

```
Inputs: investor.json_fields["us_investor_type"], investor.json_fields["is_benefit_plan_investor"], fund.fund_exemption_type, side_letter_required

Standard documents (all investors):
  - Subscription Agreement (counsel-approved template, current version)
  - Investor Questionnaire (eligibility + KYC reps)

Conditional additions:
  - us_investor_type = "Foreign Entity" → add W-8BEN-E exhibit
  - us_investor_type = "Foreign Individual" → add W-8BEN exhibit
  - is_benefit_plan_investor = "true" (json_fields value) → add ERISA exhibit
  - fund_exemption_type = three_c_7 → add QP certification exhibit
  - side_letter_agreed = true → add side letter
```

### Template Versioning & Counsel Approval

**`DocumentTemplate`** enhancements (or new model if template management is refactored):
- `version` — string (e.g. "2.1")
- `status` — enum: `draft`, `counsel_review`, `approved`, `archived`
- `approved_by_user_id`, `approved_at`
- `fund_id` FK (templates are fund-specific)
- `template_type` — enum matching `document_role` above

When a new template version is uploaded, previous version auto-archives. Only `status = approved` templates are used in packet generation.

---

## Functional Requirements

1. DocuSign is the primary US e-sign provider and is already fully integrated; Dropbox Sign is offered as an alternative when built — the provider is selected per entity via `entity_setting.esign_provider`
2. Packet assembly determines required documents based on investor type and fund configuration; counsel can override for individual investors
3. Template version used is recorded on every SubscriptionPacket; changing the template after packets are sent has no effect on in-flight packets
4. Signing order enforces: LP signatories complete before GP countersignature routing is triggered
5. Multi-signatory LPs: all LP signatories must complete before the packet moves to countersignature
6. Completion certificate (DocuSign/Dropbox Sign audit trail PDF) is stored alongside the executed document in the investor's folder
7. Wet-sign upload marks the document as manually executed; e-sign is not required; closing room accepts wet-signed documents
8. Subscription packet status is a required dimension in the closing room readiness checklist
9. Counsel-approved template status gates packet generation: no packet can be sent using a draft or unapproved template

---

## Integration Points

- `closing_room.md` — subscription packet status is a required closing checklist dimension
- `us_investor_taxonomy.md` — investor type drives document determination logic
- `investor_qualification_engine.md` — investor questionnaire in the packet captures eligibility representations
- `us_tax_forms.md` — W-8/W-9 documents may be included in the packet or linked to it
- `compliance_evidence_binder.md` — executed subscription package (all signed documents + completion certificate) included in evidence binder
- Existing: DocuSign eSignature API — already integrated (`core/investor_kycs/services/docusign/`); `EsignHelper` adapter pattern already in place
- To integrate: Dropbox Sign API (same adapter interface)
