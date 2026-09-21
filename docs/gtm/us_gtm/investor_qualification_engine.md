# Investor Qualification Engine

**Approach:** Build — no meaningful existing foundation in CapHive
**Phase:** P0 — required for any US private placement workflow

---

## What This Is

US private funds operate under regulatory exemptions (3(c)(1), 3(c)(7), Regulation D) that impose specific investor eligibility requirements. Every investor admitted to a US fund must meet the eligibility threshold(s) required by that fund's exemption type. These determinations must be documented, defensible, and re-evaluable.

The Investor Qualification Engine is a rules-based system that: (1) reads fund-level eligibility rules configured by the GP or counsel, (2) evaluates investor questionnaire responses against those rules, (3) produces a qualification result with the evidence behind it, and (4) routes exceptions to human review. It does not make final legal determinations — it surfaces the data and routes the decision.

---

## Who Uses It

| Persona | When | What They Need |
|---------|------|----------------|
| **Fund Counsel** | Fund setup | Configure the eligibility rules for each fund vehicle (which exemptions apply, which investor types are allowed) |
| **Operations / Compliance** | Investor onboarding | See each investor's qualification result and the evidence behind it; approve or escalate exceptions |
| **LP (self) via portal** | Completing onboarding questionnaire | Answer eligibility questions appropriate to their investor type; be guided, not confused |
| **COO** | Closing readiness | Confirm all investors in a closing meet eligibility requirements before admission |
| **General Counsel (GP)** | 3(c)(1) fund | Know the current beneficial owner count and get an alert when approaching 100 |

---

## Use Cases

### UC-1: 3(c)(7) Fund — Qualified Purchaser Requirement
A PE fund relies on the 3(c)(7) exemption. Every investor must be a Qualified Purchaser (QP) — holding $5M+ in investments for individuals, $25M+ for institutions. The engine evaluates QP representations from the subscription questionnaire and flags any investor whose stated investment assets are below the threshold or who provides inconsistent answers.

### UC-2: 3(c)(1) Fund — Beneficial Owner Count Alert
A VC fund relies on the 3(c)(1) exemption and can have no more than 100 beneficial owners. The engine tracks the count, accounts for look-through entities (a fund-of-funds counts as multiple beneficial owners), and alerts the GP when approaching 90 to leave room for error.

### UC-3: Qualified Client for Carried Interest
A fund charges carry that is permissible only for Qualified Clients under the Advisers Act. Individual investors must have $2.2M+ in net worth (excluding primary residence) or $1.1M+ in assets under management with the adviser. The engine evaluates QC representations and flags investors who do not meet the threshold.

### UC-4: ERISA Plan Asset Tracking
A fund has some ERISA benefit plan investors (pension funds, 401(k)s). If benefit plan investors exceed 25% of total assets, the fund may become subject to ERISA's plan asset rules, significantly increasing compliance obligations. The engine tracks the benefit plan investor percentage as investors are admitted and alerts when approaching 25%.

### UC-5: Accredited Investor — Regulation D Fund
A smaller fund raises under Regulation D Rule 506(b) or 506(c). Every investor must be an accredited investor (AI): individuals with $200K+ income ($300K joint) or $1M+ net worth, entities with $5M+ in assets. The engine evaluates AI representations and routes borderline cases to counsel review.

### UC-6: Exception Handling — Borderline Qualified Purchaser
An investor's subscription questionnaire states $4.8M in investments — just below the $5M QP threshold. The engine flags this as an exception, explains the gap, and routes it to the compliance team with a suggested action: request updated investment schedule from the investor to confirm the threshold is met.

---

## Current CapHive State

| Capability | Status | Notes |
|------------|--------|-------|
| Fund exemption type field | ⚠️ Partial | Added as FormCustomField on `Fund` via `us_fund_legal_structure.md` — `fund_exemption_type` Select (3(c)(1), 3(c)(7), Reg D, etc.) |
| Investor eligibility fields (AI, QP, QC status) | ⚠️ Partial | Can be FormCustomField on `Investor` (same pattern as `is_benefit_plan_investor` in `us_investor_taxonomy.md`); no eligibility fields seeded yet |
| ERISA benefit plan investor flag | ⚠️ Partial | Already addressed in `us_investor_taxonomy.md` as a CheckBox FormCustomField on `Investor`; ERISA percentage is a computed method on `Fund` |
| Benefit plan investor percentage counter | ⚠️ Partial | Computed method pattern already designed in `us_investor_taxonomy.md` — no separate counter model needed |
| 3(c)(1) beneficial owner count | ❌ Missing | Requires counter logic and look-through rules; not derivable from FormCustomField alone |
| Questionnaire-based eligibility evaluation | ⚠️ Partial | Qualification questions can be a new FormType on `InvestorKyc` (same pattern as US tax form types in `us_tax_forms.md`); evaluation logic still needs to be built |
| Qualification result with evidence | ❌ Missing | `InvestorQualification` record needed for audit trail, status enum, and reviewer approval |
| Exception routing to human reviewer | ⚠️ Partial | Tasks and approvals modules exist; no auto-exception generation |
| Configurable rules per fund | ⚠️ Partial | Basic fund exemption type is a FormCustomField; threshold values and exception approver config still need a model |

