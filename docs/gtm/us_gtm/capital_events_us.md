# Capital Events — US Enhancements

**Approach:** Enhance existing `CapitalCall`, `CapitalDistribution`, `CapitalCommitment`, and `CapitalRemittance` models
**Phase:** P1 — core engine is solid; these enhancements are required for production US use

---

## What This Is

CapHive's capital events engine (capital calls, distributions, commitments) is one of the platform's strongest areas. The core computation — per-investor amounts, fund close equalization, multi-currency, fees, approval workflow, payment status lifecycle — is production-ready.

This feature covers the specific enhancements required for US fund operations that are either missing entirely or insufficiently developed for the US ICP's expectations: unfunded commitment as a named tracked field, dual/maker-checker approval, a fund bank account object for wire instructions, fraud warning language enforcement, recallable distribution tracking, default interest on overdue calls, and a structured reconciliation export for fund administrators.

---

## Who Uses It

| Persona | When | What They Need |
|---------|------|----------------|
| **Operations / Finance** | Preparing capital calls and distributions | Unfunded commitment on the notice; dual approval before sending; verified wire instructions auto-embedded |
| **CFO / COO** | Approving capital events | Second-approver step; ability to see who approved and when |
| **LP (self) via portal** | Receiving a capital call or distribution notice | See their unfunded commitment; clearly stated wire instructions with fraud warning |
| **Compliance** | Post-event review | Evidence that dual approval occurred; fraud warning language was included |
| **Fund Administrator** | Receiving payment data | Structured reconciliation export showing expected vs. received per investor |

---

## Use Cases

### UC-1: Capital Call Notice with Unfunded Commitment
An LP receives a capital call notice showing: commitment amount ($5M), amount called to date ($1.5M), this call amount ($600K, 12% of commitment), and unfunded commitment after this call ($2.9M). This information is pulled from commitment data and displayed on the notice automatically — not manually calculated by the operations team.

### UC-2: Dual Approval Before a Large Distribution
A $12M distribution to 80 investors requires two approvers to sign off before notices go out. The CFO approves as first approver. The system routes to the COO for second approval. Both approvals are recorded with timestamp and user. Only after both approvals does the distribution move to "approved" and notices are sent.

### UC-3: Wire Instructions Auto-Populated in Call Notice
When generating a capital call notice, the system pulls the fund's verified bank account record and embeds the wire instructions (bank name, ABA routing number, account number, account name, reference) into the call notice template automatically. The fund bank account record must have `verification_status = verified` before it can be used in notices.

### UC-4: Fraud Warning Language on Every Notice
Every capital call and distribution notice includes a standard anti-fraud warning: "Wire instructions for this fund will never be changed by email. If you receive any communication requesting a change to the wire instructions below, do not comply — contact [GP contact] immediately." This language is system-enforced; it cannot be omitted from the notice template.

### UC-5: Recallable Distribution
A fund distributes $3M to investors from a portfolio company partial exit. The distribution is marked as "recallable" because the LPA allows the GP to call back distributed amounts if needed to fund future capital calls. CapHive records the recallable flag, tracks the amount within the recall window, and surfaces the recallable distribution balance when calculating unfunded commitment.

### UC-6: Default Interest on Overdue Capital Call
An LP's remittance is 15 days overdue. Per the LPA, default interest accrues at 18% per annum from the due date. CapHive calculates the default interest amount based on the overdue period and the LPA rate configured for the fund, and generates a default interest notice to the LP.

### UC-7: Fund Admin Reconciliation Export
After a capital call is completed, the CFO exports a reconciliation file: one row per investor showing commitment, equalization basis, amount called, amount received, variance, and payment date. The file format is pre-configured to match the fund administrator's import template.

---

## Current CapHive State

| Capability | Status | Notes |
|------------|--------|-------|
| Capital call amount calculation (%, account entry, upload) | ✅ Exists | Solid; multiple call bases |
| Fund close equalization | ✅ Exists | Per-close percentages; different % per tranche |
| Payment status (Pending/Overdue/Paid/Overpaid) | ✅ Exists | Status lifecycle with background job |
| Single-approver workflow | ✅ Exists | `approved_by_user_id` on call and distribution |
| Notice document generation per remittance | ✅ Exists | Uses "Call Template" document template |
| Manual payment reminders | ✅ Exists | Send Reminder button on call and remittance pages |
| Unfunded commitment as a named tracked field | ⚠️ Partial | `unfunded_commitment_as_of(end_date)` already exists as a computed method on `CapitalCommitment` (`capital_commitment_shared.rb`); not a stored field and not yet surfaced on notices or LP portal |
| Dual / maker-checker approval | ❌ Missing | Only one approver role; no second-approver requirement |
| Fund bank account object | ❌ Missing | No fund bank account model; wire instructions live in the notice template only |
| Wire instructions auto-populated in notices | ❌ Missing | No structured bank account to pull from; template-only today |
| Fraud warning language enforcement | ❌ Missing | Can be added to templates manually; not system-enforced |
| Recallable distribution flag and tracking | ❌ Missing | No recallable flag on distribution; no recall window tracking |
| Default interest calculation on overdue | ❌ Missing | Overdue status tracked; no default interest computation |
| Fund admin reconciliation export | ⚠️ Partial | Report Builder can generate data; no structured fund-admin-format export |

