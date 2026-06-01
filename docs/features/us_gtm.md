# CapHive US Launch Roadmap

## Making CapHive Native to the US Private Funds Ecosystem

**Audience:** CapHive founders, product leadership, engineering, sales, partnerships, compliance, and implementation teams
**Goal:** Define a practical, phased roadmap for launching CapHive in the United States as a credible, US-native platform for private fund onboarding, fund operations, investor servicing, compliance evidence, and AI-powered document intelligence.

---

# At a Glance

| What | Detail |
|------|--------|
| **Market** | ~25,000 registered US investment advisers; private capital AUM exceeds $12T; operational software spend is a multi-billion dollar underserved category |
| **Our wedge** | AI-native workflow layer that handles the complexity, speed, and auditability demands of mid-to-large GPs — not a replacement for incumbents, but a layer incumbents cannot build |
| **Phase 1 ICP** | Technically sophisticated GPs, $500M–$10B AUM, 3–10 active fund vehicles, 150–800 LPs, significant workflow complexity and desire to reduce operational cost and error |
| **Year 1 goal** | 3–5 lighthouse accounts at $100K–$250K ARR each; CapHive is the operating layer for a full fund lifecycle at a complex firm |
| **Year 2 goal** | 15–25 accounts; AI differentiation live and defensible; first fund administrator partnership generating inbound leads |

### The Four Phases

| Phase | Theme | Horizon | Value Delivered |
|-------|-------|---------|-----------------|
| **1** | US-native foundation | Months 1–3 | "We can onboard US LPs properly." |
| **2** | Operational depth | Months 4–12 | "We coordinate GP, admin, counsel, tax, and LP workflows." |
| **3** | AI differentiation | Year 2 | "We reduce manual review, exception handling, and document reading." |
| **4** | Ecosystem platform | Year 2–3 | "CapHive is embedded in the US private funds operating stack." |

### Feature Specifications

Each capability required for the US GTM has a detailed feature spec in [`docs/features/us_gtm/`](us_gtm/). Each file documents: use cases, user personas, current CapHive state (✅ exists / ⚠️ partial / ❌ missing), build approach, model changes, and integration points.

| Feature | Approach | Phase | Description |
|---------|----------|-------|-------------|
| [US Fund Legal Structure](us_gtm/us_fund_legal_structure.md) | Enhance | P0 | `legal_structure`, `vehicle_type`, `fund_exemption_type`, `strategy`, `vintage_year` as FormCustomField on `Fund` (which includes `WithCustomField`) — Entity model unchanged; no new FK columns needed: feeder→master is already modelled via `Fund.master_fund_id` / `has_many :feeder_funds`, and feeder fund commitments via `CapitalCommitment.feeder_fund_id` |
| [US Investor Taxonomy](us_gtm/us_investor_taxonomy.md) | Enhance | P0 | US investor types via existing `Investor.category` (configurable per entity) + seed 9 US-tagged KYC form type templates using FormCustomField — joint holders use `esign_emails`, IRA/trust fields are plain custom fields, ERISA flag is a CheckBox; only model change is the shared `encrypted_tin` column |
| [Investor Qualification Engine](us_gtm/investor_qualification_engine.md) | Enhance | P0 | Questionnaire as `US_QUALIFICATION` FormType on `InvestorKyc`; eligibility status fields (AI/QP/QC) as FormCustomField on `Investor`; fund config as FormCustomField on `Fund` — only `InvestorQualification` (evidence record) and `BeneficialOwnerCount` (3(c)(1) counter) are new models |
| [US Tax Forms — W-9 / W-8 / FATCA](us_gtm/us_tax_forms.md) | Enhance | P0 | W-9/W-8/FATCA collection using existing `FormCustomField` on `IndividualKyc`/`NonIndividualKyc` — seed 5 US-tagged form type templates with conditional fields and File upload; add form type routing logic (~50 lines), encrypted TIN column, and expiry alert job; ~1 week vs. building a new module |
| [Bank Instruction Controls](us_gtm/bank_instruction_controls.md) | Build + Integrate | P0 | Payment instructions lifecycle with Plaid bank verification, fraud hold rules, dual approval on changes, pre-distribution fraud check, and full audit trail — prevents distribution fraud |
| [US KYC / KYB](us_gtm/us_kyc_kyb.md) | Enhance + Integrate | P0 | Extends existing KYC module with US identity verification (Persona), entity verification (Middesk), and sanctions/PEP/adverse media screening (ComplyAdvantage); adds structured check result model and exception workflow |
| [US E-Sign & Subscription Packets](us_gtm/us_esign_subscription.md) | Enhance | P0 | DocuSign is already fully integrated (JWT auth, envelope creation, webhook handling, completion download); `EsignHelper` provider adapter pattern already exists — US work is: Subscription Packet Engine (document determination per investor type, pre-fill, LP-then-GP ordering), counsel template versioning, and optionally a Dropbox Sign adapter |
| [Closing Room](us_gtm/closing_room.md) | Enhance | P1 | Extends `KycOnboardingAgent` with US-specific check steps (tax form, subscription e-sign, qualification) and enhances the existing Onboarding Report with a summary bar, Admit action, and closing binder generation — verified KYC already implies bank details confirmed; no new model hierarchy needed |
| [Capital Events — US Enhancements](us_gtm/capital_events_us.md) | Enhance | P1 | Adds unfunded commitment as a tracked field, dual/maker-checker approval, `FundBankAccount` object for wire instruction auto-population, fraud warning enforcement, recallable distribution tracking, default interest calculation, and structured fund admin reconciliation export |
| [Tax Center — K-1 Delivery](us_gtm/tax_center.md) | Enhance | P1 | Bulk K-1 upload extends existing `ImportFundDocsService` (ZIP + index.xlsx, Folio No matching, `as_of` date); CPA/advisor access builds on existing `InvestorAdvisor` model; new: `TaxYear`/`TaxDocument` models, tax-year-organised UI, corrected K-1 workflow, and delivery dashboard |
| [Fund Admin Exchange](us_gtm/fund_admin_exchange.md) | Enhance | P1 | XLSX import (`ImportUpload`/`rubyXL`) and export (`ReportBuilder`/`caxlsx`) already exist; API already exists; new: `FundAdminProfile` (per-admin config + format presets), `FundAdminExchangeRun` (audit log), and pre-defined exchange schemas for investor master, capital call reconciliation, and closing data — SFTP not planned |
| [Side Letter & LP Obligation Matrix](us_gtm/side_letter_obligations.md) | Build | P1/P2 | Side letter upload and structured obligation tracking — obligation type, owner, trigger, due date, and fulfillment evidence; MFN review workflow; Phase 2 adds AI extraction via `ai_document_intelligence.md` |
| [Compliance Evidence Binder](us_gtm/compliance_evidence_binder.md) | Build | P1/P2 | Per-investor compliance snapshot aggregating KYC, AML, tax form, bank verification, qualification, and subscription status into a single view; exportable PDF/ZIP package for auditors, LPs, and SEC examiners |
| [AI Subscription Review](us_gtm/ai_subscription_review.md) | Build | P2 | Automated review of completed subscription packets using existing SupportAgent infrastructure — detects missing signatures, name mismatches, tax form errors, incomplete eligibility answers, and ERISA representation gaps; every finding cites the source document |
| [AI Document Intelligence](us_gtm/ai_document_intelligence.md) | Build | P2 | LPA term sheet extraction (fee structure, waterfall, capital call rules, key person provisions) and side letter obligation extraction into the LP Obligation Matrix; fund document chat with mandatory source citations |
| [Private Credit Fund Operations](us_gtm/private_credit_funds.md) | Build | P1/P2 | Loan-level tracking (`LoanFacility`, interest accrual, PIK, OID), covenant monitoring and breach alerting, loan fair value / NAV computation, subscription credit facility tracking, and credit-specific LP quarterly reports (yield, WAS, WAM, default rate, leverage ratio) — supports direct lending, asset-backed finance, infrastructure debt, and CRE credit strategies |
| [Evergreen Fund Structures](us_gtm/evergreen_fund_structures.md) | Build | P2 | NAV-per-unit pricing engine, rolling subscription processing and unit issuance, redemption queue with gate enforcement, monthly fund NAV computation with approval workflow, management fee on trailing NAV, and vintage/series sub-allocation — addresses the doubling of evergreen private credit funds (141 in 2020 → 318 in 2025) |
| [Continuation Funds & Fee Alignment](us_gtm/continuation_fund_fee_alignment.md) | Build | P2 | Continuation vehicle creation with source fund link, LP election workflow (cash out vs. roll), carry crystallization at independent transfer valuation, dual reporting for exiting and rolling LPs, tiered management fee step-downs, and performance hurdle configuration with index-linked rates and catch-up — serves the record 64 GPs closing first continuation funds in 2024 |

---

# 1. The Opportunity

## 1.1 Why the US Private Funds Market Now

The US private funds market is the largest in the world — but operationally, it runs on tools designed for a different era.

**The scale:**
- Over 25,000 SEC-registered investment advisers
- Private equity and venture AUM exceeding $12T
- Thousands of fund launches per year, driven by an emerging manager wave
- Institutional LPs spreading capital across more managers than ever before

**The operational gap:**
Most fund managers — from a $100M emerging VC to a $3B PE firm — share the same operational problem: their investor workflows are stitched together from DocuSign, email, Excel, PDFs, shared drives, and whoever picks up the phone. The tools exist. The workflow does not.

**Why now is the right moment:**

1. **LP expectations have risen.** Institutional LPs now require digital onboarding, portal access, secure document delivery, and audit-ready evidence. This used to be optional. It no longer is.
2. **Regulatory scrutiny has increased.** The SEC's 2023 Private Fund Advisers rules, enhanced Form PF reporting, and the new cybersecurity rule create real operational and compliance obligations that small back-office teams cannot manage manually.
3. **AI is now viable.** Document extraction, subscription review, LPA analysis, and investor servicing are genuinely automatable with today's AI. Two years ago this was experimental. Today it is production-grade.
4. **Fund administrators need help scaling.** Fund admins are handling more clients without proportionally growing headcount. They need a technology layer, not more staff.
5. **The emerging manager wave.** More first-time and second-time fund managers launch each year than ever before. They need institutional-grade operations without institutional-grade back-office spend.

## 1.2 The Problem We Solve

A $1B GP managing three fund vehicles, 300 LPs, and a growing portfolio of 20 companies has, at any given moment, capital calls to issue, KYC records to maintain, distribution calculations to verify, K-1s to deliver, side letter obligations to track, portfolio company KPIs to collect, LP performance reports to draft, and secondary transfer requests to process. All of this operational work is real, expensive, and error-prone — and none of it is well-served by the software most firms currently use.

The problem is not that software doesn't exist. It is that the software is **fragmented by function**, **disconnected from the underlying data**, and **built before AI could help**.

Here is what that looks like in practice across the seven operational areas that consume the most time:

---

### 1. Capital Events: Error Risk in Every Calculation

When a GP issues a capital call or distribution, the per-investor amounts must account for committed amounts, called-to-date, fund close percentages (equalization for late-admitted investors), multi-currency folios, and any fee adjustments. This is routinely done in Excel — or handed to a fund administrator who also does it in Excel.

The error rate is not zero. A single formula error on a capital call to 200 investors creates downstream corrections, re-issuances, LP complaints, and reconciliation work. Distributions are worse: net payable must account for carry allocations, account entry adjustments, and currency conversions across investor classes.

**What CapHive solves:** Capital calls and distributions are computed directly from the commitment data already in the system — pro-rata amounts, close percentage equalization, multi-currency folios, and fee adjustments all applied automatically. An approval workflow requires sign-off before notices are sent. Every remittance and payment is tracked to completion, with reconciliation exports for the fund administrator.

---

### 2. KYC and Compliance: A Manual Process With No Memory

At a $1B+ fund, KYC is not a one-time event. Investor KYC must be maintained, re-verified at defined intervals, and documented for AML purposes. Entity investors require different form types than individuals. Jurisdiction-specific requirements (SEBI, GIFT, FATCA) add further variation. Bank accounts must be verified. AML screenings must be logged. KYC records expire.

Most firms manage this through a combination of email threads, shared folders, and a compliance associate who knows where everything is. When that person leaves, the institutional knowledge goes with them.

**What CapHive solves:** KYC workflows for both individuals and entities, with jurisdiction-specific form types, document checklists, PAN and bank account verification, AML report generation, KYC expiry tracking with alerts, and investor self-completion via secure portal links. Every verification step is logged, reviewable, and exportable as audit evidence.

---

### 3. Documents and E-Signing: Scattered, Untracked, Uncontrolled

Subscription agreements, KYC documents, capital call notices, distribution letters, side letters, K-1s, quarterly reports — a $1B fund generates hundreds of documents per year across dozens of investors. These documents live in DocuSign, in a shared drive, in email attachments, and sometimes in the fund administrator's proprietary system. Access is ad hoc. Whether an LP actually opened and read a document is unknown.

**What CapHive solves:** A hierarchical document management system scoped to each fund and investor, with access control that propagates through folder inheritance. E-signing is integrated — documents are sent for signature from within CapHive, signing order is configurable, and the completed signed package is stored automatically in the investor's record. Document viewing is tracked: GPs know exactly which LPs have opened which documents, and when.

---

### 4. Portfolio Tracking and Performance Metrics: Still in Spreadsheets

Tracking portfolio company investments — buy transactions, sale transactions, FMV updates, FIFO attribution, realised and unrealised gains — is one of the most data-intensive ongoing workflows in a fund. Most firms do this in Excel. The result: version conflicts, stale valuations, and performance metrics (TVPI, DPI, RVPI, XIRR, MOIC) recomputed manually each quarter and often inconsistent between what the GP shows internally and what is reported to LPs.

**What CapHive solves:** Portfolio investments are tracked as structured records — buy/sell transactions with instrument-level detail, FIFO and weighted-average cost attribution, valuation history that drives FMV forward in time, and performance ratios (TVPI, DPI, RVPI, XIRR, MOIC, PIC, estimated carry) computed automatically at both fund level and individual investor folio level. Cross-fund ratio runs, scenario modelling with synthetic valuations, and a Value Bridge to decompose performance drivers by period are all available without touching a spreadsheet.

---

### 5. KPI Collection: Chasing Portfolio Companies by Email

Collecting quarterly KPIs from 15–25 portfolio companies is a recurring coordination problem. Someone sends a spreadsheet template, follows up three times, receives formats that don't match, manually consolidates the data, gets it approved, and then re-publishes it to dashboards and LP reports — quarterly, every quarter, forever.

**What CapHive solves:** Portfolio companies submit KPIs directly through a structured workbook upload workflow with client-side validation (rejecting malformed files before submission). Staged data is reviewed and approved by the fund team before it appears in dashboards or reports. Automated calculations (quarterly, YTD, annual aggregates) run on approval. KPI dashboards reflect only approved data, removing the "which version is current?" problem entirely.

---

### 6. LP Reporting: High Effort, Low Leverage

