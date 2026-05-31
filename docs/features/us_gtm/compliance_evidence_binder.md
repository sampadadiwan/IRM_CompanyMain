# Compliance Evidence Binder

**Approach:** Build — aggregates data from all other US modules; no existing equivalent
**Phase:** P1/P2 — most valuable after P0 modules generate evidence data

---

## What This Is

Compliance in private funds is not just doing the right thing — it is proving later that you did it. When an SEC examiner requests books and records, when an institutional LP conducts due diligence, or when a fund administrator needs evidence for their own compliance obligations, the question is the same: show me the evidence.

Today, assembling this evidence takes weeks of legal team time: hunting across KYC systems, document folders, email threads, and spreadsheets. The Compliance Evidence Binder automates this: a per-investor, per-fund evidence package that aggregates every compliance-relevant record — KYC results, tax forms, qualification determinations, subscription documents, bank verification, side letter obligations — into a structured, exportable summary.

---

## Who Uses It

| Persona | When | What They Need |
|---------|------|----------------|
| **General Counsel / Compliance** | SEC exam, LP due diligence, audit | Pull a complete evidence package for any investor in minutes, not weeks |
| **COO** | Quarterly compliance review | See which investors have stale KYC, expired tax forms, or open exceptions across the fund |
| **Fund Administrator** | Receiving compliance data | Get a structured summary of each investor's compliance status |
| **IR Director** | Responding to institutional LP questions | Show evidence that the GP has a rigorous compliance program without exposing raw data |
| **Operations** | Ongoing hygiene | Identify and remediate gaps before they become problems — missing beneficial owners, expired W-8s, unresolved AML flags |

---

## Use Cases

### UC-1: SEC Annual Exam — Books and Records Request
The SEC requests investor records for Fund III. The compliance team generates a Compliance Evidence Binder for all 96 investors. Each binder contains: subscription documents (signed), KYC verification results (with provider, date, and result), AML screening results, tax form (type, date, FATCA classification), bank instruction verification record, qualification determination (AI/QP/QC status), and any exceptions with approvals. Total assembly time: under 1 hour.

### UC-2: Institutional LP Due Diligence
A university endowment LP is conducting operational due diligence on the GP before committing to the next fund. They ask for evidence of the GP's investor onboarding and compliance process. The compliance team exports a redacted binder showing the process (not individual investor data) with one anonymized example showing each step. The LP sees that every dimension is covered, documented, and auditable.

### UC-3: Compliance Gap Dashboard
The compliance team runs a monthly "compliance health check": how many investors have KYC expiring in the next 90 days? How many have expired W-8 forms? How many have open AML exceptions that haven't been resolved? The dashboard surfaces all of these across the fund portfolio in one view, with direct links to remediate each gap.

### UC-4: New LP — Binder Generated at Admission
When an investor is admitted in a closing, CapHive automatically generates their initial Compliance Evidence Binder as part of the closing binder package. This creates a baseline record of their compliance status at admission, against which future changes can be compared.

### UC-5: Exception Audit Trail
During an audit, the auditor asks: "Show me every investor where a KYC or compliance exception was approved, and by whom." The compliance team runs an exception audit report: all investors with `status = exception_approved`, the exception type, the approver, the timestamp, and the notes. This is available in under 60 seconds.

---

## Current CapHive State

| Capability | Status | Notes |
|------------|--------|-------|
| KYC records and verification status | ✅ Exists | `InvestorKyc`, `IndividualKyc`, `NonIndividualKyc`; verification sign-off |
| AML report records | ✅ Exists | `AmlReport` model; basic manual record today; enhanced by `us_kyc_kyb.md` |
| Document storage and access | ✅ Exists | Per-investor folder hierarchy |
| Audit logs (Audited gem) | ✅ Exists | `Audit` model tracks changes to most records |
| Compliance evidence binder (per-investor aggregate) | ❌ Missing | No aggregation layer; evidence must be assembled manually |
| Compliance gap dashboard (across all investors) | ❌ Missing | No cross-investor compliance health view |
| Exception audit trail report | ❌ Missing | Exceptions exist as tasks and notes; no structured exception model |
| Auto-generation at admission | ❌ Missing | No trigger to generate evidence package on investor admission |
| Exportable PDF / ZIP package per investor | ❌ Missing | Individual documents can be downloaded; no packaged export |

---

## Build Approach: New pack `funds/compliance_evidence`

### Architecture

The Compliance Evidence Binder is a read-aggregation layer. It does not store duplicate data — it reads from the source modules and assembles a structured view. A `ComplianceSnapshot` model caches the current state for performance, but the underlying data always comes from the authoritative source.

### New Models

**`ComplianceSnapshot`** (belongs to Investor + Fund)
- `investor_id`, `fund_id` FKs
- `kyc_status` — enum: `not_started`, `pending`, `approved`, `exception`, `expired`
- `kyc_last_verified_at` date
- `kyc_refresh_due_at` date
- `aml_status` — enum: `clear`, `potential_match`, `confirmed_match`, `exception_approved`
- `aml_last_screened_at` date
- `aml_refresh_due_at` date
- `tax_form_type` string (e.g. "W-9", "W-8BEN-E")
- `tax_form_status` — enum: `pending`, `validated`, `expired`
- `tax_form_expires_at` date
- `bank_verification_status` — enum: `not_provided`, `pending`, `verified`, `failed`
- `qualification_status` — enum: `qualified`, `exception`, `not_eligible`, `not_evaluated`
- `subscription_docs_status` — enum: `pending`, `signed`, `countersigned`
- `open_exceptions_count` integer
- `overall_status` — enum: `compliant`, `attention_required`, `non_compliant`
- `last_computed_at` timestamp

