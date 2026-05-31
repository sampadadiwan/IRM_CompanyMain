# US KYC / KYB — Identity, Entity Verification & Sanctions

**Approach:** Enhance existing KYC pack (`core/investor_kycs`) + Integrate new US providers
**Phase:** P0 — required for investor diligence before any US closing

---

## What This Is

CapHive has a functional KYC module built for the Indian market (PAN verification, CKYC, KRA, SEBI form types). For the US, the module needs to be extended with: US-specific identity verification providers (Persona, Socure), entity verification providers (Middesk, Alloy), sanctions/PEP/adverse media screening (ComplyAdvantage, LSEG), and the structured evidence model that US institutional LPs and fund administrators expect to see.

The goal is not to replace the existing KYC architecture — which is solid — but to add US provider integrations alongside the existing India integrations, and to build the compliance evidence record that surfaces "what was checked, when, by whom, and what was found."

---

## Who Uses It

| Persona | When | What They Need |
|---------|------|----------------|
| **Operations / Compliance Team** | LP onboarding | Run identity and entity checks, review results, approve or escalate exceptions |
| **LP (self) via portal** | Onboarding identity step | Upload ID documents; complete identity verification flow (Persona) |
| **General Counsel / Compliance** | Investor admission and periodic refresh | See structured evidence of what was checked; approve exceptions; know when refresh is due |
| **Fund Administrator** | Receiving investor data | Receive structured KYC status and AML results for their records |
| **Auditor / SEC Examiner** | Periodic review | Pull a compliance evidence package showing all KYC checks performed and results |

---

## Use Cases

