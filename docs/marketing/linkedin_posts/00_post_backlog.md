# Post Backlog — the commercially interesting ones

> **Status update.** All thirteen drafts in this folder are now published as blog
> articles under `public/website/`, linked from `blog.html` and listed in
> `sitemap.xml`. Regenerate them from the drafts with:
> `node docs/marketing/build_blog_from_drafts.mjs`
> (requires network access on first run — it fetches mermaid-cli to render the
> diagrams). Edit the markdown draft, re-run, done. The LinkedIn side is now a
> short blurb linking to the site, so the feed-teaser blocks in each draft are
> the blurb source; the HTML previews are no longer generated.
>
> **Two drafts must not be published as-is** — see their frontmatter:
> `07_lp_crm.md` (waiting on `feature/lp-crm-mvp` to merge) and
> `11_carry_net_irr.md` (needs compliance sign-off; it discusses performance).
> `08_data_rooms.md` contains a roadmap section that must stay clearly labelled
> as not-yet-built.


**Series:** "Fund Ops, Unstacked"
**ICP:** US GPs, $500M–$10B AUM, structurally complex, technically savvy (`docs/features/us_gtm.md` §2.1).
**Filter applied:** only features that map to a *buying trigger* — a loss the GP has already felt, a deal-blocker in diligence, or a capability a competitor can't ship quickly. Table-stakes features (document folders, task lists, dashboards, exports, 2FA) are excluded even where the guides are good, because they don't move a purchase decision.

---

## Already covered — publish these before writing anything new

| File | Feature | Persona | Status |
|---|---|---|---|
| `01_cash_flow_assistant_agent.md` | Cash Flow Assistant Agent | CFO | complete draft, not posted |
| `03_allocation_engine_fund_formulas.md` | Allocation Engine + Fund Formulas | CFO | ready for review |
| `04_kpi_portfolio_monitoring.md` | KPI collection → dashboards → agents | COO | ready for review |
| `02_customer_support_agent.md` | Customer Support Agent + AI judge | COO | spare draft — weakest of the four commercially; hold |

---

## The seven worth writing

### #4 — Side Letters Are Promises. Most Funds Track Them in a Folder.
- **Feature:** Side Letter Obligations Agent
- **Persona:** Director of Investor Relations
- **Business trigger:** An MFN clause or a missed reporting obligation surfaces during an LP's re-up diligence. This is unbudgeted, un-owned work at every GP in the ICP band, and there is no incumbent tool for it — most funds genuinely do keep executed side letters in a folder and rely on memory.
- **Why it converts:** extraction of obligations into tracked, owned, recurring duties is a claim no fund admin platform currently makes loudly. Named explicitly as this persona's message in the paid ads plan.
- **Guides:** `agents/side_letter_obligation_agent_user_guide.md`, `tasks_user_guide.md`, `document_management_user_guide.md`
- **Also use as:** the gated content offer for Stage 2 of the paid funnel.

### #5 — Your Fund Data, Inside Claude
- **Feature:** MCP server + entity-level LLM configuration (bring your own API key)
- **Persona:** The technically savvy GP — the ICP's own self-description
- **Business trigger:** Every GP is being asked by their IC or their LPs what their AI strategy is, and every vendor answer is "we added a chatbot." The differentiated answer is the inverse: the fund's data becomes a tool the GP's *own* AI client calls, under the GP's own keys and billing.
- **Why it converts:** it is the single hardest thing on this list for a competitor to copy, and it disqualifies the "AI wrapper" objection before it's raised. Own keys / own billing also neutralises the data-governance question in the same breath.
- **Guides:** `mcp_server/user_guide_mcp_connect_claude.md`, `llm_configuration_guide.md`, `ai_features_user_guide.md`, `integration.md`

### #6 — Before the Wire Leaves
- **Feature:** Capital distributions + Distribution Readiness Agent
- **Persona:** CFO / Controller
- **Business trigger:** Payment fraud and mis-payment are the two operational events that get a CFO fired. A rule-based gate on bank details, computed amounts, approved notices and KYC — checked immediately before funds move — sells against a fear the buyer already has.
- **Why it converts:** "bank-fraud controls" is already the CFO message in the ads plan; this is the product proof for it.
- **Guides:** `capital_distributions_user_guide.md`, `agents/distribution_readiness_agent_user_guide.md`, `fund_units_user_guide.md`

### #7 — The Capital Call That Shouldn't Have Gone Out
- **Feature:** Capital call lifecycle + Call Notice Agent pre-flight checklist
- **Persona:** CFO / Head of Fund Finance
- **Business trigger:** Every fund has retracted a notice. It's embarrassing in front of LPs, it's remembered, and nobody has a control for it — the checklist lives in someone's head.
- **Why it converts:** mirrors #1's "the agent that refuses to answer" — the product decision is what it *blocks*, not what it generates. Reads as operational maturity rather than automation hype.
- **Guides:** `capital_calls_user_guide.md`, `agents/call_notice_agent_user_guide.md`, `approvals_user_guide.md`

