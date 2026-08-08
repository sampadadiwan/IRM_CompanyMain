# AI Document Intelligence — LPA & Side Letter Extraction

**Approach:** Build — new AI feature; extends existing `DocQuestion`, `SupportAgent`, and `Chat` infrastructure
**Phase:** P2 — builds on `side_letter_obligations.md` (P1); requires document corpus to be meaningful

> **Scope note (2026-08):** Side letter obligation extraction has moved into P1 and is delivered by the
> `SideLetterObligationAgent` — see `side_letter_obligations.md`. This document now covers LPA term-sheet
> extraction and the fund-document chat only; its side-letter use cases are retained for context.

---

## What This Is

Private fund documents — LPAs, PPMs, side letters, management agreements — contain the rules that govern every fund action. They are 100–200 page PDFs reviewed at closing and then largely inaccessible in daily operations. When a question arises ("What is the notice period for a key person change?", "Does LP Gamma have a right of first offer on this deal?"), the answer requires a lawyer to find it.

AI Document Intelligence makes fund documents queryable. It extracts structured term data from LPAs and side letters, answers natural language questions from fund staff, and populates obligation matrices with extracted clauses. Every AI answer cites the exact document section — so users can verify, not just trust.

This feature extends CapHive's existing `DocQuestion` (document Q&A extraction) and `Chat` (conversational AI) infrastructure with fund-document-specific extraction models and a term sheet output.

---

## Who Uses It

| Persona | When | What They Need |
|---------|------|----------------|
| **General Counsel / Legal Team** | LPA/side letter review, obligation setup | Extract structured terms from documents for legal review; populate the LP Obligation Matrix |
| **CFO / Finance** | Fee calculation, distribution waterfall | Get source-cited answers to fee structure and waterfall questions without re-reading the LPA |
| **IR Director** | LP communications | Answer investor questions about fund terms accurately and quickly |
| **COO** | Fund operations setup | Understand the LPA's operational requirements (notice periods, capital call rules, transfer restrictions) |
| **Deal Team** | New investment preparation | Check co-investment rights and excuse rights for relevant LPs before deal close |

---

## Use Cases

### UC-1: LPA Term Sheet Extraction
Counsel uploads the LPA for Fund III. CapHive's extraction agent processes the document and populates a structured term sheet:
- Management fee: 2.0% during commitment period; 1.5% post-investment period
- Preferred return: 8% compounded annually on contributed capital
- Carry: 20% after return of capital and preferred return; 50/50 GP catch-up to 20%
- Capital call notice: 10 business days minimum; 3 business days for emergency
- Transfer restriction: GP consent required; affiliates excepted
- Key person: departure of 2+ key persons within 24 months triggers suspension

Every extracted term cites the LPA section it came from.

### UC-2: Side Letter Obligation Extraction
After a closing, 15 side letters are uploaded. The AI extraction agent processes each one and creates draft `SideLetterObligation` records in the LP Obligation Matrix. Counsel reviews the draft matrix, approves 42 obligations, corrects 3 AI misclassifications, and adds 2 that the AI missed. Total counsel review time: 3 hours vs. 2 weeks manual entry.

### UC-3: Natural Language Fund Document Query
The CFO asks the fund document chat: "What is the maximum percentage we can call in a single capital call?" The system searches across the LPA and any amendments, finds "Section 6.3(b): No single capital call shall exceed 25% of an investor's total commitment except in the event of an emergency expense as defined in Section 1," and returns the answer with the exact quote and section reference.

### UC-4: Co-Investment Right Check Before Deal Close
The deal team is closing a $20M investment. Before signing the term sheet, they ask: "Which LPs have co-investment rights that we need to notify for this deal?" The system checks all side letters with active co-investment obligations and returns: "LP Gamma — co-invest right on deals > $15M — notify 7 business days before deal close (Section 4.2 of LP Gamma side letter)."

### UC-5: MFN Obligation Comparison
After extracting all side letter obligations, counsel asks: "Show me all reporting obligations that are more favorable than the standard LPA reporting clause." The AI compares extracted reporting obligations across all side letters against the LPA baseline and surfaces 3 that appear more favorable, flagging them for MFN review.

---

## Current CapHive State

| Capability | Status | Notes |
|------------|--------|-------|
| `DocQuestion` — AI Q&A extraction from documents | ✅ Exists | AI extracts question/answer pairs from document content; used in support agents |
| `Chat` — conversational AI within the platform | ✅ Exists | AI chat sessions scoped to entity data |
| `SupportAgent` — configurable AI agents | ✅ Exists | Agents with tool access; can read documents, KYC, fund data |
| LLM configuration per entity | ✅ Exists | Claude and other models configurable |
| LPA term extraction | ❌ Missing | No structured extraction of fund terms into a term sheet model |
| Side letter obligation extraction → LP Obligation Matrix | ➡️ Moved | Delivered in P1 by `SideLetterObligationAgent` (`side_letter_obligations.md`) |
| Fund document natural language query with citations | ❌ Missing | Chat exists but without fund-document-specific grounding or citation enforcement |
| Cross-document comparison (side letter vs. LPA baseline) | ❌ Missing | No cross-document comparison logic |
| MFN analysis from extracted obligations | ❌ Missing | To be added as part of this feature |