Quarterly LP reports are among the highest-effort, lowest-leverage activities in a fund operations team. A typical quarterly report requires pulling performance data, retrieving portfolio company KPIs, writing section narratives, formatting the document, and routing it for approval — before it can be delivered to 200+ LPs. At most firms, this consumes two weeks of work by a 2–3 person team.

**What CapHive solves:** AI-generated portfolio company reports pull KPI data and write section narratives (SWOT, competition, financial highlights, growth outlook) using the fund's approved LLM. Drafts are editable section by section, can be regenerated individually, and export to Word. The Report Builder provides a self-service tool for creating any cross-table data export — investor lists, commitment summaries, capital activity, KPI trends — without writing code or building pivot tables. Reports can be scheduled for auto-generation and published to the investor portal.

---

### 7. LP Experience: A Portal That Earns Trust

Institutional LPs increasingly evaluate a fund's operational quality as a signal of overall quality. An LP who has to email the IR team to find out their unfunded commitment, or who receives their K-1 via a generic file-sharing link, forms a view of the GP's operational capability.

**What CapHive solves:** A purpose-built investor portal where LPs access their documents, capital activity, fund performance metrics, and tax packages — scoped precisely to what each LP is authorized to see, with inheritance-based access control. An AI investor service assistant answers common LP questions (unfunded commitment, distribution history, document status, capital call details) directly from their authorized data, without involving the IR team. Document access is tracked: GPs know what LPs have read and when.

---

### The Aggregate Cost

These seven problems are not isolated. They compound. A capital call that takes two weeks instead of two days delays everything downstream. A KYC process that relies on one compliance associate creates a single point of failure. A portfolio report that takes two weeks to produce means LPs receive it six weeks after quarter-end.

For a $500M–$10B GP managing multiple fund vehicles, the cumulative operational cost is significant:

| Problem Area | Typical Manual Cost | Risk If Wrong |
|---|---|---|
| Capital call calculation | 3–5 days per call, per fund admin | Wrong amounts to 200+ investors; reissuance |
| KYC maintenance | 1–2 FTE continuously | Compliance gap found by auditor or SEC |
| Document tracking | 4–8 hours per LP query | LP frustration; document not provably delivered |
| Portfolio metrics | 5–10 days per quarter | Inconsistent performance reporting to LPs |
| KPI collection | 2–3 weeks per quarter | Late LP reports; stale dashboards |
| LP reporting | 8–15 days per quarter | Reports published 6+ weeks after quarter-end |
| LP servicing | IR team answers same 10 questions per capital event | IR bandwidth consumed by reactive queries |

**CapHive replaces the manual work across all seven.** The operations team moves from executing repetitive workflows to reviewing, approving, and acting on exceptions that genuinely require judgment.

## 1.3 Our Strategic Position

CapHive should not enter the US market as "fund administration software." That places it directly against deeply embedded incumbents with decade-long client relationships and migration lock-in.

Instead, CapHive enters as:

> **CapHive is the full operating stack for private fund workflows: a purpose-built System of Record with fine-grained access control, a deep computation engine covering Fund Ratios, cash flows, and fund formulas, structured workflows for capital calls, distributions, and document e-signing — all unified by an AI agent layer that automates what used to be manual coordination.**

This position is stronger for three reasons:
1. It works *with* existing fund administrators rather than replacing them — removing the biggest objection in a first sales call
2. It targets the pain that existing systems do not solve: workflow coordination, document intelligence, and evidence creation
3. AI is the moat — incumbents have legacy architecture and cannot retrofit AI-native workflows without a full rebuild

---

# 2. Who We Sell To First

## 2.1 Ideal Customer Profile (ICP)

Progressive disclosure: Start here to understand who to target, then move to personas for depth.

**Primary ICP: The Technically Sophisticated Mid-to-Large GP**

| Dimension | Target |
|-----------|--------|
| AUM | $500M–$10B |
| Strategy | PE, growth equity, credit, real assets, multi-strategy VC |
| Fund count | 3–10 active vehicles (including parallel funds, co-invest vehicles, SPVs) |
| LP count | 150–800 investors across vehicles |
| Back office | 8–30 person operations, finance, and IR team |
| Tech posture | Already uses SaaS tools; views technology as a competitive advantage, not a cost center |
| Existing tech | Salesforce or DealCloud, fund admin (Allvue/FundCount/FIS), data room, DocuSign, maybe Juniper Square or Dynamo |
| Pain | Operational complexity is not matched by their current tooling; high error rate in manual processes; side letter obligations managed in spreadsheets; LP servicing requires too many people; compliance evidence assembled manually for auditors |
| What they want | Speed, accuracy, auditability — and a platform that can handle complexity without requiring them to simplify their fund structure to fit the software |
| Budget signal | $100K–$300K/year for a platform that demonstrably reduces operational cost and risk |

**Why this ICP?** These buyers already believe technology can solve operational problems — they do not need to be convinced that software is better than email. The sales conversation skips the first 30 minutes of "why do you need this" and goes directly to "here is what CapHive does that your current stack cannot." They have budget, they have real complexity, and they make faster decisions than you would expect because operational drag costs them tangible money.

**Secondary ICP: Fund Administrator (Year 2)**

| Dimension | Target |
|-----------|--------|
| Type | Mid-market fund administrator, not the top 5 |
| Clients | 30–150 GP clients; $10B–$75B total AUM served |
| Pain | Onboarding new GP clients manually; subscription review; investor communications at scale |
| Fit | Wants to offer a modern front-end to their GP clients without rebuilding their core accounting stack |
| Budget signal | Per-client licensing model; $200K–$750K/year |

**Opportunistic ICP: Complex Emerging Manager (Year 1–2, selective)**

Some Fund I/II managers launch with institutional backing, complex LP rosters, and a tech-first operational philosophy. These are worth pursuing when they exhibit the same characteristics as the primary ICP — technical savvy, complexity, and desire to build right from the start. Do not pursue emerging managers who are unsophisticated or primarily price-sensitive; they will drain implementation resources without yielding reference value.

## 2.2 Buyer Personas

These are the individuals who evaluate, champion, and approve CapHive. At a $500M–$10B fund, there are typically 3–5 stakeholders involved in the decision. Understanding each one is essential to moving through the sales cycle.

### Persona 1: The COO / Head of Operations (Primary Champion)
- **Title variants:** COO, Chief Operating Officer, VP Operations, Head of Fund Operations
- **What they own:** All investor operational workflows — onboarding, capital calls, distributions, compliance, fund admin coordination
- **Day-to-day pain:** Their team is performing high-value operational work that should be automated; errors in manual processes create expensive downstream corrections; each new fund vehicle adds linear headcount instead of leveraging existing infrastructure
- **What they want to hear:** "CapHive handles the operational complexity your current stack cannot — without requiring you to simplify your fund structure"
- **How they evaluate:** They will dig into the data model, the edge cases, and the exception handling. They have seen many tools that look good in demo and break in production. Give them a sandbox with real complexity.
- **Win trigger:** Demo with their actual fund structure, including parallel vehicles, co-invest SPVs, and mixed investor types. Show how CapHive handles it without workarounds.
- **Objection to handle:** "We've tried other platforms and they couldn't handle our complexity." Response: walk through the specific complexity they have and show it working.

### Persona 2: The CFO / Head of Finance
- **Title variants:** CFO, Managing Director Finance, Head of Fund Finance
- **What they own:** Financial controls, audit readiness, fund admin relationship, tax compliance
- **Day-to-day pain:** Compliance evidence is assembled manually before each audit or LP due diligence review; bank instruction changes create fraud risk that is not systematically controlled; K-1 delivery and tax form tracking is spreadsheet-managed
- **What they want to hear:** "CapHive creates a complete, auditable evidence trail for every investor decision, verification, and document delivery — without requiring anyone to prepare it manually"
- **Win trigger:** Compliance evidence binder demo + bank instruction change control workflow

### Persona 3: The Director of Investor Relations
- **Title variants:** IR Director, Head of IR, VP Investor Relations
- **What they own:** LP experience, capital call/distribution communications, reporting, tax season coordination
- **Day-to-day pain:** LP questions consume disproportionate IR team time; capital call and distribution processes require significant manual coordination; side letter commitments create obligation risk that lives in someone's head; tax season is a fire drill
- **What they want to hear:** "CapHive reduces LP service burden by 40%+ and makes your team proactive instead of reactive"
- **Win trigger:** LP portal + AI investor service assistant + side letter obligation matrix

### Persona 4: The Head of Legal / General Counsel (Approver)
- **Title variants:** General Counsel, Chief Compliance Officer, Deputy GC
- **What they own:** Legal risk, compliance program, LP agreement obligations, regulatory filings
- **Day-to-day pain:** Subscription document exceptions managed by email; side letter obligations not systematically tracked; compliance evidence requested by auditors and examiners requires significant legal team time to compile
- **What they want to hear:** "CapHive is not making legal decisions — it is creating the evidence and workflow structure that makes your compliance program defensible"
- **Win trigger:** Compliance evidence binder + AI review disclaimer (AI flags, human decides)

### Persona 5: The CTO / Head of Technology (Evaluator, not always present)
- **Title variants:** CTO, Head of Technology, Director of Engineering
- **What they own:** Technology stack, data security, vendor risk, API integrations
- **Day-to-day pain:** Existing systems do not expose APIs; data is trapped in fund admin or point solutions; no single source of truth for investor data
- **What they want to hear:** "CapHive has a real API, a documented data model, SSO/SAML, SOC 2, and a partner integration layer — we are building for teams like yours"
- **Win trigger:** API documentation review + security questionnaire completion + SSO demo

---

# 3. Competitive Landscape

## 3.1 The Competitive Map (High Level)

The US private funds software market is organised into distinct layers. CapHive's position in that map is specific and deliberate — it is not "connective tissue" between systems, and it is not trying to be everything to everyone. Understanding exactly where CapHive competes, where it complements, and where it integrates is essential to winning sales conversations and building the right partnerships.

### The Layered Map

```text
┌─────────────────────────────────────────────────────────────────────┐
│                    SPECIALIZED EXECUTION APIS                        │
│  DocuSign · Plaid · Persona · Middesk · ComplyAdvantage · Stripe    │
│  (CapHive INTEGRATES — these execute specific atomic actions)        │
└─────────────────────────────────────────────────────────────────────┘
                               ▲ API calls
┌─────────────────────────────────────────────────────────────────────┐
│                    THE OPERATIONS LAYER                              │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │   Investor   │  │  Fundraising │  │   Portfolio  │              │
│  │   Portal     │  │   Pipeline   │  │  Monitoring  │              │
│  │ Juniper Sq · │  │ DealCloud ·  │  │ Chronograph ·│              │
│  │ Carta · Arch │  │ 4Degrees ·   │  │ iLevel ·     │              │
│  │              │  │ Affinity     │  │ Canoe ·      │              │
│  │ ◀ CapHive ▶  │  │ ◀ CapHive ▶  │  │ Accelex      │              │
│  └──────────────┘  └──────────────┘  │ ◀ CapHive ▶  │              │
│  ┌──────────────┐  ┌──────────────┐  └──────────────┘              │
│  │  Onboarding  │  │   Document   │  ┌──────────────┐              │
│  │  & KYC       │  │   Mgmt /     │  │  Capital     │              │
│  │ Passthrough ·│  │   Data Room  │  │  Events      │              │
│  │ Anduin · Arch│  │ Box · Dropbox│  │ (calls,      │              │
│  │              │  │ Intralinks   │  │  distrib.,   │              │
│  │ ◀ CapHive ▶  │  │ ◀ CapHive ▶  │  │  commitments)│              │
│  └──────────────┘  └──────────────┘  │ ◀ CapHive ▶  │              │
│                                       └──────────────┘              │
│  CapHive is a full-stack platform that NATIVELY covers this layer.  │
│  A firm currently running 5-6 point solutions replaces them with 1. │
└─────────────────────────────────────────────────────────────────────┘
                               ▼ data exchange
┌─────────────────────────────────────────────────────────────────────┐
│                  FUND ACCOUNTING / GENERAL LEDGER                    │
│  Allvue · FIS Investran · SS&C Geneva · FundCount                   │
│  (CapHive COMPLEMENTS — these own the GL; CapHive sits above it)     │
└─────────────────────────────────────────────────────────────────────┘
```

### What This Map Means in Practice

**The operations layer is where CapHive competes and wins.** This layer — investor portal, onboarding, fundraising pipeline, portfolio monitoring, document management, capital events, AI features — is currently served by 5–6 separate point solutions that do not share data, require manual reconciliation between them, and collectively cost more than a single integrated platform. CapHive replaces all of them.

**The GL layer is where CapHive integrates, not competes.** The fund accounting general ledger (Allvue, FIS Investran, SS&C Geneva) handles double-entry bookkeeping, investor capital accounts at the accounting level, and regulatory reporting. CapHive does not build a GL. It exchanges data with the GL — pushing capital call and distribution data, receiving capital account statements — and handles everything above that line.

**The API execution layer is where CapHive integrates to extend.** E-signature execution (DocuSign), bank account verification (Plaid), identity verification (Persona, Middesk), and sanctions screening (ComplyAdvantage) are atomic, specialized services. CapHive calls their APIs to execute specific actions but owns the workflow, the evidence, and the lifecycle management around those actions.

### The Positioning Principle

CapHive's competitive position depends on who is in the room. Use the right framing for the audience — the underlying product truth is the same, but the emphasis shifts.

| Audience | Right Framing | Why It Works |
|----------|---------------|--------------|
| GP evaluating CapHive cold | "Replace your 5–6 point solutions with one platform. Keep your fund admin's GL — we connect to it." | They care about consolidation, integration cost, and a single data model |
| Fund administrator being pitched as a partner | "CapHive sits above your GL. We handle the operations layer your GP clients need — you keep the accounting work you own." | They need to know CapHive doesn't cannibalize their core business |
| GP who already uses Allvue or FIS for GL | "We complement your accounting system. CapHive handles everything above the GL — investor ops, portal, portfolio, compliance, AI." | Removes the biggest objection before it's raised |
| GP already using Juniper Square or Passthrough | "CapHive covers what they do, plus the full lifecycle they don't: capital events, portfolio monitoring, compliance evidence, side letters, AI review. We can run alongside during transition." | Lowers switching risk; displacement follows once CapHive is embedded |
| GP evaluating Chronograph or iLevel for portfolio monitoring | "CapHive does portfolio monitoring natively — with the same data model as your capital events, KPIs, and investor records. No separate system, no reconciliation." | Positions depth + integration as superior to a standalone monitoring tool |

## 3.2 Competitor Analysis

### Juniper Square / Carta / Dynamo — Investor Portals

**What they do well:** Investor portal UX, reporting delivery, document distribution, some fund accounting integrations, basic fundraising CRM.

**Where they fall short:**
- Built around the portal as the product — onboarding, capital events, compliance, and portfolio monitoring are secondary or missing
- Onboarding is form-based without AI-assisted review or exception routing
- No side-letter obligation tracking or LP obligation matrix
- Portfolio monitoring depth is limited for PE/credit/real estate complexity
- AI is a recent add-on, not native to the workflow architecture
- Carta and Dynamo tilt toward VC; less depth in institutional PE/credit

