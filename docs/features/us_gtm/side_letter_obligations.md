# Side Letter & LP Obligation Matrix

**Approach:** Build — no side letter or obligation tracking module exists in CapHive
**Phase:** P1/P2 — high differentiation; start with manual entry, layer AI extraction on top

---

## What This Is

Side letters are legally binding agreements between a GP and a specific LP that modify or supplement the terms of the Limited Partnership Agreement. They create obligations: reporting requirements, fee arrangements, co-investment rights, notice requirements, key person provisions, transfer rights, and more. These obligations are operationally dangerous because they live in PDFs reviewed at closing and then largely forgotten — until an LP calls to enforce them.

The LP Obligation Matrix is CapHive's answer: a structured, searchable, actionable record of every obligation in every side letter, with action owners, trigger conditions, and reminder workflows. Phase 1 is manual entry and tracking. Phase 2 layers AI extraction on top (see `ai_document_intelligence.md`).

---

## Who Uses It

| Persona | When | What They Need |
|---------|------|----------------|
| **General Counsel / Legal Team** | After a closing and ongoing | Know every obligation that was agreed to; approve AI-extracted obligations before they become active |
| **IR Director** | Ongoing LP servicing | See upcoming reporting obligations and co-investment notifications before they trigger |
| **Deal Team** | When a new investment is being made | Check whether any LP has a co-investment right that must be offered before the investment closes |
| **Finance / CFO** | Fee calculation periods | See all reduced fee arrangements and verify they are applied correctly |
| **COO** | Compliance review and LP due diligence | Demonstrate that all side letter obligations are tracked and fulfilled |

---

## Use Cases

### UC-1: Quarterly ESG Report Obligation
LP Alpha has a side letter requiring a quarterly ESG impact report within 45 days of each quarter-end. The obligation matrix shows this as an active obligation with the next due date (October 14 for Q3 2026), the owner (IR team), and the trigger (Q3 close). 10 days before the due date, the owner receives a reminder notification.

### UC-2: Reduced Management Fee
LP Beta has a reduced management fee of 1.5% during the commitment period (vs. standard 1.75%). The obligation matrix records this as a fee arrangement. Each time a management fee notice is issued, the system flags LP Beta's fee for review to confirm the reduced rate is applied.

### UC-3: Co-Investment Right Trigger
LP Gamma has a right to co-invest alongside the fund on deals above $15M total investment. When the deal team is preparing a new investment above the threshold, CapHive alerts the IR team: "LP Gamma has a co-investment right — notify by [date] before this deal closes." The team sends the notification and records it.

### UC-4: MFN Clause Detection
Counsel reviews the newly extracted obligation matrix and notices that LP Epsilon's side letter contains a reporting obligation more favorable than the standard LPA. Three other LPs have MFN provisions in their side letters. Counsel reviews whether the MFN is triggered and documents their determination.

### UC-5: Key Person Notification
LP Delta's side letter requires the GP to notify LP Delta within 5 business days if a key person leaves. When a key person event occurs, the system surfaces all LPs with key person notice obligations and prompts the IR team to send notifications. The notification is logged with timestamp and method.

### UC-6: Transfer Right Negotiation
An LP wants to transfer part of their fund interest. The operations team checks the obligation matrix to confirm: does this LP have a side letter restricting transfer? Does the transfer require GP consent? Are there right-of-first-offer provisions that apply? All of these are surfaced in under 30 seconds.

---

## Current CapHive State

| Capability | Status | Notes |
|------------|--------|-------|
| Document upload and storage per investor | ✅ Exists | Side letters can be uploaded as documents in the investor's folder |
| Document AI Q&A (`DocQuestion`) | ✅ Exists | AI can extract question/answer pairs from documents; foundation for obligation extraction |
| Tasks module | ✅ Exists | Tasks can be used to track obligations manually; not structured as obligation records |
| Side letter model | ❌ Missing | No side letter record type; side letters are plain documents with no structured data |
| LP obligation record | ❌ Missing | No obligation model; obligations would need to be tasks |
| MFN tracking | ❌ Missing | No comparison logic across investor side letters |
| Obligation trigger and reminder workflow | ❌ Missing | Tasks have due dates and reminders but are not tied to fund calendar events |
| Obligation owner assignment | ⚠️ Partial | Tasks have assignees; not obligation-specific |
| AI-assisted obligation extraction | ❌ Missing | To be built in Phase 2 (see `ai_document_intelligence.md`) |

---

## Build Approach: New pack `funds/side_letters`

### New Models

