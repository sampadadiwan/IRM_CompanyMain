# Tax Center — K-1 Delivery & Tax Document Management

**Approach:** Build — no existing K-1 delivery workflow; documents can be uploaded and shared but no tax-year-organized delivery module
**Phase:** P1 — required for investor servicing post-close

---

## What This Is

Tax season is one of the highest-friction periods in a GP's relationship with its LPs. K-1s arrive late, get lost in email, reach the wrong contact, or never reach the LP's CPA. IR teams spend weeks answering "where is my K-1?" questions. LPs with multiple fund investments have to hunt across fund administrator portals, emails, and shared drives.

The Tax Center is a purpose-built module for tax document delivery, CPA/delegate access, and investor tax communication. It does not generate K-1s — that is the fund administrator's job — but it manages the receipt, matching, delivery, and evidence of every tax document for every investor, every year.

---

## Who Uses It

| Persona | When | What They Need |
|---------|------|----------------|
| **Operations / IR Team** | Tax season (Jan–Apr, extension season) | Bulk upload K-1s from fund administrator; match to investors; track delivery and acknowledgment |
| **LP (self) via portal** | Tax season | Find their K-1 and state K-1 in one place; download immediately; delegate access to their CPA |
| **CPA / Tax Delegate** | Tax season | Access client's K-1s directly without the LP having to forward documents |
| **CFO** | Year-end reporting | Know that every investor has received their K-1; track any corrections or reissues |
| **Fund Administrator** | Annual tax package prep | Upload K-1 files in bulk; receive delivery confirmation |

---

## Use Cases

### UC-1: Bulk K-1 Upload and Investor Matching
The fund administrator prepares 200 K-1 PDFs for the year ended December 31. The IR team uploads the zip file to CapHive. The system parses each PDF filename (or embedded EIN/SSN) and matches it to the correct investor record. Unmatched files appear in a review queue for manual assignment. Matched files appear in each investor's Tax Center, ready for delivery.

### UC-2: Investor Accesses Their K-1 via Portal
An LP logs into their portal in late February. The Tax Center shows "Tax Year 2025 — Federal K-1 [Download] ✓" and "State K-1 (California) [Download]." The LP downloads both. The IR team sees the download timestamp in the Tax Center delivery dashboard.

### UC-3: CPA Delegate Access
An LP delegates K-1 access to their CPA: "john@smithtax.com — K-1 access only — expires June 15." The CPA receives an email with a secure link, clicks it, and sees only the LP's K-1 documents for the current tax year — nothing else in the investor portal. The IR team can see when the CPA accessed the documents.

### UC-4: Corrected K-1 Reissue
The fund administrator issues a corrected K-1 for one investor in March (a correction to the partnership income allocation). The IR team uploads the corrected K-1, marks it as a correction, and the system notifies the investor and their CPA delegate. The original and corrected K-1 are both visible in the Tax Center with labels showing which is current.

### UC-5: Tax Estimate Notice Delivery
In Q3, the GP sends a tax estimate notice to investors to help them plan estimated tax payments. The Tax Center supports non-K-1 tax documents: estimates, extension notices, and informational letters. These are uploaded and delivered alongside the K-1s.

### UC-6: LP Asks "Where Is My K-1?"
An investor contacts IR asking about their K-1. The IR team opens the investor's Tax Center: "Federal K-1 — uploaded Feb 14 — downloaded by LP Feb 20 at 2:34pm — also downloaded by CPA John Smith Feb 21." The IR team's answer takes 15 seconds.

---

## Current CapHive State

