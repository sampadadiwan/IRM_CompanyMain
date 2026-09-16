# AI Subscription Review

**Approach:** Build — new AI feature; builds on existing `SupportAgent`, `AiRule`, and `DocQuestion` infrastructure
**Phase:** P2 — requires base subscription workflow (P0) to be live

---

## What This Is

Subscription documents are long, repetitive, and manually reviewed by fund admins, GP operations teams, and counsel. A standard PE fund subscription packet is 40–80 pages across multiple documents. For a 50-LP closing, that is thousands of pages reviewed to find exceptions that could be caught algorithmically.

The AI Subscription Review feature uses CapHive's existing AI infrastructure (Support Agents, AI Rules, DocQuestion) to automatically review completed subscription packets, surface exceptions, explain the specific issue with a document reference, and route each exception to the appropriate human reviewer. The AI never approves or rejects an investor — it surfaces and routes.

---

## Who Uses It

| Persona | When | What They Need |
|---------|------|----------------|
| **Fund Administrator (operations)** | After each investor completes their subscription packet | See a prioritized list of exceptions that need attention — without reading every page manually |
| **Fund Counsel** | During closing | Focus their legal review on the exceptions that require legal judgment; skip the mechanical checks |
| **Operations Team** | Day-to-day closing management | Know which investors need follow-up for specific document issues — without manually checking each packet |
| **COO** | Closing quality assurance | Confirm that every packet has been reviewed before investor admission |

---

## Use Cases

### UC-1: Missing Signature Detection
An investor submits their subscription agreement with all pages completed but one signature block on page 34 unsigned. The AI review surfaces this: "Missing signature: Page 34, Section 9.4 (LP Release). The investor signatory block shows no signature. Action: re-send page 34 for completion."

### UC-2: Name Inconsistency Across Documents
The investor's name appears as "Meridian Capital Partners LLC" in the subscription agreement but "Meridian Capital, LLC" in the W-9. The AI flags: "Name mismatch: subscription agreement uses 'Meridian Capital Partners LLC'; W-9 uses 'Meridian Capital, LLC.' Confirm legal name with investor and correct the inconsistent document."

### UC-3: Tax Form Type Mismatch
An investor marked themselves as a "US LLC" in the investor questionnaire but submitted a W-8BEN-E (non-US entity form). The AI flags: "Tax form mismatch: investor questionnaire states US LLC (requires W-9); submitted form is W-8BEN-E. Clarify investor's US/non-US status."

### UC-4: Incomplete Eligibility Answer
An investor's qualified purchaser questionnaire leaves the "total value of investments" field blank. The AI flags: "Incomplete QP response: Section 3.2 of the investor questionnaire requires the investor's total investment assets. Field is blank. Cannot confirm QP status. Action: request completion from investor."

### UC-5: Beneficial Owner Count Inconsistency
An entity investor's subscription questionnaire lists 2 beneficial owners, but the beneficial owner certification attached to the W-8BEN-E lists 3 beneficial owners. The AI flags: "Beneficial owner count inconsistency: questionnaire states 2 owners; W-8BEN-E certification lists 3. Confirm which is accurate and update the lower-count document."

### UC-6: ERISA Investor — Missing Representation
An investor checked "benefit plan investor" in the eligibility questionnaire but the subscription agreement's ERISA representation section (Section 7.3) is not initialled. The AI flags: "ERISA representation unsigned: investor is a benefit plan investor but did not initial Section 7.3 of the subscription agreement. Action: re-send Section 7.3 for initials."

---

## Current CapHive State

| Capability | Status | Notes |
|------------|--------|-------|
| Support Agents framework (`SupportAgent`, `AgentSchedule`) | ✅ Exists | Configurable AI agents with tool access; scheduling; execution logs |
| AI Rules (`AiRule`, `AiCheck`) | ✅ Exists | Automated checks run against records; results logged |
| Document Q&A (`DocQuestion`) | ✅ Exists | AI extraction of question/answer pairs from document content |
| LLM configuration (`EntitySetting`, LLM provider) | ✅ Exists | Claude or other LLM configurable per entity |
| AI Subscription Review workflow | ❌ Missing | No pre-built subscription review agent or rule set |
| Exception routing from AI review to human queue | ❌ Missing | AI checks flag issues; no subscription-specific exception routing |
| Cross-document consistency checks | ❌ Missing | AI rules run per record; no cross-document comparison logic |

---

## Build Approach: New `SupportAgent` type + new `AiRule` category, built on existing AI infrastructure

### New Agent Type: `SubscriptionReviewAgent`