**CapHive's position:** CapHive natively covers investor portal, onboarding, capital events, portfolio monitoring, document management, KPI management, and AI features in one platform. Juniper Square, Carta, and Dynamo are point solutions for one layer of what CapHive covers end-to-end.

**How to win in a direct comparison:**
> "Juniper Square is an investor portal with some adjacent features. CapHive is a full fund operations platform — investor portal is one module. You get the full lifecycle: onboarding, KYC, capital calls, distributions, portfolio tracking, compliance evidence, side letters, AI review, and LP servicing. One system, one data model, no reconciliation between tools."

**When a prospect already has Juniper Square:** Don't ask them to rip it out on day one. Propose a side-by-side on the workflows Juniper Square doesn't cover well (onboarding, compliance, portfolio monitoring). Displacement often follows naturally once CapHive is embedded.

---

### Passthrough / Anduin / Arch — Subscription and Onboarding

**What they do well:** Subscription packet digitization, investor questionnaire routing, some KYC/AML integrations.

**Where they fall short:**
- Narrow scope: subscription only, not fund operations lifecycle
- No ongoing investor servicing or capital call/distribution workflows
- No side-letter or LP obligation tracking
- No AI document intelligence beyond basic form fill

**How CapHive wins:**
> "Passthrough handles the subscription form. CapHive handles the subscription form *plus* KYC, tax forms, bank verification, closing readiness, capital calls, compliance evidence, side letters, ongoing investor servicing, and AI document intelligence. It's the difference between a form tool and an operating system."

---

### Allvue / FIS Investran / SS&C Geneva / FundCount — Fund Accounting Platforms

**What they do well:** Deep fund accounting, waterfall calculations, investor capital accounts, regulatory reporting.

**Where they fall short:**
- Not designed for front-office or middle-office workflows
- Investor onboarding, document management, and LP communications are weak
- Long implementation timelines and high costs
- Not accessible for emerging managers

**How CapHive wins:**
> "We do not replace your accounting system. CapHive integrates with it, adding the workflow and intelligence layer for onboarding, documents, investor communication, compliance evidence, and AI review that accounting platforms were never built for."

**Important:** Never lead with "we replace Allvue." This causes prospects to default to their existing relationships.

---

### Full-Service Fund Administrators (SS&C, Gen II, U.S. Bank, Apex, Alter Domus)

**What they do:** Everything — fund accounting, investor services, tax, compliance, capital activity, reporting.

**The nuance:** Fund administrators are both competitors and partners. Positioning matters enormously.

**How CapHive wins with GPs:**
> "Your fund administrator handles accounting and tax. CapHive handles the workflow layer between you and your admin — investor onboarding, document execution, capital call/distribution communication, LP portal, compliance evidence, and AI review. You get better service *and* better evidence."

**How CapHive wins with fund administrators themselves:**
> "CapHive helps you service more GP clients without adding headcount. We handle the onboarding workflow, subscription review, investor communications, and document intelligence — you retain the accounting and tax work you own."

---

## 3.3 CapHive's Sustainable Differentiation

The honest answer is that product features can be copied. CapHive's sustainable differentiation is:

1. **AI-native architecture** — not retrofitted AI on a legacy platform; workflows built around document intelligence from day one
2. **Workflow completeness** — covering the full lifecycle from prospect to ongoing investor servicing, not one slice
3. **Ecosystem integration** — designed to work with existing fund admins, CRMs, e-sign providers, and KYC tools rather than demand rip-and-replace
4. **LP experience** — an investor-facing layer that feels modern, not like a 2010-era fund admin portal

---

# 4. Go-to-Market Motion

## 4.1 Sales Strategy

### Phase 1: Founder-Led, High-Complexity Focus (Months 1–12)

The first 5 customers are won through deep technical credibility and warm introductions. The buyer at a $500M–$10B fund has seen many software demos. What wins with them is not a polished sales deck — it is demonstrating that CapHive handles their specific complexity without workarounds.

**Sales motion:**

1. **Identify 30 target accounts** — GPs with $500M–$10B AUM, 4+ active fund vehicles, recent fund closes or upcoming activity, reputation for tech-forward operations
2. **Warm intro paths:** Fund counsel (a single fund formation partner at a top law firm knows 50+ GP clients); fund administrators where CapHive can complement rather than compete; LP placement agents who see operational quality as a selection criterion; operating partner networks (NVCA, MFA, AIC, ILPA)
3. **Discovery call — go deep, not wide:** The question is not "walk me through your process." The question is: "Tell me about the most painful investor situation you've dealt with in the last 12 months — a side letter obligation you almost missed, a closing that dragged for 3 months, a capital call that had errors." Let the specific pain surface.
4. **Demo — match their complexity:** Do not show a generic 10-LP demo. Before the product demo, learn their fund structure: how many vehicles, investor types, any foreign investors, any active side letters, fund admin name. Configure a demo environment that mirrors their situation. The COO's reaction when they see their actual complexity handled correctly is the deal moment.
5. **Technical proof:** For CTO/tech stakeholders, offer API documentation, a sandbox environment, and a completed security questionnaire before they ask for one.
6. **Pilot design:** Offer a structured 60-day pilot tied to a specific operational milestone — a closing, a capital call cycle, or a first LP obligation matrix population. Define success criteria upfront. Price the pilot at a discounted annual rate, not free.

**Sales cycle expectation:**
- Primary ICP ($500M–$3B, tech-forward): 8–16 weeks, 3–5 stakeholders
- Upper ICP ($3B–$10B, established firm): 12–24 weeks, 5–8 stakeholders, formal vendor evaluation
- Fund administrator: 16–30 weeks, formal procurement, InfoSec review required

**What accelerates the deal:**
- A shared contact who has already seen CapHive in production
- Upcoming closing or LP event that creates urgency
- Operational pain event (missed obligation, compliance gap found) that happened recently
- CTO or technologist already in the buying group

### Phase 2: Partner-Led Growth (Months 10–24)

Once 5+ customers are live and reference-able, shift to structured partnership development:

- **Fund administrator partnerships:** Identify 3 mid-market fund admins ($10B–$75B AUM served) who are losing GP clients to firms that offer better technology. Pitch CapHive as the front-end they can offer without rebuilding their accounting stack.
- **Fund counsel referral program:** 3–5 law firms with active fund formation practices; offer co-branded onboarding templates and a counsel view of the closing room
- **Content and community:** Build the authoritative resource for US private fund operational best practices. The buyers in our ICP read, share, and trust high-quality operational content.

### Phase 3: Platform and Ecosystem (Year 2+)

- Integration marketplace: direct connect to KYC, e-sign, bank verification, CRM, and fund admin providers
- Inbound demand from content, conference presence, and reference customers
- Enterprise self-serve for firms that have seen CapHive at a peer firm

## 4.2 Pricing Framework

### Principles

**1. Never price on AUM.** AUM-based pricing is common among fund administrators and older portal vendors. It is the wrong signal for CapHive — it implies CapHive is extracting a rent from the fund's assets rather than delivering operational value. A $2B fund and a $500M fund can have identical operational complexity and identical value derived from the platform. Price on what drives actual usage: investor count and active modules.

**2. Modular — pay only for what you use.** Not every firm needs every module on day one. A GP focused on a new raise needs the fundraising pipeline and onboarding modules. A GP in steady-state operations needs capital events, portal, and portfolio monitoring. CapHive's pricing should allow a firm to start with the modules that solve their immediate pain and expand as their usage grows. This lowers the entry barrier, creates a natural expansion motion, and ensures each module is priced against the value it specifically delivers.

**3. Step up on LP count and complexity, not seat count.** The operational effort CapHive replaces scales with the number of investors managed and the complexity of the fund structure (number of vehicles, SPVs, foreign investors, side letters). Seat-based pricing penalises firms with larger teams and rewards under-licensing. LP count bands are transparent, predictable, and map directly to the work the platform is doing.

---

### LP Count Bands (Primary Pricing Dimension)

| Band | Investor Records | Indicative Annual Base |
|------|-----------------|----------------------|
| Starter | Up to 150 LPs | $60K–$90K |
| Growth | 151–400 LPs | $90K–$150K |
| Scale | 401–800 LPs | $150K–$220K |
| Enterprise | 800+ LPs | $220K–$500K+ |

*Investor records = active LP records across all fund vehicles on the platform. Co-invest SPV investors and parallel fund investors count toward the total.*

---

### Module Pricing

A base subscription includes the core platform (investor records, document management, fund vehicle setup, basic portal, audit logs). Modules are enabled and priced on top. Each module maps to a discrete operational workflow.

| Module | What It Covers | When a Firm Needs It |
|--------|---------------|----------------------|
| **Fundraising & Pipeline** | Deals management, investor pipeline, health scores, CRM integration | Active fundraise underway |
| **Onboarding & KYC** | KYC workflows, e-sign integration, investor qualification, closing room | New fund close or ongoing investor admissions |
| **Capital Events** | Capital calls, distributions, commitment tracking, payment reconciliation | Fund is past first close and calling capital |
| **Investor Portal & Tax Center** | LP-facing portal, document delivery, K-1 management, CPA delegation | Investor servicing post-close |
| **Portfolio Monitoring** | Portfolio investments, valuations, FMV, performance ratios, KPI management | Fund has active portfolio companies |
| **Fund Ratios & Reporting** | TVPI/DPI/RVPI/XIRR/MOIC, carry computations, Report Builder, scheduled reports | Quarterly LP reporting cycle |
| **Compliance Evidence** | Bank verification controls, compliance binder, side letter matrix, obligation tracking | Audit prep, institutional LP due diligence |
| **AI Intelligence** | AI subscription review, AI portfolio reports, LP service assistant, document Q&A | After base workflows are live; AI accelerates review |
| **Secondary Sales** | LP interest marketplace, clearing algorithm, SPA generation | Secondary liquidity events |
| **Fund Admin Exchange** | Structured data exports/imports with fund administrator | Firms with a third-party fund admin |

---

### Complexity Add-Ons

Some structural factors increase the operational work CapHive manages, and are priced accordingly:

| Factor | Why It Drives Price |
|--------|-------------------|
| Additional fund vehicles beyond base (e.g. >5 vehicles) | Each vehicle adds investor rosters, document templates, capital event workflows |
| Foreign investor population >25% | Multi-currency folios, W-8 form routing, FATCA classification, withholding tracking |
| Active side letters >20 | LP obligation matrix population, MFN analysis, obligation calendar |
| API integration count | Some integrations (KYC providers, bank verification) carry pass-through API costs |
| Dedicated implementation and CSM | Included at Enterprise tier; available as an add-on for Growth and Scale |

---

### One-Time Setup and Integration Fees

Annual subscription covers ongoing platform access. Setup and integration work is priced separately as a one-time fee.

| Item | Scope | Indicative Fee |
|------|-------|---------------|
| **Platform onboarding** | Fund vehicle configuration, investor data migration, user setup, first closing walkthrough | $5K–$20K depending on fund count and data complexity |
| **CRM integration** | Bidirectional sync with Salesforce, HubSpot, Affinity, or DealCloud | $3K–$8K per CRM |
| **Fund admin data exchange** | Configuring export/import formats for the firm's specific fund administrator | $3K–$10K depending on admin's format requirements |
| **E-sign provider integration** | Connecting DocuSign or Dropbox Sign to the firm's existing account and template library | $2K–$5K |
| **KYC/identity provider integration** | Connecting Persona, Middesk, or equivalent; configuring workflow rules | $3K–$8K per provider |
| **Bank verification integration** | Plaid or equivalent; configuring verification rules and fraud hold logic | $2K–$5K |
| **Sanctions/AML provider integration** | ComplyAdvantage or equivalent; configuring screening frequency and exception routing | $3K–$8K |
| **Custom API integration** | Bespoke integration not covered by standard connectors | Scoped separately |

**Why charge for setup:** Implementation quality directly determines whether the platform delivers value in the first 90 days. Charging for setup creates alignment — CapHive has skin in the game to configure the platform correctly, and the firm has a committed engagement rather than a self-serve trial that stalls. Setup fees should never be a profit centre; they should reflect the actual cost of doing the integration work well.

---

### What to Avoid

- **AUM-based pricing** — wrong signal, wrong incentive, wrong comparison to fund administrators
- **Per-user seat pricing** — the COO should not need to justify 15 seats when 3 people use the platform daily; operational scope is the right unit
- **Bundling everything into one "enterprise" price** — hides module value, makes expansion conversations harder, and makes it easy for prospects to compare on total price rather than value per workflow
- **Waiving setup fees to close a deal** — this shortcuts the implementation process that determines first-90-day outcomes; discount the annual fee instead if needed

## 4.3 Marketing Strategy

### Immediate (Months 1–6): Credibility First

Marketing at this stage is sales support and credibility building:

1. **Website positioning:** "Private fund operations for teams that take complexity seriously." Not: "The easiest fund software." This ICP is not buying easy — they are buying capable.
2. **Technical depth content:** Publish one long-form operational guide per month: "Managing W-8BEN-E FATCA classifications at scale," "Side letter obligation tracking for multi-fund GPs," "Building a compliance evidence binder that survives an SEC exam." These establish subject matter credibility with the exact buyer.
3. **Reference assets:** First 3 customers should be asked for: (a) a named quote, (b) a 15-minute reference call for prospects, (c) a one-paragraph case study. These matter more than any marketing campaign.
4. **Security documentation:** SOC 2 readiness, completed security questionnaire template, and a data processing agreement should be ready before the first enterprise evaluation.

### Growth (Months 7–18): Channel and Content

1. **Fund counsel content partnerships:** Co-author operational guides with fund formation attorneys. These reach the exact buyers CapHive is targeting.
2. **Conference presence:** ILPA Summit, MFA Forum, AIC Annual Conference — not as a vendor exhibitor initially, but as a presenter or panelist on operational technology topics.
3. **LinkedIn:** Founder-led content on operational complexity, AI in fund operations, and compliance best practices. The target ICP COO reads LinkedIn daily.
4. **Webinar series:** "Fund Operations for the Modern GP" — invite fund admins, counsel, and COOs as co-presenters. Builds relationships and generates pipeline simultaneously.

### Scale (Year 2+): Platform Network Effects

1. Integration partnerships drive co-marketing (KYC providers, e-sign, fund admins)
2. Community: CapHive Users Group for COOs and operations leaders
3. Conference sponsorship once reference customers are publicly referenceable

## 4.4 First Customer Acquisition Playbook

Getting from zero to 5 customers in the primary ICP is the hardest phase. Here is a concrete playbook:

**Step 1: Build the target account list**
Identify 30 firms meeting the ICP profile:
- $500M–$5B AUM (easier to win than $5B+)
- 3+ fund vehicles including at least one SPV or parallel fund
- Known to have operational complexity (look for multi-strategy, international LPs, complex fund structures)
- Technology-forward reputation (presence at NVCA tech track, known to use SaaS tools)

**Step 2: Find the warm path**
Cold outreach to a COO at a $1B PE fund rarely works. The warm path matters:
- Fund counsel at a top-5 fund formation firm (they have 50+ GP relationships each)
- A shared LP who is invested in multiple CapHive target firms
- A fund administrator who serves the target firm and is open to co-presenting CapHive