---

## Build Approach: New extraction models + enhance `Chat` and `SupportAgent` for fund document scope

### New Models

**`FundDocumentSet`** (belongs to Fund)
- `fund_id` FK
- Groups the fund's key documents for AI use: LPA, PPM, management agreement, amendments, side letters
- `lpa_document_id`, `ppm_document_id`, `management_agreement_document_id` FKs (optional)
- `indexed_at` timestamp (when the document set was last processed for AI)

**`FundTermSheet`** (belongs to FundDocumentSet)
- Structured extracted terms from the LPA; each field is a text value + source citation

| Field | Example Value | Source Citation |
|-------|--------------|----------------|
| `management_fee_commitment_period` | "2.0% of committed capital" | LPA Section 7.1(a) |
| `management_fee_post_investment` | "1.5% of invested capital" | LPA Section 7.1(b) |
| `preferred_return_rate` | "8% per annum, compounded" | LPA Section 8.2(b) |
| `carry_rate` | "20%" | LPA Section 8.2(c) |
| `gp_catchup` | "50/50 until GP receives 20% of total profits" | LPA Section 8.2(c) |
| `capital_call_notice_days` | "10 business days; 3 for emergency" | LPA Section 6.3 |
| `capital_call_max_single` | "25% of commitment per call" | LPA Section 6.3(b) |
| `transfer_restriction` | "GP consent required; affiliates excepted" | LPA Section 11.2 |
| `key_person_trigger` | "Departure of 2+ key persons within 24 months" | LPA Section 5.4 |
| `key_person_effect` | "Suspension of new investment activity" | LPA Section 5.4 |
| `recycling_permitted` | "Yes, up to 10% of commitments" | LPA Section 6.5 |
| `excuse_rights` | "LPs may be excused from investments that conflict with their investment mandate" | LPA Section 9.3 |

- All fields `null` if not found; AI confidence stored alongside each field
- `reviewed_by_user_id`, `reviewed_at` (counsel reviews and approves)

**`SideLetterExtractionRun`** (belongs to SideLetter)
- `side_letter_id` FK
- `status` — enum: `pending`, `running`, `complete`, `error`
- `obligations_extracted_count` integer
- `obligations_approved_count` integer
- `completed_at` timestamp

### Extraction Pipeline

```
Document uploaded (LPA or side letter)
        │
FundDocumentSet updated
        │
Background job: ExtractionAgent runs
        │
For LPA:
  → Structured extraction into FundTermSheet
  → Each field: extracted value + source section
  → Low-confidence fields flagged for counsel review

For side letter:
  → Handled by SideLetterObligationAgent (see side_letter_obligations.md) —
    extraction, counsel review gate, task projection, and due-date enforcement
    all live in that feature
```

### Fund Document Chat

Extend `Chat` with a `chat_scope = fund_documents` mode:

- User selects "Ask Fund Documents" from the fund page
- Chat session is grounded on the `FundDocumentSet` for that fund
- Every response must cite the source document and section; if the AI cannot find a source, it says so
- Chat logs are retained as `AiChatSession` records for audit purposes
- Chat is available to GP employees only; not to LPs (LP-facing service assistant is separate)

**Tool available to the fund document chat agent:**
- `search_fund_document(fund_id, query)` — searches indexed document content and returns relevant passages with location
- `get_term_sheet(fund_id)` — returns the structured FundTermSheet for quick reference
- `list_obligations_for_investor(investor_id, obligation_type)` — queries LP Obligation Matrix

### Citation Enforcement

Every AI answer must include `[Source: {document_name}, Section {X.Y}]`. If the AI cannot find a supporting section with sufficient confidence, it responds: "I could not find a definitive answer to this in the uploaded fund documents. Please review [document name] manually or consult counsel."

---

## Functional Requirements

1. LPA term extraction runs automatically when an LPA document is added to the `FundDocumentSet`; results are draft until reviewed by counsel
2. Side letter extraction creates `SideLetterObligation` records with `status = ai_extracted`; these do not appear as active obligations until counsel approves them
3. Every AI-extracted term and obligation retains its source citation; terms without citations are not surfaced
4. `FundTermSheet` fields with `ai_confidence < 0.75` are flagged for mandatory counsel review before the term is considered confirmed
5. Fund document chat sessions are logged; all queries and responses are auditable
6. Cross-document MFN comparison is presented as a suggested review list — not an automatic determination
7. Re-running extraction on a revised document creates a new `SideLetterExtractionRun`; existing approved obligations are not overwritten automatically — counsel reviews the delta

---

## Integration Points

- `side_letter_obligations.md` — obligation extraction is delivered there (P1) by `SideLetterObligationAgent`; this feature's cross-document tools query the resulting `SideLetterObligation` records
- `investor_qualification_engine.md` — extracted eligibility terms from LPA feed into fund rule configuration
- `capital_events_us.md` — extracted capital call rules (notice period, max call percentage) can pre-populate fund settings
- `compliance_evidence_binder.md` — `FundTermSheet` included as a fund-level compliance reference
- Existing: `DocQuestion`, `SupportAgent`, `Chat`, `Document` models