Extend `SupportAgent` with `agent_type = subscription_review`. This agent:
- Is triggered when a `SubscriptionPacket` moves to `status = fully_signed` or `countersigned`
- Receives the list of `SubscriptionPacketDocument` records and their associated documents
- Runs a sequence of review checks (see below)
- Creates `SubscriptionReviewException` records for each finding
- Updates the `SubscriptionPacket` with a review summary

### New Model: `SubscriptionReviewException`

- `subscription_packet_id` FK
- `check_type` — enum: `missing_signature`, `missing_initial`, `name_mismatch`, `tax_form_mismatch`, `incomplete_eligibility`, `beneficial_owner_inconsistency`, `erisa_representation`, `entity_type_mismatch`, `other`
- `severity` — enum: `advisory`, `requires_lp_action`, `requires_legal_review`
- `description` text (human-readable explanation)
- `source_document_id` FK, `source_location` text (page/section reference)
- `ai_confidence` decimal (0–1)
- `status` — enum: `open`, `resolved`, `waived`
- `resolved_by_user_id`, `resolved_at`
- `resolution_notes` text

### Review Check Sequence

The agent runs these checks using a combination of DocQuestion extraction and LLM analysis:

| Check | Method | What It Looks For |
|-------|--------|-------------------|
| Signature completeness | DocQuestion extraction + LLM | All required signature/initial blocks present and filled |
| Name consistency | Cross-document LLM comparison | Investor legal name matches across subscription agreement, questionnaire, and tax form |
| Tax form type match | Rule: `investor.json_fields["us_investor_type"]` vs. submitted tax form type | US person types should have W-9; foreign individual should have W-8BEN; foreign entity should have W-8BEN-E |
| Eligibility answer completeness | DocQuestion extraction | Required fields in eligibility questionnaire are not blank |
| Beneficial owner count | Cross-document comparison | Owner count in questionnaire matches owner count in W-8BEN-E certification |
| ERISA representation | Rule: `investor.json_fields["is_benefit_plan_investor"] = "true"` requires Section X initials | ERISA exhibit signed if investor is flagged as a benefit plan investor (FormCustomField on `Investor`) |
| Entity type consistency | LLM comparison of questionnaire vs. subscription | Stated entity type (LLC, LP, etc.) consistent across documents |
| QP/AI threshold indicators | LLM analysis of stated amounts | Stated investment assets / net worth consistent with claimed eligibility status |

### Review Summary on SubscriptionPacket

After the agent runs, `SubscriptionPacket` is updated with:
- `ai_review_status` — enum: `not_run`, `running`, `passed`, `exceptions_found`, `error`
- `ai_review_exceptions_count` integer
- `ai_review_summary` text (e.g. "4 items found: 2 require LP action, 1 requires legal review, 1 advisory")
- `ai_reviewed_at` timestamp

### Exception Queue UI

Operations team sees a review queue in the Closing Room:
- Sorted by severity (legal review first), then by committed amount
- Each exception: investor name → check type → description → source document + page → suggested action → assign owner → mark resolved

### Guardrails (Critical)

- The AI never approves or rejects an investor — every check is advisory or requires human sign-off
- Every AI finding must cite the specific document and section it is based on; findings without a citation are not surfaced
- `ai_confidence < 0.7` findings are labelled "low confidence" and shown separately; reviewer must decide whether to investigate
- All AI review activity is logged in `AgentExecutionLog` for audit purposes

---

## Functional Requirements

1. Review is triggered automatically when `SubscriptionPacket.status = fully_signed`; can also be triggered manually
2. Review completes within 5 minutes for a standard subscription packet; timeout produces `ai_review_status = error` with fallback to manual review
3. `SubscriptionReviewException.status = open` with `severity = requires_legal_review` prevents the investor from being marked "ready" in the closing room without a reviewed exception approval
4. All exceptions, their resolutions, and AI confidence scores are included in the Compliance Evidence Binder
5. The agent uses the entity's configured LLM provider; no hardcoded model
6. Review results are not visible to the LP — they are an internal compliance tool only

---

## Integration Points

- `us_esign_subscription.md` — triggers on `SubscriptionPacket.status` change
- `closing_room.md` — AI review status and unresolved exceptions surface as a closing checklist dimension
- `compliance_evidence_binder.md` — all `SubscriptionReviewException` records included in evidence binder
- `investor_qualification_engine.md` — eligibility completeness checks from AI review feed back into qualification status
- Existing: `SupportAgent`, `AiRule`, `DocQuestion`, `AgentExecutionLog` models