**Step 3: Lead with the problem, not the product**
The opening call is an operational problem exploration: "I'm researching how mid-market GPs manage the operational complexity between their fund admin, counsel, and LP base — particularly around onboarding, compliance evidence, and LP obligations. Can I get 30 minutes?" This opens a peer conversation, not a vendor demo.

**Step 4: Design the demo around their specific complexity**
Before showing the product, learn:
- Fund structure (how many vehicles? any SPVs or feeders?)
- LP mix (domestic only, or foreign investors?)
- Existing systems (which fund admin? which CRM?)
- Most painful recent operational situation

Then configure a demo environment that mirrors their situation. Walk them through the one scenario that maps directly to their stated pain.

**Step 5: Propose a structured pilot, not a free trial**
A free trial signals low confidence. A structured pilot says: "Here is a 60-day engagement. We will configure your fund structure, load your current closing, and run one full closing cycle through CapHive. The success criterion is: your operations team agrees this is meaningfully better than your current process. The price is $X for the pilot period, which converts to the annual contract if it succeeds."

**Step 6: Make the pilot operationally excellent**
Assign a dedicated implementation engineer. Pre-configure everything possible before they log in. Make the first investor onboarding take under 30 minutes. Deliver a weekly check-in to surface and resolve friction fast. This is the audition for the annual contract.

---

# 5. Phase 1: US-Native Foundation

## Overview

> **Goal:** Make CapHive credible enough for a US fund manager to run their first real investor onboarding and closing through it.

Phase 1 is about trust, not features. Every capability built here serves one purpose: allowing a US fund manager to say "CapHive understands how US private funds work."

**What "done" looks like for Phase 1:**
- A US emerging manager can configure a Delaware LP fund, send subscription packets to 20+ investors, collect W-9/W-8 forms, verify bank instructions, complete KYC/KYB for each investor, and generate a closing-ready summary — all within CapHive
- The demo impresses a first-time buyer within 15 minutes
- First 3 paying customers are live

---

## 5.1 US Terminology and Data Model

### The Concept

US private funds use terminology, legal structures, and investor eligibility concepts that are specific to US law and practice. If CapHive's data model does not reflect these accurately, US buyers will dismiss the product in the first demo.

### What to Build

Legend: ✅ Exists in CapHive today · ⚠️ Partial / needs US adaptation · ❌ Not yet built

#### Fund Structures

| US Requirement | Status | Notes |
|----------------|--------|-------|
| Investment fund entity (generic) | ✅ | `Investment Fund` and `Angel Fund` entity types; parent/child hierarchy for management company + fund relationships |
| Delaware LP / LLC as named legal structure type | ❌ | No US legal structure classification on the entity. Need a "Legal Structure" field (Delaware LP, Delaware LLC, Cayman LP, etc.) so documents, tax treatment, and reporting can reference it correctly |
| SPV / co-investment vehicle | ⚠️ | Can be represented as a separate entity with a parent fund, but no SPV-specific type or flag. Need an explicit "vehicle type" field (SPV, feeder, blocker, parallel fund, master, co-invest) |
| Feeder fund / blocker / parallel fund | ⚠️ | Feeder→master is fully modelled (`Fund.master_fund_id` / `has_many :feeder_funds`); blocker and parallel fund are separate fund entities grouped under a common parent entity — no explicit "blocker" type flag yet |
| Master-feeder relationship | ✅ | `Fund belongs_to :master_fund` and `has_many :feeder_funds` FK associations exist; `CapitalCommitment.feeder_fund_id` tracks which feeder fund a master-fund commitment came from |
| Fund-of-one | ⚠️ | Representable as a single-LP fund entity, but no specific type or workflow shortcut |
| GP LLC + management company | ✅ | Parent entity hierarchy supports this; GP and management company can be separate entities under the same parent |

#### Investor Types

| US Requirement | Status | Notes |
|----------------|--------|-------|
| Individual investor | ✅ | Individual KYC type with field set for natural persons |
| Non-individual / entity investor | ✅ | Non-Individual KYC type covers companies, LLPs, trusts, partnerships |
| Custom investor categories (HNI, Trust, Corporate, etc.) | ✅ | Configurable per entity via `INVESTOR_CATEGORIES` setting |
| Family office | ✅ | `Family Office` is a dedicated entity type |
| Joint investor | ❌ | No joint account / joint investor structure in the data model; no field for multiple named holders on one investment |
| Trust (with trustee documentation workflow) | ⚠️ | Can be set as a custom category; Non-Individual KYC can capture trustee details via custom form fields — but no structured trustee verification workflow |
| IRA / pension plan / retirement account | ❌ | No specific investor type for tax-advantaged accounts; no field for custodian, plan type, or IRA restrictions |
| Foundation / endowment | ⚠️ | Representable as Non-Individual with custom category; no specific compliance field set for 501(c)(3) status or spending policy |
| Fund-of-funds | ⚠️ | Custom category only; no structured LP-of-LP look-through or beneficial owner cascade |
| Sovereign wealth fund | ⚠️ | Custom category only; no W-8EXP routing or sovereign entity compliance workflow |
| US investor type taxonomy with distinct field sets | ❌ | KYC form types are configurable but not pre-built for US investor type distinctions; need US-specific form type templates per investor class |

#### Fund Concepts

| US Requirement | Status | Notes |
|----------------|--------|-------|
| Commitment (committed amount) | ✅ | Full capital commitments module with folio ID, fund close, unit type, multi-currency |
| Capital contribution / called amount | ✅ | Called amount tracked per commitment; capital calls generate per-investor remittances |
| Capital call (notice + collection workflow) | ✅ | Full lifecycle: create, calculate, approve, notify, track payment, reconcile |
| Distribution | ✅ | Full capital distributions module with fees, approval, payment completion |
| Equalization (close percentage) | ✅ | Fund closes with per-close call percentages; later-close investors called at higher percentage to equalize with first-close investors |
| Multi-currency commitments and calls | ✅ | Folio currency ≠ fund currency supported; exchange rate adjustments available |
| Unfunded commitment | ⚠️ | `unfunded_commitment_as_of(end_date)` exists as a computed method on `CapitalCommitment`; not yet a named stored field, not surfaced on notices or LP portal |
| Capital account (LP-level account statement) | ⚠️ | Account entries exist (FMV, cash in hand, etc.) and performance metrics (TVPI, DPI) are computed per folio — but there is no formal US-style capital account statement (contributions, distributions, FMV, unrealised gain by period) generated as a document |
| Recallable distribution | ❌ | No flag or tracking for distributions that the GP has the right to recall. Needed for capital call calculations that depend on net contributed capital |
| Default interest on missed capital calls | ❌ | No default interest calculation; no overdue remittance penalty workflow |
| Bridge loan / subscription line | ❌ | No bridge facility model; subscription credit line usage affects called amounts and IRR calculations and is not currently handled |
| Capital recycling | ❌ | No recycling flag or workflow; recycled amounts would affect unfunded commitment and call capacity calculations |
| Skip call notice for specific investor | ✅ | `skip_call_notice` flag on a commitment excludes that folio from capital call notice generation |
| Excused investor from specific investments | ⚠️ | `Excused Investors` exists on portfolio investments (per the portfolio investments guide) but not as a systematic excuse mechanism tied to LPA terms or side letter rights |

#### Legal Exemptions

| US Requirement | Status | Notes |
|----------------|--------|-------|
| Accredited investor representation | ❌ | No structured field; would need to be captured as a custom KYC form field or custom investor field — not a first-class data point today |
| Qualified purchaser status | ❌ | Not in the system; needs a structured eligibility field with the representation date and basis (assets-under-management test, investments test) |
| Qualified client status | ❌ | Not in the system |
| Knowledgeable employee | ❌ | Not in the system |
| 3(c)(1) beneficial owner count tracking | ❌ | No investor count against a 3(c)(1) exemption limit; no alert when approaching the 100-beneficial-owner threshold |
| 3(c)(7) QP-only fund enforcement | ❌ | No fund-level exemption type setting that enforces QP status on all admitted investors |
| ERISA benefit plan investor flag | ❌ | No ERISA flag; no benefit plan investor percentage tracking against the 25% plan asset threshold |
| Bad actor representation | ❌ | Not in the system |
| Regulation D exemption tracking | ❌ | No Reg D filing readiness or exemption type classification on the fund |

#### Tax Concepts

| US Requirement | Status | Notes |
|----------------|--------|-------|
| PAN (India tax ID) | ✅ | PAN field on investor/entity, with CKYC/KRA verification integration |
| FATCA / CRS classification as custom form field | ⚠️ | Can be added as a custom step in the Non-Individual KYC form wizard; not a structured field with routing logic or expiry tracking |
| W-9 form collection and TIN verification | ❌ | No W-9 workflow; no TIN field distinct from PAN; no IRS TIN matching integration |
| W-8BEN (non-US individual) | ❌ | No W-8 form type, routing logic, or expiry tracking |
| W-8BEN-E (non-US entity) | ❌ | No W-8BEN-E; no FATCA classification tree (Active NFFE, Passive NFFE, FFI, etc.) |
| W-8IMY (intermediary / flow-through) | ❌ | Not in the system |
| GIIN capture and validation | ❌ | No GIIN field; no FATCA Financial Institution identification |
| Withholding status tracking | ❌ | No withholding rate or exempt status field per investor |
| K-1 delivery workflow | ❌ | No K-1 delivery module; documents can be uploaded and shared via the portal but no structured tax year / K-1 matching / CPA delegation workflow |
| 1042-S tracking | ❌ | Not in the system |
| EIN / SSN for US investors | ⚠️ | PAN field exists for India; a separate US Tax ID field (EIN for entities, SSN/ITIN for individuals) needs to be added with appropriate encryption and access controls |

### Product Rule

> **Do not hardcode one "US fund" model.** Build a flexible entity and investor model that handles funds, feeders, blockers, SPVs, parallel vehicles, and investor entities with nested beneficial owners.

### Use Case: Multi-Vehicle Fund Structure

A US venture fund has:
- Main Delaware LP (the primary fund vehicle)
- GP LLC (holds the general partner interest)
- Management company (receives management fees)
- Parallel fund for a strategic LP with special terms
- SPV for one co-investment alongside the fund
- Several LPs investing through family office LLCs
- Two foreign investors requiring W-8BEN-E
- One trust investor requiring trustee documentation

CapHive must represent this structure clearly. Each vehicle has its own investor roster, tax treatment, and document requirements. This is day-one reality for even a small emerging manager.

---

## 5.2 E-Signature and Subscription Document Execution

### The Concept

US private funds are built on executed subscription documents. E-signature is table stakes — but the *workflow* around it is where CapHive creates value. Sending a DocuSign envelope is not a differentiator. Managing the full subscription workflow from investor data capture to countersigned archive is.

### What to Build

**Subscription Packet Engine**

```text
Investor profile created
        │
        ▼
System determines required forms
(subscription agreement, investor questionnaire,
accreditation reps, side letter if applicable)
        │
        ▼
Forms pre-filled from investor profile data
        │
        ▼
Packet sent for e-signature via integrated provider
        │
        ▼
Investor signs; co-signatories notified
        │
        ▼
GP / counsel reviews exceptions or missing fields
        │
        ▼
GP countersigns
        │
        ▼
Final executed package stored in investor record
with certificate of completion
```

**E-Signature Provider Support**

| Segment | Providers |
|---------|-----------|
| Enterprise funds | DocuSign, Adobe Acrobat Sign |
| Developer-friendly | Dropbox Sign |
| Mid-market | PandaDoc, SignNow |

**Critical capabilities:**
- Route to multiple signers in the correct sequence
- Support countersignature by GP/manager
- Track status at document and investor level
- Allow wet-sign/manual upload fallback for legacy investors
- Version-control counsel-approved templates
- Store certificate of completion alongside executed PDF

### The Positioning Statement

> "We integrate with DocuSign" is a feature. The value statement is: **"CapHive manages the full subscription workflow from data capture to signed package, countersignature, investor admission, and audit evidence — DocuSign is the signing mechanism, not the workflow."**

---

## 5.3 Bank Verification and Payment Instruction Controls

### The Concept

Bank verification in the US fund context is not a one-time API call. It is a controlled lifecycle around payment instructions, fraud risk, change approvals, and audit evidence. Distribution fraud is a real and growing threat in private fund operations.

### What to Build

**Payment Instructions Control Center**

```text
Investor submits bank details
        │
        ▼
Bank account ownership verification
        │
        ├── Instant verification success ──▶ Verified; available for use
        │
        ├── Micro-deposit required ─────────▶ Pending LP confirmation
        │
        └── Failed / name mismatch ──────────▶ Exception review queue

If bank details change later:
        │
        ▼
Change event triggers enhanced verification
        │
        ├── Low-risk change (same account type, same name) ──▶ Re-verify
        └── High-risk change (new account, new bank) ─────────▶ Dual approval
                                                               + GP notification
                                                               + 72-hour hold
```

**Provider Options**

| Need | Providers |
|------|-----------|
| Bank account linking and verification | Plaid, MX, Finicity, Stripe Financial Connections |
| ACH/payment operations | Modern Treasury, Dwolla, Checkbook, Increase |
| Fraud and risk scoring | Sardine, Socure, Alloy |

### Use Cases

**Distribution fraud prevention:** An investor changes their bank instructions 48 hours before a $2M distribution. CapHive flags the change, requires enhanced verification, notifies the GP operations team, and places a hold on the new account until dual approval is completed. The old account is used for the current distribution.

**ACH capital call collection:** A fund wants to allow ACH debit for smaller commitments. CapHive verifies each account, obtains the required ACH authorization, tracks status in real time, and records any failed payments or returns in the investor record.

**Wire instruction evidence:** An institutional LP uploads wire instructions as a PDF. CapHive stores the document, captures who reviewed and approved it, ties it to the capital call workflow, and creates an audit-ready evidence record.

---

## 5.4 Identity Verification, KYC, KYB, AML, and Sanctions

### The Concept

US private funds need to verify investors, entities, beneficial owners, and authorized signatories. The compliance evidence from this process matters as much as the verification result itself — for fund auditors, prime brokers, banking relationships, and eventual LP-level due diligence.

### What to Build

**Compliance Evidence Binder (per investor)**

```text
Investor: Sequoia Family Office LLC

Identity & Entity Verification
  ├── Entity type: Delaware LLC
  ├── EIN: verified
  ├── Formation docs: received and reviewed
  ├── Authorized signatory: John Smith — identity verified
  └── Beneficial owners (>25%): 2 identified, both screened

Screening Results
  ├── Entity sanctions: clear — ComplyAdvantage — [date]
  ├── John Smith — individual sanctions: clear — [date]
  ├── John Smith — PEP screening: clear — [date]
  └── Adverse media: no material findings — [date]

Investor Eligibility
  ├── Accredited investor: confirmed — questionnaire responses on file
  ├── Qualified purchaser: confirmed — $25M+ in investments represented
  └── ERISA: not a benefit plan investor — confirmed

Status: Approved
Reviewer: Sarah Chen — [date]
Next refresh: Sanctions — annually; Formation docs — on change
```

**Key providers:**