### #8 — "Show Me the IRR Net of Carry" — and Where the Number Came From
- **Feature:** Carry computations + fund ratios + ratio formulas + run templates
- **Persona:** CFO / Head of Fund Finance
- **Business trigger:** Gross IRR is marketing; net-of-carry is what an LP acts on and what an auditor questions. The commercial point is that the calculation is *configurable* — fee rebates, side pockets, fund-specific expenses fold in — so the GP doesn't have to simplify their economics to fit the software. That is the ICP's core complaint about incumbents.
- **Guides:** `carry_computations_user_guide.md`, `fund_ratios_user_guide.md`, `ratio_formulas_user_guide.md`, `fund_ratio_run_templates_user_guide.md`
- **Caution:** stay off #3's territory — that post is entry *generation*, this is performance *measurement*.

### #9 — One Fund in INR, One in EUR, One Report in USD
- **Feature:** Tracking currency
- **Persona:** CFO at a multi-jurisdiction GP
- **Business trigger:** A GP running funds in more than one currency is either restating by hand in a workbook or has already been burned by an FX-date inconsistency. Narrow audience, but the ones it fits have an acute, specific, expensive problem — and a short shortlist of vendors who handle it properly.
- **Why it converts:** highest intent-per-reader on the list. Best-qualified inbound of anything here.
- **Guides:** `tracking_currency_guide.md`, `capital_commitments_user_guide.md`

### #10 — Document-First KYC: Upload Three Files, Confirm, Done
- **Feature:** KYC Doc Extractor Agent + KYC Onboarding Agent
- **Persona:** COO / Head of Operations
- **Business trigger:** Onboarding drag delays closes. Investors abandon forms that ask them to retype what's already on their passport, and ops teams chase them. Inverting it — read documents first, pre-fill, confirm — is a time-to-close story, not an efficiency story.
- **Why it converts:** the second agent auditing the finished record for completeness and expiry is what makes it credible to a compliance-minded buyer rather than sounding like OCR.
- **Guides:** `agents/kyc_doc_extractor_agent_user_guide.md`, `agents/kyc_onboarding_agent_user_guide.md`, `investor_kyc_user_guide.md`

---

## Sequencing

**#4 (IR) → #5 (technical GP) → #6 (CFO) → #10 (COO) → #8 (CFO) → #7 (CFO) → #9 (CFO, niche)**

Personas alternate so the feed doesn't read as one long finance thread. If only two ever get written, write **#4 and #5** — they're the two nobody else can answer.

---

## Deliberately excluded, and why

| Feature | Guides | Why it's not a post |
|---|---|---|
| Workflow templates, approvals | `workflow_templates`, `approvals` | Real capability, but "approval workflows" is a checkbox on every RFP — it doesn't differentiate in a feed. |
| Document management, data rooms, e-signing, E-Sign Monitor | `document_management`, `data_rooms_gp`, `esigning`, `agents/esign_monitor_agent` | Table stakes. Buyers assume it. Use as demo content, not thought leadership. |
| Report Builder, period reports | `report_builder`, `account_entries_period_report` | Self-service export is expected in 2026; leading with it signals a reporting tool, not a platform. |
| Deals workspace + deal agents | `deals_management`, `agents/deal_management_agent`, `agents/deals_report_agent` | Competes head-on with dedicated CRMs where CapHive isn't the strongest claim. Better as a "and it's already in here" line inside #4. |
| Validation rules, custom fields | `validation_rule_engine`, `custom_fields` | Configuration depth — sells in a demo, doesn't hook in a feed. |
| Security hardening, 2FA, access model, roles | `security_hardening_changelog`, `two_factor_authentication`, `investor_access_tutorial`, `user_role_management` | Diligence answers, not demand generation. Belongs in a security one-pager sent on request. |
| Portfolio report drafts | `portfolio_report_drafts`, `agents/portfolio_report_agent` | Overlaps #3 too heavily to justify a second post this cycle. |
| Secondary sales, fund unit transfers | `secondary_sales`, `fund_unit_transfers` | Genuinely interesting market, but a small slice of the ICP runs LP-led secondaries in-house. Revisit if inbound asks for it. |
| Investment opportunities / EOI | `investment_opportunity` | Overlaps the deals story; same CRM-comparison problem. |
| RTA reconciliation | `agents/rta_reconciliation_agent` | India/APAC only (CAMS, KFintech). Wrong audience for US LinkedIn. |
| Dashboards, entities, investors, tasks, email add-ins, access-cache reset | various | Foundational setup or internal procedure — no buying trigger. |