### UC-1: Individual Identity Verification (US Person)
A US high-net-worth individual submits their SSN and ID documents via the portal. CapHive initiates a Persona identity verification: document capture (passport or driver's license), facial biometric match, and database check. Result is returned as: passed / failed / needs_review. Fund team sees the result in the KYC record; exceptions route to a review queue.

### UC-2: Entity Verification (US LLC)
A family office LLC investing in the fund needs entity KYC. CapHive initiates a Middesk business verification: confirms the entity is registered in its stated state of formation, retrieves registered agent information, confirms the entity is active, and returns beneficial owner data if available. Operations team reviews and approves.

### UC-3: Sanctions, PEP, and Adverse Media Screening
For every investor — individual or entity — CapHive runs a ComplyAdvantage screening: OFAC/HMT/EU sanctions lists, global PEP lists, and adverse media. Results are returned with match details. True matches block admission; potential matches route to compliance review with the specific list entry and reason.

### UC-4: Beneficial Owner Cascade (Passive NFFE)
A Cayman LP with a Passive NFFE FATCA classification must identify beneficial owners above 25% threshold. CapHive collects beneficial owner declarations from the entity's UBO form, then runs individual identity verification and sanctions screening on each named owner.

### UC-5: Periodic KYC Refresh
A fund's compliance policy requires sanctions re-screening annually and full KYC refresh every 3 years for standard-risk investors. CapHive tracks the last screening date on each `InvestorKyc` record, sends an alert 60 days before the refresh due date, and auto-creates a task for the operations team.

### UC-6: Exception — Adverse Media Hit
A family office LP returns an adverse media result: a news article from 3 years ago about the principal in a regulatory enforcement action that was later resolved. The operations team reviews the article, documents their determination ("resolved; no ongoing sanctions exposure"), and approves the exception with a note. The exception record is stored with the KYC record.

---

## Current CapHive State

| Capability | Status | Notes |
|------------|--------|-------|
| Individual KYC (`IndividualKyc`) and Non-Individual KYC (`NonIndividualKyc`) models | ✅ Exists | Solid foundation; field sets are configurable via form types |
| Configurable KYC form wizard with jurisdiction tags | ✅ Exists | SEBI, GIFT, Default tags; US tag needs to be added |
| AML report model (`AmlReport`) | ✅ Exists | `AmlReport` with `match_status` enum (`potential_match`, `no_match`), `request_data`/`response_data` jsonb, `request_id`; `GenerateAmlReportJob` auto-triggered by `KycOnboardingAgent`; current provider is India-specific — US providers (ComplyAdvantage) need to be added |
| KYC expiry tracking (`kyc_expiry`) | ✅ Exists | Field exists; background alerts need to be verified |
| PAN verification (India — CKYC/KRA) | ✅ Exists | India-specific; not applicable for US |
| US identity verification (Persona, Socure, Onfido) | ❌ Missing | No US identity provider integration |
| Entity verification (Middesk, Alloy) | ❌ Missing | No US entity verification provider |
| Sanctions / PEP / adverse media screening (ComplyAdvantage) | ❌ Missing | No screening provider integration; AML report is a manual record only |
| Beneficial owner cascade (UBO) with individual screening | ⚠️ Partial | Beneficial ownership declaration available as custom form step; no structured UBO model with individual screening |
| Screening result record with match details | ❌ Missing | AmlReport exists but holds free-text notes; no structured match/no-match result |
| Exception record with reviewer approval | ⚠️ Partial | Tasks and notes can capture this; no formal exception model linked to a KYC check |
| KYC evidence export for compliance | ⚠️ Partial | Documents can be downloaded individually; no structured compliance evidence package |

---

## Build Approach: Enhance `core/investor_kycs` pack + new provider integrations

### Model Changes

**`AmlReport` enhancements** (existing columns: `match_status` enum, `request_data`/`response_data` jsonb, `request_id`; add):
- `provider` — enum: `comply_advantage`, `lseg_world_check`, `dow_jones`, `lexisnexis`, `manual` (currently implicit India provider)
- `check_type` — enum: `sanctions`, `pep`, `adverse_media`, `combined`
- `result` — enum: `clear`, `potential_match`, `confirmed_match`, `error` (replaces/extends existing `match_status`)
- `match_count` — integer
- `screened_at` timestamp
- `reviewed_by_user_id`, `reviewed_at`
- `review_disposition` — enum: `false_positive`, `true_match_blocked`, `exception_approved`
- `review_notes` text
- Note: `raw_response` is already covered by the existing `response_data` jsonb column; no new column needed

**New model: `KycVerificationCheck`** (belongs to InvestorKyc)
- `check_type` — enum: `identity`, `entity`, `sanctions`, `pep`, `adverse_media`, `beneficial_owner`
- `provider` — string
- `provider_check_id` — string (external reference)
- `status` — enum: `pending`, `pass`, `fail`, `needs_review`, `error`
- `result_summary` — text
- `raw_response` — jsonb (encrypted)
- `performed_at` timestamp
- `reviewed_by_user_id`, `reviewed_at`
- `exception_approved` — boolean
- `exception_notes` text

**New model: `BeneficialOwner`** (belongs to NonIndividualKyc)
- `kyc_id` FK
- `full_name`, `nationality`, `date_of_birth`, `ownership_percentage`
- `id_type`, `id_number_encrypted`
- `verification_status` — enum: `pending`, `verified`, `flagged`
- `aml_report_id` FK (individual screening result)

### Provider Integrations

**Persona (individual identity):**
- Embed Persona Hosted Flow in the investor portal for US individuals
- Receive webhook callback with verification result
- Store `KycVerificationCheck` with `check_type = identity`, `provider = persona`
- Results: `pass` (ID verified, biometric match), `fail`, `needs_review`

**Middesk (entity verification):**
- API call on Non-Individual KYC submission with entity name, EIN, state of formation
- Returns: entity status, registered agent, formation documents, beneficial owner data
- Store `KycVerificationCheck` with `check_type = entity`, `provider = middesk`

**ComplyAdvantage (sanctions, PEP, adverse media):**
- API call for every investor (individual and entity) and every beneficial owner
- Search by name + date of birth (individual) or name + jurisdiction (entity)
- Returns: match list with sources, match score, match type
- Store `AmlReport` with full match detail; route potential matches to review queue

### Refresh Logic
- Background job checks `investor_kycs.kyc_expiry` and `aml_reports.screened_at` daily
- Sends alert 60 days before AML refresh due date (annual for standard risk, 6 months for elevated)
- Auto-creates task for operations team with link to investor's KYC record
- Re-screening can be triggered manually from the KYC record page at any time

---

## Functional Requirements

1. US identity verification (Persona) is triggered from the investor portal; LP completes the flow without leaving the portal
2. Entity verification (Middesk) is triggered by the operations team on the Non-Individual KYC record page
3. Sanctions/PEP/adverse media screening runs automatically on KYC submission and on any schedule-based refresh; results land in the KYC record within 60 seconds
4. `result = confirmed_match` on an AML report blocks the investor in the closing room and prevents capital call/distribution payment until the compliance team resolves
5. Every `KycVerificationCheck` and `AmlReport` is audit-logged; result records are immutable once created (corrections create new records)
6. Beneficial owners above 25% must each have their own `BeneficialOwner` record with individual sanctions screening before the entity KYC is considered complete
7. Exception approvals are recorded with: approving user, timestamp, disposition, and notes — all included in the Compliance Evidence Binder
8. Provider API keys are stored in `EntitySetting`; never in code or environment variables checked into VCS
9. Raw provider responses are stored encrypted and retained for 7 years per standard compliance record retention

---

## Integration Points

- `us_investor_taxonomy.md` — reads `us_investor_type` to determine which provider to use (individual vs. entity)
- `closing_room.md` — KYC/KYB verification status and AML result are required closing readiness dimensions
- `compliance_evidence_binder.md` — all verification check records and AML reports included in evidence binder
- `investor_qualification_engine.md` — PEP / sanctions status feeds into qualification exception flags
- `fund_admin_exchange.md` — KYC status (pass/fail/exception) included in fund admin data export
- External: Persona, Middesk, ComplyAdvantage APIs