| Need | Providers |
|------|-----------|
| Individual identity verification | Persona, Socure, Onfido, Trulioo |
| Business/entity verification | Middesk, Alloy, Persona |
| Sanctions, PEP, adverse media | ComplyAdvantage, LSEG World-Check, Dow Jones |
| Fraud risk | Sardine, Socure |

### The Core Principle

> The product should not just show "KYC passed." It must show **what was checked, when, which data source was used, who approved exceptions, and what triggers a refresh.** This is what auditors and institutional LPs ask for.

---

## 5.5 US Tax Form Collection

### The Concept

Tax form collection is one of the most important — and most underestimated — US-specific workflows. Every investor has a required tax form. The form depends on investor type, US/non-US status, entity classification, and FATCA status. Missing or incorrect forms cause tax withholding problems, fund administrator exceptions, and LP complaints.

### Forms to Support

| Form | Who Needs It | Common Scenario |
|------|-------------|-----------------|
| W-9 | US persons and entities | Most domestic LPs |
| W-8BEN | Non-US individuals | Foreign individual LP |
| W-8BEN-E | Non-US entities | Foreign corporate LP, Cayman feeder |
| W-8IMY | Intermediaries, flow-through entities | Foreign fund-of-funds, nominees |
| W-8EXP | Foreign governments, tax-exempt orgs | Sovereign funds, foreign endowments |
| W-8ECI | Income effectively connected to US trade | Rare, but required when applicable |
| 1042-S | US-source income to foreign persons | Generated by fund/tax advisor |
| K-1 | Partnership income allocation | All fund investors, annually |

### What to Build

**Tax Form Wizard**

```text
Investor type entered
        │
        ▼
US person or entity?
        │
        ├── Yes ──────────────────────────────▶ W-9 workflow
        │                                       (collect TIN, certifications)
        │
        └── No ───▶ Individual or entity?
                    │
                    ├── Individual ────────────▶ W-8BEN workflow
                    │                           (country, foreign TIN)
                    │
                    └── Entity ─▶ FATCA classification
                                  │
                                  ├── Active NFFE ────▶ W-8BEN-E Part XXV
                                  ├── Passive NFFE ───▶ W-8BEN-E + UBO cert
                                  ├── FFI with GIIN ──▶ W-8BEN-E Part X + GIIN
                                  ├── Flow-through ───▶ W-8IMY + withholding stmt
                                  └── Tax-exempt org ─▶ W-8EXP
```

**Required capabilities:**
- Guide investor to correct form through intelligent questionnaire
- Pre-fill fields from investor profile
- Validate required fields and warn on common errors
- Track form version, expiration date, and FATCA classification
- Flag forms that are stale (W-8 forms expire every 3 years or on status change)
- Export tax data fields to fund administrator in standard formats

### Use Case: Cayman Feeder into US Fund

A Cayman Islands-based fund-of-funds invests into a US PE fund. CapHive identifies the investor is a non-US entity, asks FATCA classification questions, determines the investor is a Passive NFFE, collects W-8BEN-E with the required Part IX certification, requests UBO identification for any US owners above the threshold, stores the form, and exports the FATCA classification to the fund administrator for annual reporting.

---

## 5.6 Investor Qualification Engine

### The Concept

US private fund subscription documents require investors to make specific legal representations about their eligibility — accredited investor, qualified purchaser, qualified client, ERISA status, and more. The rules vary by fund structure, exemption, and investment strategy. CapHive must support configurable eligibility rules rather than a one-size-fits-all questionnaire.

### What to Build

```text
Fund configuration (set by GP or counsel)
      │
      ├── Is this a 3(c)(1) fund? → track investor count toward 100 limit
      ├── Is this a 3(c)(7) fund? → require QP status for all investors
      ├── Are performance fees/carry charged? → qualified client required
      ├── ERISA restrictions set? → flag benefit plan investors and track %
      └── Non-US investors allowed? → route to additional KYC/tax steps

Investor completes qualification questionnaire
      │
      ▼
Rules engine evaluates responses
      │
      ├── Qualified ───────────────────────────▶ proceed to onboarding
      ├── Exception (borderline case) ─────────▶ counsel review queue
      ├── Needs more information ──────────────▶ follow-up request to LP
      └── Not eligible ────────────────────────▶ notify GP; do not proceed
```

**Concepts to support:**

| Concept | Why It Matters |
|---------|----------------|
| Accredited Investor | Required for Regulation D private placements |
| Qualified Purchaser | Required for 3(c)(7) funds; higher threshold than accredited |
| Qualified Client | Required for funds charging performance fees under Advisers Act |
| Knowledgeable Employee | Relevant eligibility category for certain fund strategies |
| ERISA / Benefit Plan Investor | Triggers plan asset rules; percentage tracking required |
| Bad Actor Representations | Required for Reg D reliance |
| 3(c)(1) Investor Count | Funds cannot exceed 100 beneficial owners |

> **Build this as a rules engine, not hardcoded logic.** US fund counsel will want to configure qualification logic per fund. The product should support this without engineering involvement.

---

# 6. Phase 2: Operational Depth

## Overview

> **Goal:** Make CapHive useful for the ongoing lifecycle of a US fund — after the initial closing, through capital events, tax season, and year-round investor servicing.

Phase 1 gets the investor in. Phase 2 makes CapHive the system the GP, fund admin, and IR team uses every day.

**What "done" looks like for Phase 2:**
- A GP can manage a capital call from approval to notice delivery and payment tracking entirely within CapHive
- The fund admin can pull investor master data, tax form status, and capital call results from CapHive via export or API
- IR team uses CapHive to answer LP questions without hunting through email
- K-1 delivery is tracked and evidenced for every investor

---

## 6.1 Closing Room

### The Concept

US funds admit investors in closings. A closing brings together subscription documents, KYC/KYB results, tax forms, bank verification, legal exceptions, and fund administrator confirmation. Today, GPs track all of this in a spreadsheet. CapHive should make this real-time and collaborative.

### Revised Understanding — The Platform Already Has Most of This

After examining the codebase closely, the Closing Room does not need to be built from scratch. The platform already has:

- **`InvestorKyc.submission_status = verified`** — a verified KYC already means: all required fields are present (including `bank_name`, `bank_account_number`, `bank_account_type`, `ifsc_code` — all presence-validated), all required documents uploaded, AML triggered, and no blocking issues. Verified KYC = data and bank details confirmed.
- **`KycOnboardingAgent`** — runs a full pipeline: field completeness, document presence, AI document validity, field-to-document consistency, expiry checks, AML auto-trigger. Produces a `SupportAgentReport` with structured issue counts surfaced as an `onboarding_status` badge on every KYC.
- **`CapitalCommitment.onboarding_completed`** boolean with `lp_onboarding_complete` / `lp_onboarding_incomplete` scopes.
- **Onboarding Report dashboard** (`funds/dashboard/onboarding_report.html.erb`) — already shows per-commitment status across all investors in a fund.

What the Closing Room adds for US funds is **three new check steps in the existing agent pipeline**, not a new model hierarchy.

### What CapHive Has vs. What the US Closing Needs

| Closing Dimension | CapHive Today | What Changes for US |
|-------------------|---------------|---------------------|
| KYC verified (all data + docs) | ✅ `submission_status = verified` via `KycOnboardingAgent` pipeline | Add US-specific field checks (SSN/EIN, US investor type) to the existing agent |
| Bank details confirmed | ✅ Bank fields are required on `InvestorKyc`; `bank_verification_response` stores verification evidence | For US: bank verification integrates with Plaid (see `bank_instruction_controls.md`); verified status feeds into KYC |
| AML / sanctions cleared | ✅ `KycOnboardingAgent` auto-triggers `GenerateAmlReportJob` when no blocking issues | US providers (ComplyAdvantage) replace India providers; same agent trigger |
| Per-investor readiness score | ✅ `SupportAgentReport` with `onboarding_status` badge showing issue counts | Add US check cards to the badge partial |
| Subscription docs signed | ⚠️ E-sign records exist per document; not currently a `KycOnboardingAgent` check | **New agent step:** `check_subscription_doc_status` reads `ESignature` records |
| US tax form collected | ❌ No US tax forms yet | **New agent step:** `check_us_tax_form_status` reads KYC json_fields (from `us_tax_forms.md`) |
| Investor qualification (AI/QP/QC) | ❌ Not yet built | **New agent step:** `check_investor_qualification` reads `InvestorQualification` records |
| Side letter executed | ❌ Not yet built | **New agent step (Phase 2):** `check_side_letter_status` |
| Cross-investor closing dashboard | ✅ Onboarding Report already exists | Enhance with summary bar (Ready/Blocked/Admitted) and Admit action |
| `onboarding_completed` auto-set | ⚠️ Currently set manually | Auto-set when agent finds zero blocking issues and `submission_status = verified` |
| Closing binder | ❌ Not yet built | `ClosingBinderJob` triggered when `onboarding_completed` flips to true |
| Fund admin export at close | ⚠️ Report Builder available | Triggered from Onboarding Report Export action (see `fund_admin_exchange.md`) |

### How to Build It

**Not a new model** — extend the existing pipeline:

```ruby
# KycOnboardingAgent — add three new steps after check_expiry_status
step :check_us_tax_form_status       # reads json_fields["form_status"]; blocks if missing or expired
step :check_subscription_doc_status  # reads ESignature records on commitment documents
step :check_investor_qualification   # reads InvestorQualification records for this investor + fund
step :auto_complete_onboarding       # sets onboarding_completed = true when all clear + verified
```

The `SupportAgentReport` badge gains three US-specific cards (Tax Form, Subscription, Qualification). The Onboarding Report dashboard gains a summary bar and a batch "Admit All Ready" action. A `ClosingBinderJob` fires when `onboarding_completed` flips to `true`, collecting all investor documents into a ZIP stored on the commitment.

**Build estimate: ~8 days** vs. 4–6 weeks for a new model hierarchy.

> See [`docs/features/us_gtm/closing_room.md`](us_gtm/closing_room.md) for full agent step specs, the `auto_complete_onboarding` logic, and binder job design.

---

## 6.2 Capital Calls and Distribution Notices

### The Concept

Capital calls and distribution notices are the most operationally sensitive communications in a private fund. Errors — wrong amounts, wrong bank details, wrong investors — create serious operational and legal problems. CapHive should make the workflow from decision to delivery to reconciliation tight, auditable, and nearly automatic.

### What CapHive Has Today vs. What the US Workflow Requires

Legend: ✅ Exists · ⚠️ Partial / needs extension · ❌ Not built

#### Capital Calls

| Capability | Expected | CapHive Today | Delta |
|------------|----------|---------------|-------|
| Per-investor amount calculation (% of commitment) | Compute each LP's call amount from their committed capital | ✅ Multiple call bases: % of commitment, fixed amount, account entry basis, upload | None — solid foundation |
| Fund close equalization | Later-close investors called at higher % to equalize with first-close | ✅ Per-close call percentages supported; different % per fund close on same call | None |
| Multi-currency call amounts | Investors committed in different currencies get amounts in their folio currency | ✅ Full multi-currency support; folio currency tracked separately from fund base currency | None |
| Call fees / management fee bundling | Bundle management fees or other charges into a capital call | ✅ Call fees with account-entry-based computation per investor | None |
| Called amount vs. committed amount tracking | Know what has been called vs. what is still uncalled per investor | ✅ `called_amount` and `collected_amount` tracked per commitment | None |
| Unfunded commitment as a tracked field | Surface unfunded commitment (committed − called) as a named field on the notice | ⚠️ Derivable from commitment data but not a named stored field or displayed per-investor metric | Needs to be a first-class computed field surfaced on notices, LP portal, and commitment views |
| Single-approver workflow before sending | Require sign-off before notices are sent | ✅ Capital call must be approved before notices are sent; `approved_by_user` recorded | None for single approver |
| Dual / maker-checker approval workflow | Require two separate approvers before a call is sent | ❌ Only one approver role; no maker-checker or dual sign-off mechanism | Needs a second-approver requirement configurable per fund — important for fraud control on large calls |
| Notice document generation per investor | Generate a personalised call notice for each LP | ✅ Document generated per remittance using a "Call Template"; one per KYC option also available | None — generation works; template content (wire instructions, fraud language) is up to the template author |
| Fund bank account / wire instructions in notice | Embed the fund's verified wire instructions in each notice automatically | ⚠️ No "fund bank account" object — wire instructions must be manually included in the notice template | Need a fund bank account record that is referenced in notice generation; "verified" state important for fraud control |
| Fraud warning language | Standard anti-fraud language on every notice advising LPs to verify wire details | ⚠️ Can be included in the notice template manually | No system-enforced fraud warning; no version control on warning language; risk of omission |
| Notice sent / reminder tracking | Know which LPs have been notified and which have received reminders | ✅ Notification log per remittance; `Send Reminder` re-sends to Pending/Overdue investors | None |
| Portal view / document open tracking | Know whether the LP has opened their call notice in the portal | ⚠️ Document `viewed_bies` tracks who has opened a document and when | Viewing is tracked per-document — not surfaced as a "LP has viewed their notice" status on the call management screen |
| Payment status lifecycle | Track Pending → Overdue → Paid / Overpaid | ✅ Full status lifecycle with background job moving Pending → Overdue on due date | None |
| Manual payment reminders to overdue investors | Re-send notice to LPs who haven't paid | ✅ `Send Reminder` button on call and individual remittance pages | None |
| Default interest on overdue remittances | Calculate penalty interest for late payment per LPA terms | ❌ Not in the system | No default interest calculation; overdue is tracked but penalty is not computed |
| Import call amounts from external source | Accept call amounts from fund administrator's file | ✅ "Upload" call basis accepts a spreadsheet with per-investor amounts | None |
| Reconciliation export for fund administrator | Export a structured file of expected vs. received payments | ⚠️ Report Builder can produce commitment/remittance data; no dedicated reconciliation export format | No purpose-built reconciliation export; needs a standard format matched to common fund admin systems |
| Skip call notice for specific investor | Exclude one investor from notice without removing them from the call | ✅ `skip_call_notice` flag on commitment | None |

#### Capital Distributions