---

## Build Approach: Enhance existing `funds/capital_calls`, `funds/capital_distributions`, `funds/capital_commitments` packs

### New Model: `FundBankAccount` (belongs to Fund/Entity)

```ruby
# app/packs/funds/funds/models/fund_bank_account.rb
```

- `fund_id` FK
- `bank_name`, `account_holder_name` strings
- `routing_number_encrypted` (ABA)
- `account_number_encrypted`
- `account_type` — enum: `checking`, `savings`
- `swift_code` (for international transfers)
- `bank_address` text
- `purpose` — enum: `capital_calls`, `distributions`, `both`
- `verification_status` — enum: `unverified`, `verified`
- `verified_by_user_id`, `verified_at`
- `active` boolean
- `document_id` FK (bank letter or voided check confirming account)

### Enhancements to `CapitalCommitment`

Add computed/stored field:
- `unfunded_commitment` — stored decimal, recomputed whenever called_amount or committed_amount changes
- Formula: `committed_amount - called_amount + recallable_distribution_amount` (recallable distributions add back to unfunded commitment per standard US LPA terms)

Surface on:
- Commitment list view (new column)
- Capital call notice template (available as a merge field `{{unfunded_commitment}}`)
- LP portal commitment summary

### Enhancements to `CapitalCall` and `CapitalDistribution`

**Dual approval:**
- Add `second_approver_required` boolean to `Fund` settings (configurable per fund)
- Add `second_approved_by_user_id`, `second_approved_at` to both models
- Add `approval_status` — enum: `pending_first`, `pending_second`, `fully_approved`; notices only send when `fully_approved`
- First approver cannot be the same user as second approver

**Fraud warning:**
- Add `fraud_warning_text` to `EntitySetting` (default text provided; overridable per GP)
- Notice template generation injects `{{fraud_warning}}` merge field; generation fails if the field is missing from the template

### Enhancements to `CapitalDistribution`

**Recallable distributions:**
- Add `recallable` boolean, default false
- Add `recall_window_days` integer (from LPA terms; e.g. 180 days)
- Add `recall_deadline` computed date (`distribution_date + recall_window_days`)
- Background job: sets `recall_expired = true` on distributions past their recall deadline
- `CapitalCommitment.unfunded_commitment` includes active recallable distributions in its computation

### New Model: `DefaultInterestNotice` (belongs to CapitalRemittance)

- `capital_remittance_id` FK
- `overdue_days` integer
- `principal_amount` decimal
- `annual_rate_percent` decimal (from fund settings)
- `interest_amount` decimal (computed: `principal × rate × overdue_days / 365`)
- `period_start`, `period_end` dates
- `document_id` FK (generated default interest notice)
- `status` — enum: `draft`, `sent`, `waived`

Fund settings: add `default_interest_rate_percent` and `default_interest_grace_days` to `FundUnitSetting` or `EntitySetting`.

### Reconciliation Export

Add a "Export for Fund Admin" action on the CapitalCall and CapitalDistribution show pages:
- One row per remittance/payment
- Columns: folio_id, investor_name, commitment_amount, amount_called, equalization_basis, this_call_amount, amount_received, variance, payment_date, payment_status, bank_name, routing_number_last4
- Format: CSV and XLSX
- Fund admin format presets: configurable per fund (e.g. "Alter Domus format," "Standish format") — maps CapHive fields to the admin's expected column names

---

## Functional Requirements

1. `unfunded_commitment` is computed and stored on `CapitalCommitment`; it appears as a merge field on capital call notices and on the LP's portal commitment summary
2. `second_approver_required = true` on a fund blocks capital call/distribution approval until a second user with Approver role signs off; the first and second approver cannot be the same person
3. `FundBankAccount` with `verification_status = verified` is required before a capital call notice can be generated that includes wire instructions; unverified accounts produce a warning
4. Fraud warning text is injected into every call and distribution notice; template validation fails if the `{{fraud_warning}}` merge field is absent
5. `recallable = true` distributions are tracked against their `recall_deadline`; `CapitalCommitment.unfunded_commitment` includes recallable distribution amounts until the recall window expires
6. Default interest: when a remittance moves to `overdue` and has been overdue for more than `default_interest_grace_days`, a `DefaultInterestNotice` is created automatically (if `default_interest_rate_percent > 0` is configured)
7. Reconciliation export is available for all approved capital calls and distributions; fund admin format presets are configurable and saved per fund

---

## Integration Points

- `bank_instruction_controls.md` — `FundBankAccount` is verified using the same controls model; LP bank instructions and fund bank account are distinct record types
- `compliance_evidence_binder.md` — dual approval records included in compliance evidence
- `fund_admin_exchange.md` — reconciliation export format is defined here; fund admin exchange layer consumes it
- `us_tax_forms.md` — distribution withholding rates from W-8 classification affect net payable computation
- `closing_room.md` — unfunded commitment displayed in closing room commitment summary
