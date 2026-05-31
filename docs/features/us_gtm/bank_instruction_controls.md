# Bank Instruction Controls & Payment Verification

**Approach:** Build new module + Integrate (Plaid for account verification)
**Phase:** P0 — required before capital calls and distributions can be issued

---

## What This Is

Distribution fraud is a significant and growing risk in private fund operations. Attackers impersonate LPs and change bank instructions shortly before a distribution, diverting funds to fraudulent accounts. In the US, where wire transfers are typically irreversible, a single undetected bank instruction change can result in millions of dollars lost.

This module creates a Payment Instructions Control Center: a lifecycle for capturing, verifying, approving, and changing LP bank instructions, with fraud controls baked into every step. It integrates with Plaid for real-time bank account verification and enforces dual approval and time-lock rules on changes.

CapHive's KYC records (`IndividualKyc`, `NonIndividualKyc`) already store bank details — `bank_account_number`, `bank_name`, `bank_account_type`, `bank_branch`, `bank_verified` (boolean), and `bank_verification_response` — with India-specific IFSC/account verification via `VerifyBankJob`. What does not exist is a separate, fraud-controlled `BankInstruction` lifecycle model with US provider (Plaid) verification, change approvals, time-locks, and a pre-distribution fraud check.

---

## Who Uses It

| Persona | When | What They Need |
|---------|------|----------------|
| **LP (self) via portal** | Onboarding, and when changing bank details | Submit bank details securely; complete verification steps; receive confirmation |
| **Operations / Finance** | Capital call and distribution preparation | See verified bank status for every investor before sending a call/distribution; act on exceptions |
| **CFO / COO** | Bank instruction change requests | Approve or reject change requests; see dual approval status |
| **Compliance** | Audit or fraud investigation | Full audit trail of every bank instruction submission, verification, and change |
| **Fund Administrator** | Receiving wire payment data | Get a clean, verified wire instruction record for each investor |

---

## Use Cases

### UC-1: New Investor Submits Bank Details During Onboarding
An LP completing their onboarding submits their bank account details through the portal. CapHive initiates a Plaid verification (instant or micro-deposit). On success, the account is marked verified and available for capital calls and distributions.

### UC-2: Bank Instruction Change Request — Low Risk
An LP changes their bank account from one Chase account to another Chase account under the same name. CapHive flags this as a change, triggers re-verification via Plaid, notifies the operations team, and marks the new account as pending. The old account remains active until the new account is verified and approved.

### UC-3: Bank Instruction Change Request — High Risk (Distribution Fraud Scenario)
An LP requests a bank instruction change 48 hours before a $3M distribution. CapHive flags this as high-risk (change within 5 days of a pending distribution), places a 72-hour hold on the new account, requires dual approval from two members of the operations team, and sends a confirmation to the LP's registered email (not the new contact information provided). The distribution proceeds to the old verified account unless the GP explicitly overrides with dual approval.

### UC-4: Wire Instruction Evidence for Institutional LP
An institutional LP provides wire instructions as a PDF (common for large LPs with internal treasury systems). Operations uploads the PDF, marks it as reviewed, and logs the approval. The record shows who reviewed it, when, and links to the PDF. This creates auditable evidence without requiring Plaid integration.

### UC-5: ACH Authorization for Smaller LP
A fund wants to collect capital calls via ACH debit from smaller LPs. LP provides account details and signs an ACH authorization. CapHive stores the authorization, verifies the account via Plaid, and passes the details to the payment processor for debit at capital call time.

### UC-6: Pre-Distribution Fraud Check
Before the operations team approves a distribution, the system automatically checks: (1) any bank instructions changed within the last 30 days for investors receiving this distribution; (2) new accounts not yet fully verified; (3) accounts with outstanding change approvals. Flagged items appear in a pre-distribution exception review.

---

## Current CapHive State

| Capability | Status | Notes |
|------------|--------|-------|
| Bank account / payment details storage | ⚠️ Partial | Bank fields (`bank_account_number`, `bank_name`, `bank_account_type`, `bank_branch`, `bank_verified`, `bank_verification_response`) exist on KYC records; missing: a separate `BankInstruction` model with lifecycle (submission, verification, change, approval, hold) |
| Bank account verification (Plaid / micro-deposit) | ⚠️ Partial | India-specific IFSC/account verification via `VerifyBankJob`; missing: US-specific Plaid instant and micro-deposit verification |
| Bank instruction change controls | ❌ Missing | Not in the system |
| Dual approval on bank changes | ❌ Missing | Not in the system |
| Fraud hold / time-lock on changes before distributions | ❌ Missing | Not in the system |
| Audit trail for bank instruction changes | ❌ Missing | Not in the system |
| Wire instruction document upload and approval | ❌ Missing | Not in the system |
| Pre-distribution fraud check | ❌ Missing | Not in the system |
| ACH authorization capture | ❌ Missing | Not in the system |

---

## Build Approach: New pack `funds/bank_instructions` + Plaid integration