| Capability | Expected | CapHive Today | Delta |
|------------|----------|---------------|-------|
| Per-investor distribution amount calculation | Allocate total distribution among investors based on ownership or units | ✅ Multiple distribution bases: unit-based, account-entry-based, upload | None |
| Distribution fees (taxes, expenses, reinvestment) | Apply per-investor adjustments to gross payable | ✅ Account-entry-based distribution fees compute net vs. gross payable per investor | None |
| Net payable vs. gross payable per investor | Separate the gross distribution from the LP's actual take-home after deductions | ✅ `net_payable` and `gross_payable` computed per payment | None |
| Approval workflow before sending | Require sign-off before distribution notices are sent | ✅ Distribution must be approved; `approved_by_user` recorded | Same dual-approval gap as capital calls |
| Distribution notice document generation | Generate a personalised distribution notice per investor | ✅ Document generated per payment using a distribution notice template | None for document generation; same wire instruction / fraud warning gap as capital calls |
| Payment completion tracking | Mark individual payments as sent to each LP | ✅ Per-payment `completed` flag; bulk "Mark All Completed" action | None |
| Notification on payment completion | Email LP when their distribution has been sent | ✅ `send_notification_on_complete` setting triggers email on completion | None |
| Portal and document view tracking | Know whether LP has opened their distribution notice | ⚠️ Same as capital calls — document viewing tracked per-document but not surfaced as distribution-level status | Same delta as capital calls |
| Recallable distribution flag | Mark a distribution as recallable; track if GP has called it back | ❌ Not in the system | No recallable flag; no mechanism to track whether a prior distribution is within the recall window; affects unfunded commitment calculation |
| Face value for redemption (return of capital) | Track the principal-return portion of a distribution separately from income | ✅ `face_value_for_redemption(start_date:, end_date:)` computed method on `InvestorKyc`; used in `KycDocGenerator` to surface principal-return portion on notices | None |
| Unit redemption on distribution | Redeem fund units when principal is returned to investors | ✅ Unit redemption linked to distribution with face value for redemption | None |
| Link distribution to portfolio company sale | Associate a distribution with the underlying realisation event | ✅ Portfolio investment sale can be linked to a capital distribution | None |
| Withholding tax per investor | Track and apply tax withholding for foreign investors on distributions | ⚠️ Distribution fees can model a tax deduction per investor via account entries | No structured withholding rate per investor tied to W-8 / FATCA classification; this is manual today |
| Reconciliation export for fund administrator | Export structured distribution data for fund admin | ⚠️ Same as capital calls — Report Builder available but no dedicated format | Same delta as capital calls |

### Use Case: 12% Capital Call for Acquisition

A PE fund calls 12% of commitments to fund a new acquisition. CapHive calculates investor-level call amounts including equalization for late-admitted investors, generates personalised notices, routes for approval, sends via portal and email, tracks delivery and payment status, and surfaces overdue investors for follow-up. A reconciliation export goes to the fund administrator showing expected vs. received payments.

**What works today:** Amount calculation, equalization, document generation, approval, notification, payment tracking, overdue flagging, reminders.

**What needs building:** Unfunded commitment as a named field on the notice, dual approval, fund bank account object for wire instruction embedding, fraud warning enforcement, portal-level notice view tracking, default interest, and the structured reconciliation export.

---

## 6.3 Tax Center and K-1 Delivery

### The Concept

Tax season is one of the most relationship-defining moments for a GP with their LPs. Missed K-1 deadlines, undeliverable emails, and LP questions that fall through the cracks create lasting friction. CapHive should make tax document delivery a managed, trackable, and delegatable workflow.

### What to Build

**Tax Center — Investor Portal**

```text
Investor Portal: Tax Center
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Tax Year 2025
  Federal K-1 ──────────────────── [Download] ✓ opened Feb 12
  State K-1 (California) ────────── [Download] ✓ opened Feb 14
  Tax Estimate Notice (Q3 2025) ─── [Download] ✓ opened Nov 2
  Extension Notice ─────────────── [Download] ✓ opened Apr 5

CPA Delegate Access
  John Accountant, CPA — cpa@smithtax.com — active

Tax Year 2024
  Federal K-1 ──────────────────── [Download] ✓
  State K-1 (California) ────────── [Download] ✓
  Corrected K-1 (issued Mar 15) ─── [Download] ✓
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Required capabilities:**
- Bulk K-1 upload and LP matching (by EIN/SSN or investor name)
- State K-1 delivery where applicable
- 1042-S delivery for foreign investors
- CPA/delegate access with time-limited permissions
- Tax year folders with version history
- Reissue and correction workflow with notification
- Download tracking and notification history
- Bulk delivery status dashboard for IR team

> Even if CapHive does not generate K-1s initially, managing their delivery, matching, notifications, CPA delegation, and evidence creates significant value during tax season.

---

## 6.4 Side Letter and LP Obligation Tracking

### The Concept

Side letters are operationally dangerous. Commitments made to specific LPs — reporting obligations, fee arrangements, co-investment rights, notice requirements, key person provisions — live in PDFs reviewed at closing and then largely forgotten. Until they aren't.

The LP Obligation Matrix converts side letters from passive PDFs into actionable operational tasks.

### What to Build

**LP Obligation Matrix**

| Investor | Clause Type | Obligation | Owner | Trigger | Next Action | Status |
|----------|-------------|-----------|-------|---------|-------------|--------|
| LP Alpha | Reporting | Quarterly ESG report within 45 days of quarter-end | IR | Q3 2026 close | Draft ESG report by Oct 14 | Upcoming |
| LP Beta | Fees | Management fee reduced to 1.5% during commitment period | Finance | Each fee calculation | Verify in next fee notice | Active |
| LP Gamma | Co-invest | Offer co-investments above $10M threshold | Deal Team | New deal > threshold | Review pipeline for trigger | Active |
| LP Delta | Notice | Notify within 5 business days of key person event | Legal | Key person change | N/A unless triggered | Standby |
| LP Epsilon | Reporting | Annual audited financials no later than 120 days | IR | Year-end | Target delivery by Apr 30 | Active |

**Required capabilities:**
- Side letter upload and investor-level tagging
- Clause extraction (initially manual; AI-assisted in Phase 3)
- Obligation categorization by type (reporting, fees, co-invest, notice, transfer, confidentiality)
- MFN comparison: identify if a clause offered to one LP should trigger rights for another
- Reminder workflows tied to fund calendar events
- Owner assignment and task escalation

> Side-letter intelligence is a genuine differentiator in US sales. Most GPs manage this in email and memory. When CapHive shows a complete obligation matrix in a demo, it creates immediate "we need this" responses.

---

## 6.5 Fund Administrator Collaboration

### The Concept

Most US fund managers already have a fund administrator. CapHive should be designed from the start to integrate with them rather than demand replacement. Winning a GP account often requires the fund administrator's sign-off or at minimum their cooperation.

### Integration Maturity Ladder

| Level | Type | What It Enables | Status |
|-------|------|-----------------|--------|
| 1 | XLSX export | Fund admin downloads investor master data and capital call exports | ✅ Exists (ReportBuilder + list view exports) |
| 2 | XLSX import | Fund admin uploads capital account data, K-1s, NAV files | ✅ Exists (ImportUpload + ImportFundDocsService) |
| 3 | API integration | Fund admin pulls investor records, capital events, and documents programmatically | ✅ Exists |
| 4 | Bidirectional workflow sync | Exceptions, approvals, and status updates flow both directions | Future |
| 5 | Shared dashboard | Fund admin and GP see the same real-time operating dashboard | Future |

> SFTP is not in scope. Fund admins use XLSX download/upload or the API.

**P1 target: Levels 1–3 with fund-admin-specific format presets.** The exchange mechanics exist; what's needed is `FundAdminProfile` (per-admin column mapping configuration) and `FundAdminExchangeRun` (audit log per exchange).

**Data the fund admin needs from CapHive:**
- Investor master data (names, entities, contacts, beneficial owners)
- Tax form status (W-9/W-8 received, form type, FATCA classification)
- KYC/KYB status and compliance evidence
- Bank instruction records with verification status
- Capital call/distribution delivery and payment status
- Document delivery evidence

**Data CapHive needs from the fund admin:**
- Capital account statements
- NAV data
- K-1 files for delivery
- Capital call wire confirmation

---

## 6.6 CRM and Fundraising Integration

### Fundraising-to-Onboarding Flow

The moment a prospect moves from "soft circle" to "investing" is where CRM hands off to CapHive. This transition should be automatic.

```text
CRM (Salesforce / HubSpot / Affinity / 4Degrees)
  │
  LP moves to "committed" stage
  │
  ▼
CapHive creates investor record
  │
  ├── pulls contact and entity data from CRM
  ├── sets commitment amount
  ├── determines investor type and eligibility rules
  ├── generates subscription packet
  └── sends portal invite to LP
  │
  ▼
Onboarding status syncs back to CRM
  │
  ├── "subscription docs sent"
  ├── "KYC pending"
  ├── "tax forms outstanding"
  └── "ready for closing"
```

**Key integrations to build:**
- Salesforce (required for enterprise buyers)
- HubSpot (most common for emerging managers)
- Affinity (common in VC)
- 4Degrees, DealCloud (common in PE)

---

# 7. Phase 3: AI-Native Differentiation

## Overview

> **Goal:** Use AI to reduce the manual work that consumes the most time in private fund workflows — document review, obligation extraction, exception handling, and investor servicing.

Phase 3 is where CapHive creates defensible distance from incumbents. AI features should be designed around one principle: **AI surfaces the issue, explains why, and routes it to the right human. AI never makes the final compliance or legal decision.**

**What "done" looks like for Phase 3:**
- CapHive's AI review catches at least 3 meaningful exceptions per subscription packet that would otherwise require manual review
- LP obligation matrix is populated from side letters with 90%+ accuracy before legal review
- LP service assistant handles 40%+ of routine investor questions without IR team involvement

---

## 7.1 AI Subscription Review

### The Problem

Fund administrators, GP operations teams, and counsel review subscription documents manually — checking for missing signatures, inconsistent names, tax form mismatches, and eligibility gaps. For a 20-LP closing, this can take days. For a 100-LP institutional closing, it is weeks of manual work.

### What CapHive's AI Does

```text
Completed subscription packet (all documents, questionnaire responses, forms)
        │
        ▼
AI Review Engine
        │
        ├── Missing signatures / initials ──────────────────▶ flag
        ├── Legal name inconsistency (sub doc vs. tax form) ─▶ flag with comparison
        ├── Entity type mismatch (LLC listed as individual)  ─▶ flag
        ├── Tax form type wrong for stated investor status  ──▶ flag with correct form
        ├── Missing beneficial owners (entity threshold)   ───▶ flag
        ├── Accreditation answers incomplete or inconsistent ─▶ flag
        ├── ERISA investor count threshold approaching      ──▶ alert GP
        └── Questionnaire answer contradicts prior answers  ──▶ flag for review
        │
        ▼
AI generates exception summary for human reviewer
  "4 issues found: 2 require LP action, 1 requires counsel review, 1 is advisory"
        │
        ▼
Human reviewer approves, rejects, or escalates each item
```

### What the AI Does Not Do

- It does not approve investors
- It does not make eligibility determinations
- It does not override legal exceptions
- Every AI flag is a recommendation, not a decision

---

## 7.2 LPA and Fund Document Intelligence

### The Problem

LPAs, PPMs, side letters, and management agreements contain the rules that govern every fund action — but they are 150-page PDFs that no one rereads after the fund closes. When a question arises (Can we make this distribution? What's the notice period for a key person change? Does this LP have co-invest rights?), the answer is in a document that requires a lawyer to find it.

### What to Build

**Fund Document AI — Term Extraction**

```text
Document: Limited Partnership Agreement — Acorn Growth Partners II

EXTRACTED TERMS (AI-assisted, reviewed by counsel)

Management Fee
  Rate: 2.0% of commitments during commitment period
  Step-down: 1.5% after investment period ends
  Source: Section 7.1(a)

Preferred Return
  Rate: 8% per annum, cumulative, compounded annually
  Calculation: on contributed capital
  Source: Section 8.2(b)

Carried Interest
  Rate: 20%
  After: return of capital + preferred return
  GP catch-up: 50/50 until GP receives 20% of total profits
  Source: Section 8.2(c)

Capital Calls
  Notice period: minimum 10 business days
  Exception: 3 business days for emergency expenses (defined in Section 1)
  Maximum single call: 25% of commitment
  Source: Section 6.3

Transfer Restrictions
  GP consent required for all transfers
  Transfers to affiliates: consent not unreasonably withheld
  Right of first offer: applies to third-party transfers
  Source: Section 11.2

Key Person Provisions
  Key persons: [Names]
  Trigger event: departure of any 2 key persons within 24 months
  Effect: suspension of new investment activity
  Source: Section 5.4
```

**Product principle:** Every AI-extracted term must cite the document section. If the AI cannot find a provision with confidence, it says so rather than guessing.

---

## 7.3 LP Obligation AI

### What to Build

Side letters are uploaded. AI extracts obligations, classifies them by type, compares them across investors for MFN relevance, and creates a draft obligation matrix for legal review.

```text
Side letters uploaded (one per LP or multiple per LP across fund vintages)
        │
        ▼
AI extraction
  ├── identifies clause types (reporting, fee, co-invest, notice, transfer, confidentiality)
  ├── extracts obligation text and trigger conditions
  ├── identifies parties and ownership of each obligation
  └── flags clauses that may trigger MFN rights for other LPs
        │
        ▼
Legal team reviews extracted matrix
  ├── approves each extracted obligation
  ├── corrects AI misclassifications
  └── adds obligations the AI missed
        │
        ▼
Approved obligations become active tasks and reminders in CapHive
        │
        ▼
CapHive reminds obligation owners when triggers approach
```

---

## 7.4 AI Investor Service Assistant

### The Problem

LP service questions are predictable, repetitive, and time-consuming for IR teams. During capital call season and tax season, the same 10 questions come from 80% of the LP base. Each answer requires navigating multiple systems.

### What the AI Handles

The assistant answers investor questions using only data and documents the investor is authorized to see:

- "What is my unfunded commitment to Growth Fund II?"
- "Can you send me the drawdown notice from the April call?"
- "How much have I received in distributions since inception?"
- "Where is my K-1 for tax year 2024?"
- "Who can I add as a delegate to my tax documents?"
- "What bank account do you have on file for distributions?"
- "What documents are still outstanding from my onboarding?"

### Safety Architecture

| Requirement | Implementation |
|-------------|----------------|
| Data isolation | Investor sees only their own data, no matter how the question is phrased |
| Permission enforcement | Role-based access checked before every response |
| Source citation | Every data point cited to its source record (not just narrated) |
| Sensitive request escalation | Bank, legal, and tax-related changes escalated to human IR team |
| Interaction logging | Every AI conversation logged and available for GP/admin review |
| GP override | GP can mark any question type as requiring human response |

---

## 7.5 Compliance Evidence AI

### The Problem

Compliance in private funds is not just doing the right thing — it is *proving later that you did it*. Auditors, SEC examiners, prime brokers, and institutional LPs ask for evidence. Assembling that evidence from email threads, shared drives, and multiple systems takes weeks.

### What to Build

**AI Compliance Evidence Binder** — auto-generated per investor, updatable on demand

```text
Compliance Evidence Binder
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Investor:  Meridian Capital Partners LLC
Fund:      Acorn Growth Partners II
Status:    Approved — with one noted exception
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ONBOARDING EVIDENCE
  ✓ Subscription agreement — signed Apr 3, 2025 — DocuSign cert #XYZ
  ✓ Investor questionnaire — completed Apr 3, 2025
  ✓ GP countersignature — Apr 8, 2025

TAX DOCUMENTATION
  ✓ W-9 — received Apr 3, 2025 — TIN verified — expires: n/a
  ✓ FATCA classification: US Person — no withholding required

IDENTITY & ENTITY VERIFICATION
  ✓ KYB completed — Middesk — Apr 5, 2025 — passed
  ✓ Beneficial owner (>25%): Jane Meridian — identity verified — Persona
  ✓ Entity sanctions screening — ComplyAdvantage — Apr 5, 2025 — clear
  ✓ Jane Meridian — individual sanctions — clear
  ✓ Jane Meridian — PEP screening — clear

