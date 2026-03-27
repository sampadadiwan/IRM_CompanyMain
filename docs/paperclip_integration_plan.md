# Paperclip Integration: AI-Powered "Zero-Entry" Back Office for AIFs

This document outlines how to integrate **Paperclip** (paperclip.ing) as an add-on to our SaaS platform to transform it from a manual "System of Record" into an automated "Operating System" for Alternative Investment Funds (AIFs).

## 1. The Value Proposition: From Manual to "Zero-Entry"
Current fund management workflows involve significant manual data entry from unstructured documents (PDFs, spreadsheets, bank notices). By integrating Paperclip, we provide a **"Hands-off" mode** where the system extracts structured data and drafts records for one-click approval.

### Key Benefits
- **Speed:** Reduce manual data entry time by up to 90%.
- **Accuracy:** Eliminate human typos in sensitive financial data (Commitments, Call Amounts, Bank Details).
- **Scale:** Allow fund managers to handle 5x more LPs without increasing back-office headcount.

---

## 2. High-Impact Use Cases

### A. Automated Capital Call & Distribution Ingestion
For Fund-of-Funds or LPs using our platform to track their investments:
- **Workflow:** Forward a GP's Capital Call notice (PDF) to a dedicated platform email.
- **AI Action:** Paperclip extracts `Due Date`, `Call Amount`, `Management Fees`, and `Wire Instructions`.
- **SaaS Action:** Automatically creates a draft in `app/packs/funds/capital_calls` and notifies the user to "Verify & Pay".

### B. Intelligent Investor Onboarding (KYC/AML)
- **Workflow:** Investors upload Subscription Booklets or Tax IDs (W-9/W-8BEN).
- **AI Action:** Paperclip parses the booklet to extract `Commitment Amount`, `Entity Type`, `Tax ID`, and `Signatory Names`.
- **SaaS Action:** Populates `InvestorKyc` and `IndividualKyc`/`NonIndividualKyc` models in `app/packs/core/investor_kycs`.

### C. Automated Bank Reconciliation
- **Workflow:** Upload monthly Bank Statements or Swift MT940 files.
- **AI Action:** Extract remitter names, reference codes, and amounts.
- **SaaS Action:** Match extracted transactions against outstanding `CapitalRemittance` or `CapitalCall` records.

### D. Portfolio Monitoring & FMV Updates
- **Workflow:** GPs upload Quarterly Reports from portfolio companies.
- **AI Action:** Extract P&L metrics (Revenue, EBITDA) and Fair Market Value (FMV).
- **SaaS Action:** Update `app/packs/core/valuations` and trigger `ai/report_insights` to generate fresh analysis.

---

## 3. Technical Integration Architecture

### Proposed New Pack: `app/packs/integrations/paperclip`
We should treat Paperclip as a modular integration to keep the core logic clean.

1.  **Service Layer:**
    - `Paperclip::ExtractData`: Sends documents to the Paperclip API.
    - `Paperclip::MapResponse`: Maps Paperclip's JSON output to our internal Domain Models (e.g., `CapitalCall`, `KycData`).
2.  **Webhook Controller:**
    - Handles asynchronous callbacks from Paperclip once OCR/Extraction is complete.
3.  **UI Components:**
    - A "Side-by-Side" verification ViewComponent showing the source PDF next to the extracted form fields for human-in-the-loop validation.

### Workflow Example: Capital Call Processing
1.  **Trigger:** File uploaded to `Document` model with `category: 'capital_call_notice'`.
2.  **Job:** `PaperclipExtractionJob` is enqueued.
3.  **Extraction:** Job calls Paperclip API with the file URL.
4.  **Callback:** Paperclip sends JSON results to our webhook.
5.  **Drafting:** Our system creates a `CapitalCall` record with `status: 'draft'`.
6.  **Notification:** `Noticed` gem alerts the Fund Manager: *"New Capital Call notice detected. Click to review draft."*

---

## 4. Product Tiers & Monetization

| Feature | Standard (Manual) | AI Add-on (Automated) |
| :--- | :--- | :--- |
| **Data Entry** | Manual form filling | AI-assisted drafting |
| **Document Processing** | File storage only | OCR & Data Extraction |
| **Reconciliation** | Manual matching | Auto-suggested matches |
| **Reporting** | Static dashboards | AI-powered insights on extracted data |

**Pricing Suggestion:** 
- Per-document processing fee (e.g., $1.00 per notice).
- Or a flat "Automated Back Office" monthly subscription.

---

## 5. Implementation Roadmap
1.  **Phase 1:** Prototype "Capital Call" extraction using a single Paperclip schema.
2.  **Phase 2:** Implement the Verification UI (Side-by-side view).
3.  **Phase 3:** Expand to Subscription Booklets and KYC documents.
4.  **Phase 4:** Roll out "Forward-to-App" email integration.