### New Models

**`BankInstruction`** (belongs to Investor + Fund)
- `investor_id`, `fund_id` FKs
- `instruction_type` — enum: `wire`, `ach`, `check`, `other`
- `bank_name`, `account_holder_name` strings
- `routing_number_encrypted` (ABA for wire/ACH)
- `account_number_encrypted`
- `account_type` — enum: `checking`, `savings`, `other`
- `iban_encrypted` (for international wires)
- `swift_code` (for international wires)
- `verification_status` — enum: `unverified`, `pending_verification`, `verified`, `failed`, `expired`
- `verification_method` — enum: `plaid_instant`, `plaid_micro_deposit`, `manual_review`, `wire_instruction_doc`
- `plaid_item_id`, `plaid_account_id` (for Plaid-verified accounts)
- `verified_at`, `verified_by_user_id`
- `active` — boolean (only one active instruction per investor per fund)
- `document_id` FK (for wire instruction PDF uploads)
- `submitted_by` — enum: `investor_self`, `fund_team`

**`BankInstructionChange`** (belongs to BankInstruction)
- `previous_bank_instruction_id`, `new_bank_instruction_id` FKs
- `requested_by` — enum: `investor`, `fund_team`
- `requested_at` timestamp
- `risk_level` — enum: `low`, `medium`, `high` (computed: high if within 30 days of distribution)
- `status` — enum: `pending_verification`, `pending_approval`, `approved`, `rejected`, `expired`
- `hold_until` date (72-hour hold for high-risk changes)
- `first_approver_id`, `first_approved_at`
- `second_approver_id`, `second_approved_at` (required for high-risk)
- `rejection_reason` text
- `investor_confirmation_sent_at` (confirmation email to LP's registered email)

**`AchAuthorization`** (belongs to BankInstruction)
- `authorized_by_name` string
- `authorized_at` date
- `authorization_type` — enum: `debit`, `credit`
- `document_id` FK (signed authorization form)

### Plaid Integration

**Instant Account Verification (IAV):**
- LP connects bank account via Plaid Link (embedded in portal)
- CapHive receives Plaid `item_id` and `account_id`; stores encrypted
- Account holder name matching: Plaid returns account owner name; system compares against investor legal name; flags mismatches

**Micro-deposit Verification (fallback):**
- If Plaid Link is unavailable or LP prefers manual: CapHive initiates two micro-deposits via Plaid ACH
- LP confirms the two amounts in the portal within 3 days
- On confirmation: account marked verified

**Plaid API keys** stored in `EntitySetting`; one per GP entity.

### Fraud Hold Logic

```
Bank instruction change submitted
        │
        ▼
Risk assessment
  ├── Change within 30 days of pending capital call or distribution → HIGH risk
  ├── New bank name differs from existing → MEDIUM risk
  └── Same bank, same name, routing number change → LOW risk
        │
HIGH risk path:
  ├── 72-hour hold placed on new account
  ├── Dual approval required (two operations team members)
  ├── Confirmation email sent to investor's ORIGINAL registered email
  └── Distribution/call uses OLD account until hold expires AND dual approved

LOW/MEDIUM risk path:
  ├── Re-verification via Plaid
  ├── Single approver sign-off
  └── Operations team notification
```

### Pre-Distribution Check

Before a capital distribution or capital call can be approved:
- System queries: any `BankInstruction.verification_status != verified` for investors in this event
- System queries: any `BankInstructionChange.status = pending_approval` for investors in this event
- System queries: any instruction changed within the last 30 days
- Flagged investors appear in a pre-event exception review modal; approval is blocked until exceptions are resolved or explicitly overridden

---

## Functional Requirements

1. Routing numbers and account numbers are encrypted at rest; access-logged on every read
2. Every bank instruction submission, verification, change, and approval creates an immutable audit log entry
3. Only one `BankInstruction` per investor per fund can have `active = true` at a time
4. High-risk changes enforce a 72-hour hold and dual approval; neither condition can be bypassed without a system-level override recorded with reason
5. Investor confirmation email is always sent to the investor's original portal email — not to any email provided in the change request
6. Wire instruction document uploads require a manual review approval by an operations team member before the account is marked verified
7. ACH authorizations must be signed before ACH debit is permitted; unsigned authorization blocks ACH payment
8. Pre-distribution check runs automatically when a capital call or distribution is moved to approval state; exceptions must be cleared before approval can proceed
9. Plaid API errors are handled gracefully; fallback to manual review is always available

---

## Integration Points

- `capital_events_us.md` — pre-distribution check reads `BankInstruction.verification_status`; verified account number populates wire instruction in call/distribution notice
- `closing_room.md` — bank verification status is a required closing readiness dimension
- `compliance_evidence_binder.md` — bank verification records and change audit log included in investor compliance binder
- `fund_admin_exchange.md` — verified wire instructions exported to fund admin in structured format
- External: Plaid API for account verification; Plaid Link for LP-facing bank connection