**`ComplianceException`** (cross-module exception record — see also `us_kyc_kyb.md`, `closing_room.md`)
- `investor_id`, `fund_id` FKs
- `source` — enum: `kyc`, `aml`, `tax_form`, `bank`, `qualification`, `side_letter`, `other`
- `description` text
- `severity` — enum: `advisory`, `requires_approval`, `hard_block`
- `status` — enum: `open`, `approved`, `rejected`, `resolved`
- `raised_at`, `resolved_at`
- `approved_by_user_id`, `approved_at`
- `approval_notes` text

### Compliance Health Dashboard (Fund-Level)

```
Fund: Acorn Growth Partners II — Compliance Health
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Fully compliant:        81 investors
Attention required:      9 investors   ← KYC expiring, tax form stale
Non-compliant:           2 investors   ← open AML exception unresolved
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ATTENTION REQUIRED
  KYC expiring in 90 days:           6 investors
  Tax form (W-8) expiring:           2 investors
  Open exceptions pending review:    1 investor

NON-COMPLIANT
  Unresolved AML potential match:    2 investors ← action required
```

Clicking any row opens the investor's Compliance Evidence Binder.

### Per-Investor Binder View

```
Compliance Evidence Binder
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Investor:  Meridian Capital Partners LLC
Fund:      Acorn Growth Partners II
Status:    Compliant — 1 historical exception (resolved)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ONBOARDING
  ✓ Subscription agreement — signed Apr 3, 2025
  ✓ Investor questionnaire — completed Apr 3, 2025
  ✓ GP countersignature — Apr 8, 2025

IDENTITY & ENTITY VERIFICATION
  ✓ KYB — Middesk — Apr 5, 2025 — passed
  ✓ Beneficial owner: Jane Meridian — identity verified — Persona — Apr 5
  ✓ Entity sanctions — ComplyAdvantage — Apr 5, 2025 — clear
  ✓ Jane Meridian — individual sanctions — clear
  Next refresh: Sanctions — Apr 2026 | KYC — Apr 2028

TAX DOCUMENTATION
  ✓ W-9 — received Apr 3, 2025 — TIN validated
  FATCA: US Person — no withholding required

BANK VERIFICATION
  ✓ JPMorgan Chase ****4521 — Plaid — Apr 4, 2025 — verified

INVESTOR QUALIFICATION
  ✓ Qualified Purchaser — $32M in investments — confirmed
  ✓ Accredited Investor — confirmed
  ERISA: Not a benefit plan investor — confirmed

SIDE LETTER
  ✓ Executed Apr 8, 2025
  ✓ 2 obligations extracted and active in LP Obligation Matrix

EXCEPTIONS
  RESOLVED — Formation document was 4 years old (threshold: 3 years)
    Approved by: Marcus Reeves (Legal) — Apr 7, 2025
    Reason: No material change in entity structure; fresh filing not warranted
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Export Package (ZIP)

When "Export Binder" is triggered, CapHive generates:
1. `binder_summary.pdf` — the structured compliance summary above as a PDF
2. `subscription_agreement_executed.pdf` — from SubscriptionPacket
3. `kyb_middesk_result.json` / `kyb_summary.pdf` — from KycVerificationCheck
4. `aml_comply_advantage_result.pdf` — from AmlReport (formatted summary)
5. `w9_or_w8.pdf` — from the File-type custom field document on the investor's KYC record (see `us_tax_forms.md`)
6. `bank_verification_record.pdf` — from BankInstruction verification record
7. `qualification_summary.pdf` — from InvestorQualification records
8. `side_letter_executed.pdf` — from SideLetter document
9. `exception_log.pdf` — all ComplianceException records with approvals

---

## Functional Requirements

1. `ComplianceSnapshot` is recomputed automatically whenever any underlying record changes (KYC, AML, tax form, bank instruction, qualification)
2. `overall_status = non_compliant` requires an open `ComplianceException` with `severity = hard_block` and no approved resolution
3. Export package generation is asynchronous; user receives a download link when ready
4. Binder is auto-generated at investor admission (triggered by `CapitalCommitment.onboarding_completed` flipping to `true` — see `closing_room.md`)
5. Exception records are immutable after `status = approved` or `resolved`; corrections create new records
6. Compliance health dashboard refreshes daily from the snapshot; real-time recalculation available on demand
7. All binder exports are logged with user, timestamp, and the snapshot values at time of export

---

## Integration Points

- `us_kyc_kyb.md` — KYC verification and AML results
- `us_tax_forms.md` — tax form status and FATCA classification
- `bank_instruction_controls.md` — bank verification record
- `investor_qualification_engine.md` — qualification status and evidence
- `us_esign_subscription.md` — executed subscription package
- `side_letter_obligations.md` — side letter execution and obligation status
- `closing_room.md` — admission record triggers initial binder generation
- `fund_admin_exchange.md` — compliance status summary included in investor master export