BANK VERIFICATION
  ✓ Bank account — JPMorgan Chase ****4521 — verified Apr 4, 2025 — Plaid
  ✓ Wire instructions — on file — reviewed by Operations Apr 6, 2025

INVESTOR ELIGIBILITY
  ✓ Accredited investor — confirmed by questionnaire
  ✓ Qualified purchaser — confirmed ($30M in investments)
  ✗ Formation document: 4 years old — preferred threshold is 3 years
      EXCEPTION: Approved by Legal (Marcus Reeves) on Apr 7, 2025
      Reason: no material change in entity structure; fresh filing not warranted
      Evidence: approval email archived in exception log

SIDE LETTER
  ✓ Side letter executed Apr 8, 2025 — stored in investor record
  ✓ Obligations extracted and added to LP Obligation Matrix

NEXT REFRESH SCHEDULE
  AML/sanctions: Annual — next Apr 2026
  KYC/KYB: Every 3 years — next Apr 2028
  Tax form: On status change
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

# 8. Phase 4: Ecosystem and Partnerships

## Overview

> **Goal:** Embed CapHive into the US private funds operating stack through partner relationships, integration marketplace, and channel distribution.

Phase 4 shifts CapHive from a standalone product to a platform. Partnerships drive scale; integrations drive stickiness.

---

## 8.1 Partner Strategy

### Motion 1: Fund Administrator Partnerships (Highest Priority)

**The pitch to fund admins:**
> "CapHive helps you service more GP clients without adding headcount. We handle investor onboarding, subscription review, investor communications, document management, and AI evidence — you retain all accounting, tax, and capital administration work."

**Why fund admins say yes:**
- Their GP clients are demanding better onboarding and LP experiences
- They cannot afford to build this themselves
- A white-labeled CapHive portal becomes a competitive differentiator for the fund admin
- Per-client licensing creates a revenue-sharing model that aligns incentives

**Activation steps:**
1. Identify 5 mid-market fund administrators ($5B–$50B AUM served) as targets
2. Warm intro through shared GP clients or industry connections
3. Propose a pilot: run one GP client's next closing through CapHive, white-labeled under the fund admin's brand
4. If the pilot succeeds, negotiate a reseller or co-sell agreement

### Motion 2: Fund Counsel Referrals

**The pitch to law firms:**
> "CapHive gives your fund clients a structured environment for subscription documents, closing workflows, side-letter obligations, and legal exceptions — reducing the back-and-forth you manage by email."

**Why law firms say yes:**
- They spend enormous billable time on administrative closing mechanics
- CapHive reduces exceptions and back-and-forth, making their clients happier
- Side-letter extraction and closing binder generation save real time

**Activation steps:**
1. Build a counsel-facing closing room view that gives counsel visibility and control
2. Offer co-branded fund document templates to 3–5 target law firms
3. Present at fund formation-focused CLEs and bar association events

### Motion 3: Emerging Manager Associations and Accelerators

**The pitch:**
> "CapHive gives emerging managers institutional-grade fund operations from day one — without hiring a 5-person back office."

**Activation paths:**
- NVCA, AIC (American Investment Council) membership and events
- First Close, Visible Hands, and other emerging manager programs
- VC-backed accelerators that launch emerging managers (e.g., Kauffman Fellows, Management Leadership for Tomorrow)

### Motion 4: Integration Partners

| Category | Priority Partners | Integration Value |
|----------|------------------|------------------|
| E-signature | DocuSign, Dropbox Sign | Subscription execution; countersignature workflow |
| Bank verification | Plaid, MX | Account ownership verification |
| KYC/KYB | Persona, Middesk | Identity and entity screening |
| Sanctions/AML | ComplyAdvantage | Investor screening; periodic refresh |
| CRM | Salesforce, HubSpot, Affinity | Prospect-to-investor handoff |
| Fund accounting | Allvue, FundCount | Data exchange; capital activity sync |
| Investor portals | Juniper Square, Arch | Optional coexistence; data sync |
| Tax workflow | K1x, fund admin tax teams | K-1 import and delivery |
| Data rooms | Intralinks, Box, Datasite | Pre-close diligence to post-close onboarding |

---

# 9. Product Architecture

## 9.1 Module Map

```text
CapHive US Platform

Core Data
  ├── Investor & Entity Master (individuals, entities, nested beneficial owners)
  ├── Fund & Vehicle Master (LP, LLC, SPV, feeder, blocker, parallel)
  └── Contact & Relationship Model (authorized signatories, delegates, counsel, admin)

Onboarding Workflow
  ├── Subscription Packet Engine (form routing, pre-fill, e-sign integration)
  ├── Investor Qualification Engine (configurable rules per fund and exemption)
  ├── Tax Form Wizard (W-9/W-8 logic, FATCA classification, expiration tracking)
  ├── KYC/KYB & Compliance Evidence Binder (providers, results, exception log)
  └── Bank Instructions Control Center (verification, fraud controls, approvals)

Fund Operations
  ├── Closing Room (readiness dashboard, action tracking, binder generation)
  ├── Capital Call & Distribution Notices (generation, approval, delivery, tracking)
  ├── Tax Center (K-1 delivery, CPA delegation, notification history)
  ├── Side Letter & LP Obligation Matrix (upload, extraction, reminders, owners)
  └── Fund Admin Exchange Layer (export/import, data schema, API)

LP Experience
  ├── Investor Portal (documents, notices, statements, tax, capital activity)
  ├── LP Assistant (AI-powered investor service, authorized data only)
  └── Communication Timeline (all interactions, notices, deliveries, history)

AI Intelligence Layer
  ├── AI Subscription Review (exception detection, flag generation, routing)
  ├── LPA / Fund Document Intelligence (term extraction, source-cited answers)
  ├── LP Obligation AI (side letter extraction, obligation matrix, MFN detection)
  └── Compliance Evidence AI (binder generation, gap detection, audit prep)

Integrations
  ├── E-signature (DocuSign, Dropbox Sign, Adobe, PandaDoc)
  ├── Bank verification (Plaid, MX, Finicity)
  ├── KYC/KYB (Persona, Middesk, Socure)
  ├── Sanctions/AML (ComplyAdvantage, LSEG)
  ├── CRM (Salesforce, HubSpot, Affinity, 4Degrees)
  ├── Fund accounting (Allvue, FundCount, QuickBooks)
  └── Data rooms (Box, Dropbox, Intralinks)

Platform Foundation
  ├── Role-Based Access Control (fund-level, investor-level, action-level)
  ├── Audit Logs (every action, every document access, every approval)
  ├── Security (MFA, SSO/SAML, encryption at rest/transit, key management)
  └── Compliance (SOC 2 roadmap, data retention, GDPR/CCPA handling)
```

## 9.2 Core Data Models

### Investor Entity

```text
Investor Entity
  ├── Legal name (as it appears on tax forms)
  ├── Investor type (individual, trust, LLC, LP, corporation, etc.)
  ├── Tax classification (US person, FATCA type)
  ├── Formation jurisdiction
  ├── EIN / TIN / foreign tax ID (encrypted)
  ├── Contacts (authorized signatories, delegates, CPA, counsel)
  ├── Beneficial owners (>25% and control persons)
  ├── Bank instructions (with verification status and approval history)
  ├── Tax forms (W-9/W-8; version, date, expiration)
  ├── KYC/KYB evidence (provider results, reviewer approvals, exception log)
  ├── Subscription documents (per fund, per closing)
  ├── Side letters (per fund, with extracted obligation status)
  ├── Commitments (per fund; committed, called, distributed, unfunded)
  └── Portal users (LP logins, delegate access, CPA access)
```

### Fund Vehicle

```text
Fund Vehicle
  ├── Legal entity name and jurisdiction
  ├── Fund type (PE, VC, credit, real estate, hedge, other)
  ├── Exemption type (3(c)(1), 3(c)(7), other)
  ├── GP entity and management company
  ├── Service providers (fund admin, counsel, auditor, tax advisor)
  ├── Bank accounts (fund bank, distribution account)
  ├── Subscription templates (counsel-approved, versioned)
  ├── Investor eligibility rules (QP, AI, QC, ERISA flags)
  ├── Reporting templates and calendar
  └── Capital call and distribution notice templates
```

---

# 10. Security and Enterprise Readiness

## Why This Is a Sales Issue, Not Just an Engineering Issue

US private fund buyers will ask about security before they trust CapHive with investor tax IDs, bank details, subscription documents, and compliance records. Security is not a backend detail — it is a sales enabler. Every enterprise sales cycle includes a vendor risk review. Being prepared shortens deals and eliminates objections.

## Required Capabilities

| Area | Requirements | Priority |
|------|-------------|----------|
| Authentication | MFA required; SSO/SAML for enterprise; session timeouts | P0 |
| Authorization | Role-based access; fund-level isolation; investor-level permissions | P0 |
| Audit logs | Every user action logged; document access logged; approval events logged | P0 |
| Data security | Encryption at rest (AES-256); encryption in transit (TLS 1.2+); encrypted field storage for TINs/bank data | P0 |
| SOC 2 | SOC 2 Type I readiness in Year 1; Type II in Year 2 | P1 |
| Privacy | Data retention policy; deletion workflows; subprocessor list; DPA available | P1 |
| Secure links | Expiring document links; download controls; IP allowlists where needed | P1 |
| Incident response | Documented plan; breach notification process; backup and recovery | P1 |

## The Vendor Risk Review Checklist

When an enterprise buyer or fund administrator asks for a security questionnaire, CapHive should be prepared to answer:

- Where is data hosted? (AWS / GCP region; US data residency option)
- Who can access customer data at CapHive? (SOC 2 covers this)
- How are TINs and bank details protected? (field-level encryption)
- What is the audit log retention policy?
- Has CapHive completed a penetration test?
- What is the disaster recovery RTO/RPO?
- Is a Data Processing Agreement available?

Prepare these answers before the first enterprise sales cycle reaches the security review stage.

---

# 11. Feature Prioritization

## Build Now vs. Build Later

| Feature | Priority | Rationale |
|---------|----------|-----------|
| US entity and investor data model | P0 | Foundation for everything |
| E-signature integration | P0 | Required for subscription execution |
| W-9/W-8 tax form collection | P0 | Core US onboarding requirement |
| KYC/KYB and sanctions | P0 | Required for investor diligence |
| Bank instruction verification and controls | P0 | Fraud risk + capital call prerequisite |
| Investor qualification engine | P0 | Private placement compliance |
| Investor portal document center | P0 | Minimum LP experience |
| Capital call and distribution notices | P0 | Core fund operation |
| Closing Room | P1 | High operational value; strong demo moment |
| Tax Center / K-1 delivery | P1 | Critical for IR team adoption |
| Fund admin exchange layer | P1 | Required for ecosystem adoption |
| CRM integration | P1 | Fundraising-to-onboarding handoff |
| Side letter obligation matrix | P1/P2 | Start manual; layer AI on top |
| AI subscription review | P2 | Differentiator; requires base workflow first |
| AI LPA/side-letter extraction | P2 | Strong competitive differentiation |
| Payment initiation (ACH debit) | P2/P3 | Higher compliance risk; start with verification |
| Regulatory filing engine (Form PF, ADV) | P3 | Complex; start with data readiness only |
| Full fund accounting | P3 | Avoid direct competition with incumbents early |

---

# 12. Implementation Roadmap

## Phase 1: Months 1–3 — US Readiness Sprint

**Goal:** CapHive can demo a complete US investor onboarding journey from prospect to signed subscription package.

### Product
- US terminology, entity types, and fund structure data model
- W-9/W-8 data model and form collection workflow
- Investor qualification fields (AI, QP, QC, ERISA, 3(c)(1) count)
- Bank instruction object with verification status lifecycle
- Capital call and distribution notice templates for US structures
- Document categories for US funds (subscription docs, formation docs, tax forms, KYC evidence)

### Integrations
- One e-sign provider (DocuSign or Dropbox Sign — pick one, do it well)
- One bank verification provider (Plaid recommended for breadth)
- One KYC/KYB provider (Persona recommended for flexibility)
- One sanctions provider (ComplyAdvantage recommended for private funds coverage)

### Security
- MFA enforced for all users
- Role-based access control review and tightening
- Audit log coverage for key actions
- Encrypted field storage for TINs and bank data
- Data retention policy drafted

**Milestone:** First 3 paying customers live on a real closing.

---

## Phase 2: Months 4–6 — Onboarding and Closing

**Goal:** CapHive supports a real US fund closing with multiple investor types, exceptions, and counsel/admin collaboration.

### Product
- Subscription Packet Engine (full workflow from data capture to countersigned archive)
- Tax Form Wizard (complete W-9/W-8 routing and FATCA classification)
- Investor Qualification Engine (configurable per fund)
- Compliance Evidence Binder (per investor; exception log; reviewer approvals)
- Closing Room (readiness dashboard; action owners; binder generation)
- Manual review queues for operations, counsel, and admin
- Exception management workflow

### Integrations
- Production e-sign workflow with countersignature support
- Production KYC/KYB with exception handling
- Production bank verification with change controls
- CRM import/export (Salesforce and HubSpot to start)

**Milestone:** 5–10 customers; first fund administrator partnership conversation.

---

## Phase 3: Months 7–12 — Fund Operations

**Goal:** CapHive becomes useful after onboarding — for ongoing fund operations, investor servicing, and fund administrator collaboration.

### Product
- Capital call and distribution notice generation, approval, and delivery
- Payment status tracking and reconciliation export
- Tax Center with K-1 delivery, CPA delegation, and notification history
- Side Letter and LP Obligation Matrix (manual entry; AI extraction in Phase 4)
- Fund Admin Exchange Layer (XLSX export with fund-admin format presets; API access)
- Bank instruction change controls with dual-approval workflow
- Investor portal improvements: communication timeline, document history, capital activity
- Reporting templates for quarterly and annual LP communications

### Integrations
- Fund admin export/import: XLSX format presets per admin; API for tech-forward admins
- Data room integration (Box or Dropbox to start)
- CRM sync expanded (push onboarding status back to CRM)
- Second e-sign provider (Adobe or PandaDoc)

**Milestone:** 20–30 customers; first reference customer willing to be named publicly.

---

## Phase 4: Year 2 — AI and Ecosystem Differentiation

**Goal:** CapHive becomes a differentiated AI-native operating system for private fund workflows.

### Product
- AI subscription review (exception detection, consistency checking, routing)
- AI side-letter extraction (obligation identification, MFN analysis, matrix population)
- AI LPA intelligence (term extraction, source-cited answers)
- AI investor service assistant (LP-facing; authorized data only)
- AI compliance evidence binder (auto-generation, gap detection)
- Portfolio KPI extraction and reporting intelligence
- Cross-fund investor dashboard (for GPs managing multiple vehicles)

### Partnerships
- First fund administrator partnership (white-labeled or co-sell)
- 3–5 law firm referral partnerships active
- Integration marketplace launched (KYC, e-sign, CRM, bank, fund admin)
- Conference presence (ILPA, NVCA, AIC)