---

## Build Approach: FormCustomField-first + minimal new models

This feature follows the same FormCustomField-first pattern as `us_investor_taxonomy.md` and `us_tax_forms.md`. The questionnaire, investor eligibility fields, and fund-level configuration all use the existing `FormCustomField` machinery. New models are added only where an audit-quality record with status, reviewer, and evidence snapshot is genuinely required.

### Step 1: Questionnaire as a FormType on `InvestorKyc` (configuration only)

Create a `FormType` for `IndividualKyc` / `NonIndividualKyc` with `tag = 'US_QUALIFICATION'`. Questions are FormCustomField fields presented as an additional KYC wizard step:

| Field | Type | Notes |
|-------|------|-------|
| `annual_income_individual` | NumberField | AI test — $200K individual / $300K joint threshold |
| `annual_income_joint` | NumberField | Conditional on joint investor type |
| `net_worth_excl_residence` | NumberField | AI test — $1M threshold |
| `total_investments_value` | NumberField | QP test — $5M individual / $25M institutional |
| `assets_under_management` | NumberField | QC test — $1.1M AUM with adviser |
| `is_benefit_plan_investor` | CheckBox | ERISA flag (shared with `us_investor_taxonomy.md` form type) |
| `bad_actor_representation` | CheckBox | Reg D reliance |
| `knowledgeable_employee` | CheckBox | For funds with this eligibility category |
| `qualification_date` | DateField | Date the investor made representations |

These live in `investor_kyc.json_fields`. The `US_QUALIFICATION` step is appended to the existing KYC form after the investor-type-specific step. No new model. No migration.

### Step 2: Eligibility Status Fields as FormCustomField on `Investor` (configuration only)

Extend the `Investor` FormType (tag: `US`) from `us_investor_taxonomy.md` with result fields that operations sets after reviewing questionnaire answers:

| Field | Type | Notes |
|-------|------|-------|
| `is_accredited_investor` | CheckBox | Confirmed by operations after review |
| `is_qualified_purchaser` | CheckBox | Confirmed by operations |
| `is_qualified_client` | CheckBox | Confirmed by operations |
| `qualification_confirmed_at` | DateField | Date of confirmation |

These live in `investor.json_fields`. Reading them: `investor.json_fields["is_qualified_purchaser"]`. No migration.

### Step 3: Fund-Level Eligibility Configuration as FormCustomField on `Fund` (configuration only)

`fund_exemption_type` is already a FormCustomField (from `us_fund_legal_structure.md`). Add threshold and restriction fields to the `US_STRUCTURE` FormType on `Fund`:

| Field | Type | Notes |
|-------|------|-------|
| `erisa_restriction_enabled` | CheckBox | Flag that ERISA 25% threshold tracking is required |
| `three_c1_count_enabled` | CheckBox | Flag that 3(c)(1) beneficial owner count tracking is required |
| `qualification_exception_approver` | TextField | Role name who approves qualification exceptions |

These live in `fund.json_fields`. No migration.

### Step 4: Minimal New Models (only where audit records are required)

**`InvestorQualification`** (belongs to Investor + Fund) — the formal evidence record:
- `investor_id`, `fund_id` FKs
- `rule_type` — enum: `accredited_investor`, `qualified_purchaser`, `qualified_client`, `knowledgeable_employee`, `erisa`, `three_c_1`, `bad_actor`
- `status` — enum: `qualified`, `exception`, `not_eligible`, `pending_review`, `waived`
- `basis` — text (which threshold was met and how)
- `questionnaire_snapshot` — jsonb (copy of relevant `investor_kyc.json_fields` values at time of evaluation — immutable audit evidence)
- `evaluated_at` timestamp
- `reviewed_by_user_id` FK, `reviewed_at` timestamp
- `exception_notes` text

**`BeneficialOwnerCount`** (belongs to Fund, for 3(c)(1) tracking) — counter with look-through logic:
- `fund_id` FK
- `count` integer (updated when investors admitted; look-through applied for entity investors)
- `alert_threshold` integer (default 90)
- `alert_sent_at` timestamp

> **`BenefitPlanInvestorCounter` is NOT needed** — ERISA percentage is already a computed method on `Fund` (`us_investor_taxonomy.md`) reading `investor.json_fields["is_benefit_plan_investor"]` across commitments. Alert logic lives in a background job.

