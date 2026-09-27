# side-letter-obligations

## Purpose

Stores each investor side letter against its capital commitment, together with the individual
obligations it imposes, so those obligations can be reviewed and tracked instead of living only
inside the executed document.

## Requirements

### Requirement: SideLetter record anchored on a capital commitment
The system SHALL store each side letter as a `SideLetter` record belonging to a `CapitalCommitment`, referencing the executed side letter `Document`, with `executed_at` and an `extraction_status` of `pending`, `ai_extracted`, `manually_entered`, or `counsel_reviewed`.

#### Scenario: Create side letter from a commitment document
- **WHEN** a user creates a `SideLetter` for a commitment and selects a document attached to that commitment
- **THEN** the side letter is saved with `extraction_status = pending` and appears on the commitment's side letter section

#### Scenario: Side letter document must belong to the same commitment
- **WHEN** a user attempts to link a `SideLetter` to a document owned by a different commitment
- **THEN** validation fails with an error naming the mismatch

### Requirement: Structured SideLetterObligation records
The system SHALL store each obligation as a `SideLetterObligation` belonging to a `SideLetter`, capturing `obligation_type` (reporting, fees, co_investment, notice, transfer, excuse, confidentiality, key_person, mfn, other), `title`, `description`, `source_clause`, owner (`owner_user_id` and/or `owner_team`), `trigger_type` (calendar_event, fund_event, deal_event, status_change, one_time, ongoing), `trigger_description`, `frequency_rrule`, `next_due_date`, `review_status`, `status`, `reminder_days_before`, `mfn_relevant`, `extracted_by`, and `ai_confidence`.

#### Scenario: Manual obligation entry
- **WHEN** a user manually adds an obligation with type, title, trigger type, and owner
- **THEN** it is saved with `extracted_by = manual` and `review_status = pending_review`

### Requirement: Counsel review gate
An `SideLetterObligation` SHALL start in `review_status = pending_review` and MUST be approved by a user before it is treated as active anywhere in the system. Approval MUST be rejected if the obligation has neither `owner_user_id` nor `owner_team`.

#### Scenario: Approving an owned obligation
- **WHEN** a reviewer approves a pending obligation that has an owner
- **THEN** `review_status` becomes `approved` and `status` becomes `active`

#### Scenario: Approval blocked without owner
- **WHEN** a reviewer attempts to approve a pending obligation with no owner user and no owner team
- **THEN** the approval is rejected with an error stating an owner is required

#### Scenario: Rejecting an obligation
- **WHEN** a reviewer rejects a pending obligation
- **THEN** `review_status` becomes `rejected` and the obligation never generates tasks or alerts

### Requirement: Fulfillment audit trail
The system SHALL record each fulfillment of an obligation as an `ObligationFulfillment` capturing `fulfilled_at`, `fulfilled_by_user_id`, a required `method` description, `period_covered`, and an optional evidence `document_id`.

#### Scenario: Fulfillment requires a method description
- **WHEN** a fulfillment is recorded without a method description
- **THEN** validation fails

#### Scenario: Fulfillment history visible on the obligation
- **WHEN** a user views an obligation with past fulfillments
- **THEN** all fulfillment records are listed with date, user, method, and evidence link where present

### Requirement: LP Obligation Matrix view
The system SHALL provide a per-fund matrix listing obligations across all LPs with columns for investor, type, obligation title, owner, next due date, and status, filterable by obligation type, owner team, due date range, review status, and MFN relevance.

#### Scenario: Matrix shows armed and dated obligations
- **WHEN** a fund has approved calendar-driven, one-time, and event-triggered obligations
- **THEN** dated obligations show their next due date and event-triggered obligations show as armed with no due date

#### Scenario: Filter by review status
- **WHEN** a user filters the matrix by `pending_review`
- **THEN** only unreviewed obligations are shown

### Requirement: Authorization
Access to side letters and obligations SHALL be governed by Pundit policies scoped to the entity, and every controller action MUST have a corresponding policy method.

#### Scenario: Non-admin cannot approve obligations
- **WHEN** a user without the required role attempts to approve an obligation
- **THEN** the action is denied by policy