**Milestone:** 50+ customers; first $1M ARR; fund administrator partnership generating pipeline.

---

# 13. End-to-End Scenario: Mid-Market PE Firm, Third Fund Cycle

This scenario shows what CapHive looks like in practice for the primary ICP — a $1.5B PE firm managing multiple fund vehicles with real complexity.

## The Situation

Ridgeline Capital Partners manages $1.5B across three vehicles: Ridgeline Fund III (their flagship $900M PE fund), Ridgeline Opportunities Fund I (a $250M co-investment vehicle), and Ridgeline Credit Fund I ($350M credit strategy). They have 280 LPs across all vehicles. Their back office is 12 people: COO, CFO, 3 finance associates, 3 IR associates, 2 operations analysts, and 2 legal/compliance staff.

Their current stack: Salesforce, FIS Investran for fund accounting, DocuSign standalone, Google Drive for shared docs, Intralinks for data room. Their fund admin is Alter Domus.

**The problem:** Each new closing takes 8–12 weeks instead of the 4–6 weeks their LPs expect. Side letter obligations for 40+ investors across 3 funds are tracked in a spreadsheet owned by one person. Three LPs received the wrong capital call amounts in the last year due to Excel formula errors. Annual compliance evidence assembly for their SEC exam took 6 weeks of legal team time.

**Why they look at CapHive:** Their COO attended an ILPA conference panel on AI in fund operations. One of CapHive's reference customers gave a 10-minute talk. The COO emails CapHive that night.

## Step 1: Discovery and Fund Configuration

CapHive's implementation team spends two weeks configuring:
- Three fund vehicles with correct LP rosters, commitment amounts, and unfunded balances
- Co-invest vehicle structure with overlapping LP relationships from the flagship fund
- Investor types across 280 LPs: US individuals, family office LLCs, institutional LPs, 8 foreign investors (W-8BEN-E), 2 foreign funds (W-8IMY)
- 40+ side letters tagged to investor records
- Salesforce sync for prospect-to-investor handoff
- Alter Domus export format for capital activity reconciliation

## Step 2: LP Obligation Matrix Population

CapHive's AI processes 40 side letters. Within 72 hours, a draft LP Obligation Matrix is ready for legal review:

```text
LP Obligation Matrix — Ridgeline Capital Partners
Vehicles: Fund III, Opportunities Fund I, Credit Fund I

REPORTING OBLIGATIONS (12 active)
  Silver Lake Endowment — Fund III
    Quarterly ESG impact report within 45 days of quarter-end
    Annual carbon footprint disclosure
    Owner: IR — due Oct 14 / Jan 14 / Apr 14 / Jul 14
    Status: Q2 2026 due in 6 weeks — ⚠ Upcoming

  Teachers' Retirement of LA — Fund III
    Annual financial statements no later than 120 days after year-end
    Side-by-side performance attribution vs. benchmark on request
    Owner: CFO — due Apr 30 annually
    Status: On track

FEE ARRANGEMENTS (8 active)
  Meridian Sovereign Fund — Fund III + Opportunities
    Management fee: 1.25% (vs. standard 1.75%)
    Applies across both vehicles; requires fee notice confirmation each period
    Owner: Finance — verify on each fee notice
    Status: Active — needs verification trigger

CO-INVESTMENT RIGHTS (6 active)
  Pacific Crossroads Family Office — Fund III
    Right of first offer on co-invest opportunities > $15M
    7 business days to respond
    Owner: Deal Team — triggered on each qualifying investment
    Status: Active — last triggered Deal A on Apr 2; no response required

MFN ANALYSIS
  3 clauses in Fund III side letters may trigger MFN rights for other LPs
  Legal review required: Clause 4.2(b) — reporting obligation in Meridian
  side letter appears to be more favorable than standard. Teacher's and 2
  others may have MFN rights that require matching.
  ⚠ Action required: Legal to review and confirm or remediate.
```

Legal reviews, approves 36 obligations, corrects 3 AI misclassifications, and adds 2 obligations the AI missed. Total legal review time: 4 hours, compared to 3–4 weeks to build this from scratch.

## Step 3: Next Fund Closing (Weeks 3–8)

Ridgeline is admitting 8 new LPs to Fund III in a second close. CapHive manages the full workflow:

**Week 3:** Subscription packets sent to 8 LPs. CapHive determines each LP's required documents: 6 need W-9, 1 needs W-8BEN-E (Cayman family office), 1 needs W-8IMY (offshore fund-of-funds).

**Week 4–5:** LPs complete questionnaires, sign documents, and submit tax forms. CapHive runs KYC/KYB via Persona and Middesk. Sanctions screening via ComplyAdvantage. Bank instruction verification via Plaid.

**Week 6:** Closing Room status:

```text
Closing: Ridgeline Fund III — Second Close — Target: [date]

Ready to close:     6 investors    $87M
Blocked:            1 investor     $15M   ← Cayman entity W-8IMY incomplete
Pending:            1 investor     $8M    ← Side letter negotiation in progress

BLOCKED — Lakewood Offshore Partners Ltd
  Tax form: W-8IMY — withholding statement missing; GIIN not confirmed
  KYC/KYB: ✓ complete
  Side letter: N/A
  Action: Operations → contact Lakewood tax counsel for FATCA cert
  Assigned: Sarah Chen — due [date]
```

**Week 7:** Legal reviews 2 side letters. One triggers an MFN check against 3 existing LPs — CapHive flags this automatically. Counsel confirms the MFN provisions are not triggered by the new terms.

**Week 8:** GP countersigns. Closing binder generated: 8 fully executed subscription agreements, KYC evidence, tax forms, bank verification records, exception approval log. Alter Domus receives the investor data export. Close completed in 6 weeks vs. the prior 10-week average.

## Step 4: Capital Call — Error-Free

The Fund III investment committee approves a 12% capital call for a new acquisition.

CapHive calculates investor-level amounts automatically from commitment data and unfunded balances, including equalization for the second-close investors. The COO reviews the draft call on screen before approval:

```text
Capital Call Draft — Ridgeline Fund III
Call date: [date]   Amount: 12% of commitments
Total: $108M

INVESTOR-LEVEL AMOUNTS (sample)
  Silver Lake Endowment     $50M commitment → $6.0M call
  Meridian Sovereign Fund   $75M commitment → $9.0M call
  Lakewood Offshore Ltd     $30M commitment → $3.6M call (2nd close equalization applied)
  ...

Wire instructions: all verified ✓
Fraud holds: none ✓
Dual approval: CFO sign-off pending
```

CFO approves. Notices delivered via portal and email. 96 investors notified. Over the next 10 days: 91 wires received, 5 pending, 0 errors. The Excel formula error that caused 3 incorrect calls last year does not happen.

## Step 5: SEC Annual Exam Preparation

The SEC requests books and records for Fund III. The compliance team runs CapHive's compliance evidence export:

- 96 investor compliance binders generated in 4 hours
- Each binder shows: KYC results, KYB results, screening results, tax forms, subscription documents, exception log, approval history, bank instruction change log
- Side letter obligation matrix exported with evidence of fulfillment for each obligation
- Capital call and distribution notice delivery evidence for all 3 years

Compliance evidence assembly: 4 hours vs. 6 weeks the prior year.

---

# 14. Key Design Principles

These principles should guide every product decision in the US build. When there is a trade-off, return to these.

## 1. Workflow Before Storage

Do not build a database with a UI. Build a workflow engine that happens to store data. Every screen should drive someone toward a next action.

## 2. Evidence by Default

Every review, approval, verification, document delivery, and exception must create an evidence record automatically. Evidence should never require a separate step by the user.

## 3. Configurable by Counsel

US fund documents and investor eligibility rules vary by fund, strategy, and counsel preference. Templates, questionnaires, and eligibility logic must be configurable without engineering involvement.

## 4. Integrate, Then Replace

Enter the US market by fitting into the existing ecosystem. The first conversation with a GP should never require them to fire their fund administrator. Replace pieces only after CapHive has earned trust.

## 5. AI Assists, Humans Decide

AI should surface issues, explain reasoning, cite sources, and route decisions to the right person. Legal, compliance, and investor eligibility decisions require human approval. Always.

## 6. Treat Bank and Tax Data as Maximum Risk

Bank instructions, tax IDs, and identity documents get stricter controls, field-level encryption, approval workflows, and access logging than any other data type. A breach of these would destroy trust.

## 7. Make the LP Experience Simple

The investor's portal should show what they need to do next. Not the operational complexity behind the scenes. Operational detail is for GPs, fund admins, and IR teams.

---

# 15. Risks and Mitigations

| Risk | What Goes Wrong | Mitigation |
|------|----------------|------------|
| Fund administrator resistance | Fund admins see CapHive as a threat and advise GP clients against it | Position explicitly as complementary; build a fund admin version of the product; pursue admin partnerships actively |
| Underestimating US tax workflow depth | W-9/W-8/FATCA errors cause fund admin and LP complaints in year one | Hire a US tax operations advisor to validate the tax form logic before launch |
| Weak security posture at enterprise evaluation | Enterprise GP or institutional LP buyer's security review kills the deal | Prioritize SOC 2 readiness, penetration testing, and encrypted field storage before enterprise sales cycles begin |
| Too many integrations in parallel | Engineering is spread too thin; nothing is production-quality | One provider per category in Phase 1; depth before breadth |
| Hardcoded legal workflows | Product does not fit GP's counsel-specific templates; loses deals | Build a configurable template and rules engine, not hardcoded logic |
| AI overreach | AI makes eligibility or compliance decisions that create legal liability | Enforce human-approval gates on every AI flag; never auto-approve investors |
| Bank/payment fraud liability | CapHive is implicated in a distribution fraud event | Build fraud controls, dual approvals, and 72-hour holds before payment initiation; carry appropriate insurance |
| Sales cycle length | Enterprise GPs take 6–12 months to close; revenue lags | Focus Phase 1 on emerging managers with 4–8 week cycles; use enterprise pipeline to validate roadmap |
| Competitive undercutting | Juniper Square or Carta launches AI onboarding features | Stay 12 months ahead on AI depth; AI subscription review and LPA intelligence are hard to retrofit |

---

# 16. Recommended MVP Scope

## Must Include

1. US fund and entity data model (Delaware LP, LLC, SPV, feeder)
2. Subscription workflow (packet generation, pre-fill, routing)
3. E-signature integration (one provider; production-quality)
4. W-9/W-8 tax form collection and routing logic
5. Investor qualification questionnaire (configurable by fund)
6. KYC/KYB and sanctions integration (one provider; production-quality)
7. Bank instruction verification and change controls
8. Investor portal document center
9. Capital call and distribution notice generation and delivery
10. Closing Room with readiness dashboard
11. Audit logs and role-based access control
12. Admin/counsel review queues and exception management

## Do Not Include in MVP

1. Full payment initiation (ACH debit) — fraud risk; start with verification only
2. Full fund accounting — do not compete with Allvue/SS&C on day one
3. Regulatory filing engine (Form PF, Form ADV) — complex; start with data readiness
4. Every e-sign, KYC, and bank provider simultaneously — one each, done well
5. Fully autonomous AI approvals — always require human review
6. Self-serve onboarding without implementation support — too risky at launch

---

# 17. Launch Packaging

## Package 1: CapHive Operate (Core Tier)

**Target:** $500M–$2B GPs, 3–6 active vehicles, 150–400 investors
**Annual price:** $80K–$150K
**Includes:** Investor onboarding workflow, subscription packet engine, tax form collection (W-9/W-8, FATCA), KYC/KYB and sanctions integration, bank instruction controls, investor qualification engine, closing room, capital call and distribution notices, investor portal, tax center, fund admin exchange layer, CRM integration, audit logs and RBAC
**Positioning:** *The operating layer that handles your fund complexity — without requiring you to simplify your structure to fit the software.*

---

## Package 2: CapHive Intelligence (AI Tier)

**Target:** $1B–$5B GPs, 5–12 vehicles, 300–800 investors, high obligation complexity
**Annual price:** $150K–$250K
**Includes:** Everything in Operate + side letter obligation matrix, AI subscription review, AI compliance evidence binder, AI LP obligation extraction and MFN analysis, reporting templates, LP obligation calendar and reminders
**Positioning:** *Connect your documents, obligations, and investor records to an AI layer that does the review work — and creates compliance evidence automatically.*

---

## Package 3: CapHive Enterprise

**Target:** $3B–$10B+ GPs, complex multi-vehicle structures, 500+ investors, institutional LP base
**Annual price:** $250K–$500K
**Includes:** Everything in Intelligence + AI LPA and fund document intelligence, AI investor service assistant, cross-fund analytics dashboard, dedicated customer success manager, 99.9% SLA, custom integration support, on-site implementation support
**Positioning:** *The enterprise-grade AI operating system for private fund complexity at scale.*

---

## Package 4: CapHive for Fund Administrators

**Target:** Mid-market fund administrators serving 30–150 GP clients
**Annual price:** Custom; per-client licensing
**Includes:** White-labeled or co-branded portal; admin-facing dashboard across GP clients; subscription review; KYC/tax/bank status tracking; capital call and distribution workflows; AI document review; client-level audit logs
**Positioning:** *Service more GP clients at institutional quality — without scaling headcount linearly.*

---

# 18. Final Recommendation

CapHive should enter the US market targeting the buyers who have the most to gain from operational complexity handled well: technically sophisticated GPs managing $500M–$10B across multiple fund vehicles, who view technology as a competitive advantage and are actively looking for a better answer to the operational drag their current stack creates.

**The wedge:** AI-native workflow operations for complex private funds — handling the full lifecycle from investor onboarding through compliance evidence, LP obligation tracking, capital events, and investor servicing in a single, integrated layer.

**The first buyer:** A COO at a $1B–$3B PE or credit firm managing 3+ fund vehicles, 200+ LPs, and a growing side letter portfolio. They know their current process is not scaling. They are already using SaaS in other parts of their operation. They are ready to listen.

**The promise:** "Run your next full closing cycle through CapHive — including KYC, tax forms, bank verification, side letters, and the closing binder. Your operations team will never want to go back."

Once the foundation is credible at this complexity level, CapHive has three expansion paths:

1. **Up into larger firms** ($5B–$10B+) where enterprise-grade AI, compliance automation, and fund administrator integration create even stronger ROI
2. **Sideways into fund administrators** who want to offer modern onboarding and LP servicing infrastructure to their GP clients without rebuilding their core accounting stack
3. **Deeper into AI** — subscription review, side-letter extraction, LPA intelligence, compliance evidence generation — where the moat grows wider as the model learns from real fund documents and workflows

The strongest competitive position is not claiming CapHive replaces every incumbent. It is owning the connective tissue of private fund operations:

> **CapHive manages the complex, costly, error-prone middle of private fund operations — the workflows between the GP, LP, fund administrator, counsel, tax team, and bank. That is where the pain is largest, where AI creates the most leverage, and where no incumbent has built a modern, integrated answer for technically sophisticated buyers.**

That is the US wedge. Build it for complexity. Sell it to buyers who respect it. Evidence it rigorously. And expand from there.