| Capability | Status | Notes |
|------------|--------|-------|
| Document upload and folder management | ✅ Exists | Documents stored in per-investor folders; access control inherited from folder |
| Document sharing via `DocShare` | ✅ Exists | Secure link sharing with external email addresses |
| Document viewing tracking (`ViewedBy`) | ✅ Exists | Tracks who opened a document and when |
| Investor portal document access | ✅ Exists | LPs can access documents shared in their portal |
| Download and print controls | ✅ Exists | `download = false` can restrict download |
| Expiring document share links | ✅ Exists | `DocShare` records can be time-limited |
| `Document.as_of` date field | ✅ Exists | Date field on `Document`; set on upload or via `import_fund_docs` index; can anchor K-1 to a tax year; indexed for filtering |
| Bulk K-1 upload with investor matching | ⚠️ Partial | `ImportFundDocsService` accepts a ZIP containing documents + `index.xlsx`; index maps each file to a Folio No, Document Type, folder, tags, send_email, and `As Of Date` (→ `document.as_of`); deduplication, case-insensitive file lookup, and nested-directory ZIP support included — gap is auto-matching from EIN/SSN embedded in PDF filenames (current matching requires Folio No to be explicit in the index) |
| K-1 delivery workflow (tax-year-organized) | ⚠️ Partial | No formal `TaxYear` model or tax-center UI; but `document.as_of` serves as the tax-year anchor and `import_fund_docs` can place K-1s in per-investor folders with the correct date — the remaining gap is a UI that groups and surfaces documents by tax year |
| CPA / delegate access with scoped permissions | ⚠️ Partial | `InvestorAdvisor` model provides external advisor access at fund level (via `AccessRight`) and folio level (via `InvestorAccess` + `AddFolioInvestorAdvisor`); advisor logs in, switches entity context, and sees only the data they have been granted; `allowed_roles` controls their permissions — gap is scoping access to tax documents only (current system grants role-level access, not document-category-level) |
| Corrected K-1 with version tracking | ⚠️ Partial | Documents can be re-uploaded; no "corrected" flag or correction notification workflow |
| Tax document delivery dashboard for IR team | ❌ Missing | No aggregate view showing K-1 delivery status across all investors |
| Tax estimate / extension notice as distinct document type | ❌ Missing | Documents have `tag_list` and `owner_tag` but no tax-document-specific type enum |

---

## Build Approach: New pack `funds/tax_center`

### New Models

**`TaxYear`** (belongs to Fund/Entity)
- `fund_id` FK
- `year` integer (e.g. 2025)
- `filing_deadline` date
- `extension_deadline` date (if applicable)
- `status` — enum: `preparing`, `delivered`, `closed`

**`TaxDocument`** (belongs to TaxYear + Investor)
- `tax_year_id`, `investor_id` FKs
- `document_type` — enum: `federal_k1`, `state_k1`, `form_1042s`, `tax_estimate`, `extension_notice`, `informational_letter`
- `state_code` string (for `state_k1` type; e.g. "CA", "NY")
- `document_id` FK (link to `Document` record; `document.as_of` carries the tax-year date)
- `is_correction` boolean, default false
- `corrects_tax_document_id` FK (self-referential; for corrected K-1s)
- `delivery_status` — enum: `uploaded`, `available`, `downloaded_by_investor`, `downloaded_by_delegate`
- `uploaded_at`, `first_downloaded_at`, `last_downloaded_at`
- `delivered_via` — enum: `portal`, `email_link`, `manual`

**`TaxDeliveryRun`** (belongs to TaxYear)
- `tax_year_id` FK
- `total_investors` integer
- `documents_uploaded` integer
- `documents_matched` integer
- `documents_unmatched` integer
- `status` — enum: `processing`, `review_required`, `complete`
- `unmatched_filenames` jsonb (files that could not be auto-matched)

> **`TaxDelegate` model is NOT needed** — CPA/advisor access uses the existing `InvestorAdvisor` model with `AddFolioInvestorAdvisor`, which already handles folio-scoped external user access, role assignment, invite emails, and `ViewedBy` tracking. See CPA delegate section below.

### Bulk Upload and Matching Logic — Build on `import_fund_docs`

The existing `ImportFundDocsService` already handles the ZIP + `index.xlsx` pipeline (`funds/capital_commitments/services/import_fund_docs_service.rb`). For K-1 delivery, extend `ImportFundDocs` or create a thin `ImportTaxDocs` subclass that:

```
IR team uploads ZIP of K-1 PDFs + index.xlsx
        │
        ▼
ImportFundDocsService unpacks ZIP, reads index.xlsx
        │
Per row in index:
  - Folio No → resolve CapitalCommitment
  - As Of Date → set document.as_of (tax year anchor)
  - Folder → place in investor's tax documents folder
  - Tags → tag as "K-1", "2025" etc.
  - Send Email → notify LP on upload
        │
        ├── Folio match found → create Document; queue for LP portal delivery
        └── No match → land in review queue for manual assignment
```