> **`InvestorEligibilityRule` is NOT needed as a model** — fund-level rules are configured via FormCustomField on `Fund` (Step 3). The evaluation thresholds (e.g. QP = $5M) are regulatory constants, not configurable per fund; they are hardcoded in the evaluation service.

### Step 5: Evaluation Service

A lightweight service reads the questionnaire snapshot from `investor_kyc.json_fields` (the `US_QUALIFICATION` form step) and creates/updates `InvestorQualification` records:

```ruby
# InvestorQualificationEvaluator.call(investor_kyc:, fund:)
# Reads: investor_kyc.json_fields["total_investments_value"] etc.
# Reads: fund.json_fields["fund_exemption_type"], ["three_c1_count_enabled"]
# Creates: InvestorQualification records per rule type
# Creates Task for reviewer when status = exception
```

### Rules Engine Logic

```
Fund's json_fields["fund_exemption_type"] determines which rules apply
        │
Investor completes US_QUALIFICATION KYC step (FormCustomField)
        │
InvestorQualificationEvaluator runs
        │
        ├── All thresholds met → InvestorQualification status = qualified
        │                        → investor.json_fields["is_qualified_purchaser"] = true
        ├── Threshold not met  → status = not_eligible → notify GP
        ├── Borderline / ambiguous → status = exception → auto-create Task for reviewer
        └── Fields blank       → status = pending_review → send follow-up to LP
```

---

## Functional Requirements

1. The `US_QUALIFICATION` FormType step is added to the KYC wizard for US funds — questions are FormCustomField, no new model needed for data collection
2. `InvestorQualificationEvaluator` reads `investor_kyc.json_fields` (questionnaire answers) and fund's FormCustomField configuration to produce `InvestorQualification` records; evaluation runs when the KYC `US_QUALIFICATION` step is completed
3. Each `InvestorQualification` stores a `questionnaire_snapshot` jsonb (copy of relevant `json_fields` values at evaluation time) — the evidence is immutable even if the investor later updates their KYC
4. `status = exception` automatically creates a Task assigned to the role in `fund.json_fields["qualification_exception_approver"]`
5. `status = not_eligible` blocks the investor from proceeding in the closing room and notifies the GP
6. ERISA percentage is computed from `investor.json_fields["is_benefit_plan_investor"]` across commitments (existing computed method in `us_investor_taxonomy.md`); background job alerts at 20% and 25%
7. 3(c)(1) beneficial owner count (`BeneficialOwnerCount`) applies look-through rules: a fund-of-funds with fewer than 10 investors counts as one; more than 10 counts as the number of its own investors
8. Confirmed eligibility status (QP, AI, QC) is written back to `investor.json_fields` as named CheckBox fields — readable by the Closing Room, Compliance Evidence Binder, and AI Subscription Review
9. All `InvestorQualification` records are included in the Compliance Evidence Binder (see `compliance_evidence_binder.md`)
10. Qualification status is surfaced as a dimension in the Closing Room readiness checklist via the `check_investor_qualification` agent step

---

## Revised Build Estimate

| Item | Effort |
|------|--------|
| Seed `US_QUALIFICATION` FormType with 9 questionnaire fields on `InvestorKyc` | 1 day (configuration) |
| Seed eligibility status fields (AI/QP/QC CheckBoxes) on `Investor` FormType | 0.5 day (configuration) |
| Seed fund eligibility config fields on `Fund` `US_STRUCTURE` FormType | 0.5 day (configuration) |
| `InvestorQualification` model + migration | 1 day |
| `BeneficialOwnerCount` model + look-through logic + migration | 1 day |
| `InvestorQualificationEvaluator` service (reads json_fields, creates qualification records) | 2 days |
| Closing Room agent step (`check_investor_qualification`) | 1 day |
| Exception Task auto-creation + not-eligible notification | 0.5 day |
| **Total** | **~7 days** vs. ~4 weeks for full model-first approach |

---

## Integration Points

- `us_fund_legal_structure.md` — reads `fund.json_fields["fund_exemption_type"]` to determine which rules apply; fund eligibility config fields added to the same `US_STRUCTURE` FormType
- `us_investor_taxonomy.md` — shares `is_benefit_plan_investor` CheckBox FormCustomField on `Investor`; ERISA percentage computed method already defined there
- `us_tax_forms.md` — same `US_QUALIFICATION` KYC step sits alongside the W-9/W-8 form step in the KYC wizard
- `closing_room.md` — `check_investor_qualification` agent step reads `InvestorQualification` records
- `compliance_evidence_binder.md` — `InvestorQualification` records + `questionnaire_snapshot` exported as part of investor compliance evidence
- Existing: `FormType`, `FormCustomField`, `InvestorKyc`, `Investor` (all include `WithCustomField`)