**`SideLetter`** (belongs to Investor + Fund)
- `investor_id`, `fund_id` FKs
- `executed_at` date
- `document_id` FK (the executed side letter PDF)
- `extraction_status` — enum: `pending`, `ai_extracted`, `manually_entered`, `counsel_reviewed`
- `notes` text

**`LpObligation`** (belongs to SideLetter)
- `side_letter_id` FK
- `obligation_type` — enum: `reporting`, `fees`, `co_investment`, `notice`, `transfer`, `excuse`, `confidentiality`, `key_person`, `mfn`, `other`
- `title` string (short description, e.g. "Quarterly ESG report")
- `description` text (full obligation text or paraphrase)
- `source_clause` string (e.g. "Section 4.3(b)")
- `owner_user_id` FK
- `owner_team` — enum: `ir`, `finance`, `legal`, `deal_team`, `operations`
- `trigger_type` — enum: `calendar_event`, `fund_event`, `deal_event`, `status_change`, `one_time`, `ongoing`
- `trigger_description` text (e.g. "Within 45 days of each quarter-end")
- `next_due_date` date (computed or manually set)
- `status` — enum: `active`, `fulfilled`, `waived`, `expired`, `disputed`
- `mfn_relevant` boolean (flags obligations that may trigger MFN rights for other LPs)
- `mfn_review_status` — enum: `not_reviewed`, `no_trigger`, `triggered_matched`, `triggered_exception`
- `extracted_by` — enum: `manual`, `ai` (Phase 2)
- `ai_confidence` decimal (Phase 2)

**`ObligationFulfillment`** (belongs to LpObligation)
- `lp_obligation_id` FK
- `fulfilled_at` date
- `fulfilled_by_user_id` FK
- `method` text (e.g. "ESG report sent via portal and email")
- `document_id` FK (evidence document, if applicable)
- `period_covered` string (e.g. "Q3 2026")

**`ObligationReminder`** (belongs to LpObligation)
- `lp_obligation_id` FK
- `reminder_days_before` integer (e.g. 14 days before due date)
- `sent_at` timestamp
- `recipient_user_id` FK

### LP Obligation Matrix View

The matrix is the primary UI for this feature: a table of all active obligations across all LPs for a fund, grouped by type or investor.

| Investor | Type | Obligation | Owner | Next Due | Status |
|----------|------|-----------|-------|----------|--------|
| LP Alpha | Reporting | Quarterly ESG report (45 days after Q-end) | IR | Oct 14 | ⚠️ Due in 12 days |
| LP Beta | Fees | Management fee 1.5% (vs. 1.75% standard) | Finance | On each fee notice | Active |
| LP Gamma | Co-invest | Offer deals > $15M | Deal Team | On deal close | Active |
| LP Delta | Notice | Key person event — notify within 5 days | Legal | On event | Standby |
| LP Epsilon | Reporting | Audited financials by Apr 30 | IR | Apr 30 | Active |

Filters: by obligation type, by owner team, by due date range, by MFN relevance.

### Reminder Workflow
- Background job runs daily; checks `LpObligation.next_due_date` for obligations due within `reminder_days_before` days
- Sends in-app notification and email to `owner_user_id`
- Reminder records logged; repeat reminders sent if obligation not fulfilled by due date

### MFN Comparison
- Counsel marks `mfn_relevant = true` on obligations during review
- System surfaces a "MFN Review" dashboard showing all MFN-relevant obligations across investors
- Counsel can review, set `mfn_review_status`, and add notes for each
- No automatic MFN determination — this is a legal judgment; the system only surfaces the data

---

## Functional Requirements

1. Side letter document upload creates a `SideLetter` record; obligations are added manually (Phase 1) or via AI extraction (Phase 2)
2. Every `LpObligation` must have an `owner_user_id` or `owner_team` before it can be set to `active`
3. Obligations with `trigger_type = calendar_event` automatically compute `next_due_date` from the fund calendar; others require manual date setting
4. `ObligationFulfillment` records require a fulfillment method description; document evidence is optional but encouraged
5. Reminders cannot be disabled at the user level; they can be configured at the obligation level (`reminder_days_before = 0` to suppress)
6. MFN review is required by legal before any `mfn_relevant = true` obligation is considered closed
7. Obligation history (all fulfillment records) is included in the Compliance Evidence Binder

---

## Integration Points

- `ai_document_intelligence.md` — AI extraction of obligations from side letter PDF populates `LpObligation` records in Phase 2
- `closing_room.md` — side letter execution status is a required closing readiness dimension
- `compliance_evidence_binder.md` — all active obligations and their fulfillment history included in evidence binder
- `capital_events_us.md` — fee arrangement obligations flagged when generating management fee notices
- Existing `Document` model — side letter document linked to `SideLetter` record