**Optional enhancement:** If `Folio No` is blank but `File Name` matches pattern `{ein_last4}_K1_2025.pdf`, attempt EIN/SSN match against `encrypted_tin` on `InvestorKyc`. This extends the existing `import_fund_docs` row processor with one additional match path — no new model needed.

### CPA / Advisor Delegate Access — Build on `InvestorAdvisor`

The `InvestorAdvisor` model and `AddFolioInvestorAdvisor` service already implement the external advisor access pattern. For the Tax Center CPA delegate use case:

- Use `AddFolioInvestorAdvisor` to grant the CPA `InvestorAccess` on the investor's folio — this gives them fund-level `AccessRight` + folio-level `InvestorAccess`
- The CPA receives an invite email (existing `investor_advisor_mailer`), logs in, and switches entity context
- What still needs to be built: a narrower portal scope for tax-doc-only access. Options:
  1. Add an `access_scope` field to `InvestorAdvisor` (`full`, `tax_documents_only`) and conditionally restrict the portal nav — small, clean
  2. Use the existing `tag_list` on documents + a document-level policy rule scoped to `investor_advisor` users with `tax_documents_only` scope

The `TaxDelegate` model proposed in the original build approach is **not needed** — this is `InvestorAdvisor` with a narrower scope. Every delegate document access already creates a `ViewedBy` record attributed to the delegate's user.

### Tax Center UI (GP-Facing Dashboard)

- Per tax year: delivery progress bar (N/total investors have downloaded their K-1)
- Table: investor name, federal K-1 status, state K-1 status, last download date, CPA delegate status
- Click row → investor detail: all tax documents for this investor across all years, download log, delegate list
- Correction workflow: "Upload corrected K-1" button on any TaxDocument; creates `is_correction = true` record and auto-notifies investor and delegates

### Tax Center UI (LP-Facing Portal Tab)

```
Tax Center
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Tax Year 2025
  Federal K-1 ─────────────── [Download] ✓ Opened Feb 20
  State K-1 (California) ──── [Download] ✓ Opened Feb 22
  Tax Estimate (Q3 2025) ───── [Download] ✓ Opened Nov 1

CPA / Delegate Access
  John Smith CPA — active — expires Jun 15 — [Manage]

Tax Year 2024
  Federal K-1 ─────────────── [Download] ✓
  State K-1 (California) ──── [Download] ✓
  Corrected K-1 (Mar 15) ───── [Download] ✓ (replaces original)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Functional Requirements

1. Bulk upload processes files asynchronously in a background job via `ImportFundDocsService`; IR team sees a live progress indicator via the existing import upload status UI
2. Matching uses Folio No from the index as the primary key; an optional EIN/SSN filename-pattern match is a secondary path; files without a match land in a review queue for manual assignment
3. `document.as_of` is set from the "As Of Date" column in the index and serves as the tax-year anchor for all K-1 documents
4. `is_correction = true` documents notify the investor and all active `InvestorAdvisor` delegates automatically on upload
5. CPA delegate access uses `InvestorAdvisor` + `AddFolioInvestorAdvisor`; access scope (`full` vs. `tax_documents_only`) enforced via an `access_scope` field on `InvestorAdvisor` and a portal nav guard
6. All document downloads (investor or delegate) are logged with timestamp and identity via `ViewedBy`
7. K-1 delivery status is surfaced in the GP-facing dashboard and is available as a filter/export
8. `TaxYear.status = closed` prevents further document uploads to that year; can be reopened by admin

---

## Integration Points

- `us_tax_forms.md` — W-8/FATCA classification determines whether 1042-S is required (foreign investors)
- `fund_admin_exchange.md` — K-1 files are received from fund administrator; delivery confirmation exported back
- `compliance_evidence_binder.md` — K-1 delivery records (what was sent, when, by whom) included in investor evidence binder
- Existing: `Document`, `Folder`, `ViewedBy`, `DocShare` models — Tax Center is built on top of these
- Existing: `ImportFundDocsService` / `ImportFundDocs` (`funds/capital_commitments/services/`) — bulk ZIP upload pipeline; Tax Center extends this rather than building its own importer
- Existing: `InvestorAdvisor`, `InvestorAccess`, `AddFolioInvestorAdvisor` (`core/investors/`) — CPA delegate access uses this model rather than a new `TaxDelegate` model
- Existing: `Document.as_of` — tax-year date anchor; already set by `import_fund_docs` index "As Of Date" column
