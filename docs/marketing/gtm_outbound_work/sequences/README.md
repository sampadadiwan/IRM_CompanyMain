# Cold Email Sequences — Rules of Use

Three sequences, one per primary persona in [`us_gtm.md`](../../../features/us_gtm.md) §2.2:

| Persona | File | Grounded in |
|---|---|---|
| CFO / Head of Finance | [`cfo_finance.md`](cfo_finance.md) | Pain: audit-ready evidence assembled by hand; controls around money movement; spreadsheet-managed tracking |
| COO / Head of Operations | [`coo_operations.md`](coo_operations.md) | Pain: team doing work that should be automated; each vehicle adds linear headcount. Win trigger: a demo against *their* structure |
| Director of Investor Relations | [`ir_director.md`](ir_director.md) | Pain: LP questions consume the team; side-letter commitments live in someone's head |

**The GC and CTO personas (§2.2 personas 4 and 5) get no cold sequence.** They are approvers and evaluators who enter mid-cycle, per the deal flow in `us_gtm_zero_budget_notes.md` §7. Cold-emailing them ahead of a champion adds a stakeholder to a buying group we are explicitly trying to keep at four or fewer.

---

## 1. Format rules

- **Word limits, body only, excluding greeting, signature and footer:** email 1 ≤ 90 · email 2 ≤ 75 · email 3 ≤ 75 · email 4 ≤ 45. Over the limit, cut — do not reformat.
- **Open on their problem.** The word "CapHive" must not appear before the second paragraph of any email, and in emails 2–4 it usually should not appear at all.
- **One personalization hook, first sentence.** See [`../personalization_framework.md`](../personalization_framework.md) §1.
- **One link maximum per email**, and never in email 1's first paragraph.
- **No attachments. Ever.** The link *is* the deck (`us_gtm_zero_budget_notes.md` §3.2). An attachment from an unknown sender is a spam signal and a security-team escalation.
- **Plain text.** No images, no tracking pixels, no HTML signature block with a logo. One tracked link at most, and only if the UTM convention from prerequisite B5 is agreed.
- **Send spacing:** email 1 → +4 business days → email 2 → +6 → email 3 → +8 → email 4. Whole sequence spans about four weeks.
- **Same thread for 2–4** (reply to the sent message). Email 1 gets the only fresh subject line.
- **Stop on any reply**, including "not interested" and out-of-office auto-replies that name a different contact.
- **Send during US business hours**, 8–11am recipient local time. India evening (`us_gtm_zero_budget_notes.md` §3.2).

Subject line rules: **under 45 characters, lower-case or sentence case, no colons, no brackets, no emoji, no "Quick question", no fake `Re:`.** CAN-SPAM prohibits deceptive subject lines and the ICP recognises every sales-tool convention on sight.

---

## 2. Approved product claims — the hard list

Every claim in these sequences traces to something verified in the repo (shipped code plus a user guide, or a published website page). **Nothing outside this list may be added to an email without re-verification.**

### ✅ Verified — safe to say

| Claim | Evidence |
|---|---|
| Capital calls and distributions are computed from commitment data, with per-close percentages so late-admitted investors equalise correctly | `docs/user_guides/capital_calls_user_guide.md`; allocation engine pack; `close_percentages` on the capital call model |
| Every generated allocation number stores the formula **and** the input values that produced it | Allocation engine pack; `https://caphive.com/allocation-engine.html` |
| A rule-based pre-flight gate runs before call notices go out — investor KYC, notice generated, documents approved, notification configured — and stops at the first failure | Call Notice Agent service; `docs/user_guides/agents/call_notice_agent_user_guide.md` |
| A rule-based pre-flight gate runs before distributions are released — investor KYC, net payable computed, notices generated and approved, bank details present | Distribution Readiness Agent service; `docs/user_guides/agents/distribution_readiness_agent_user_guide.md` |
| Side letters are read and their obligations extracted with the source clause, then held for counsel review before anything becomes a tracked, dated, owned task | Side Letter Obligation Agent service; `docs/user_guides/agents/side_letter_obligation_agent_user_guide.md` |
| A fund runs in its own base currency and is restated into one firm-wide reporting currency, per record, at the rate on that record's own economic date | `docs/user_guides/tracking_currency_guide.md` |
| TVPI, DPI, RVPI, XIRR, MOIC and net-of-carry IRR are computed from the ledger — carry deducted in net IRR is an **estimated** carry figure | `docs/user_guides/fund_ratios_user_guide.md`, `docs/user_guides/carry_computations_user_guide.md` |
| Documents record who viewed them and when, visible per document | `docs/user_guides/document_management_user_guide.md` |
| KYC documents are read on upload and used to pre-fill the form, then a second agent audits the finished record for completeness and expiry | KYC Doc Extractor + KYC Onboarding agent guides |
| Master-feeder is modelled as a real relationship — a fund can have a master, commitments can be attributed through a feeder, and allocation follows it | `Fund.master_fund_id` / `has_many :feeder_funds`; `CapitalCommitment.feeder_fund_id` |
| Portfolio companies submit KPIs on a reminder cycle that skips those who have already submitted; data is approved before it reaches dashboards | `docs/user_guides/kpi_upload_user_guide.md` |
| Report Builder produces cross-table exports on demand or on a schedule | `docs/user_guides/report_builder_user_guide.md` |
| CapHive data can be connected read-only to Claude.ai over OAuth, exposing read-only tools — no data leaves for training, and it is the GP's own AI client | `docs/user_guides/mcp_server/user_guide_mcp_connect_claude.md` |
| Full audit trail (who changed what, when, from where), 2FA, documented REST API | Audited gem + `audits` table; 2FA guides; `/api/v1` with Swagger |
| LP portal with per-investor scoped access and external advisor access | `docs/user_guides/investor_access_tutorial.md`, `investor_advisor_user_guide.md` |

### ❌ Prohibited — do NOT claim in any email

| Prohibited claim | Why |
|---|---|
| **SOC 2 of any type** | No verified status. `docs/marketing/website_todos.md` files the existing site claim under "published claims that could mislead", wrapped in a do-not-publish-unless-confirmed marker |
| **ISO 27001** | Same source, same status — unverified |
| **Bank verification, Plaid, dual approval on bank changes, fraud hold, ACH authorisation** | Not built. No bank-account model, no Plaid dependency anywhere in the codebase. The distribution gate checks that bank details are *present*, not that they are *verified* — do not upgrade the verb |
| **Compliance evidence binder** | Roadmap. No code |
| **Tax Center, K-1 delivery workflow, corrected-K-1 handling** | Roadmap. Only generic document delivery exists |
| **W-9 / W-8 / FATCA collection** | Roadmap. A configurable form engine exists that *could* be templated for them; that is not the same sentence |
| **Closing Room** | Roadmap |
| **SSO / SAML** | Not built |
| **MFN review or cross-side-letter comparison** | Deferred. The data model has an MFN flag; there is no comparison logic. "Flag a clause as MFN-relevant" is true; "MFN review" is not |
| **"Shadow books"** | Appears on the website with nothing behind it. A prospect will ask for a demo of it |
| **Named bank or third-party integrations** | Which integrations are live is explicitly unconfirmed in `website_todos.md` |
| **US-hours support commitment** | Prerequisite E5 is unchecked. Do not state a coverage window until it is staffed and published |
| **Unfunded commitment surfaced to LPs in the portal** | It is a computed method, not surfaced on notices or in the portal. Use a different example of an LP self-serve question |
| **Any outcome metric** — "40% less LP service burden", "quarter-close from 15 days to 4", "$10bn+ AUM", "4,000+ investors" | Unowned or unapproved. No performance guarantees, no invented metrics (prerequisite D1 gates these) |
| **Any customer name, quote or testimonial** | None are approved for attribution |

---

## 3. Verified links — the only URLs that may be used

Domain is **`caphive.com`** and the canonical form **includes `.html`**. Extensionless paths resolve but do not match the canonical tag — paste the `.html` form.

| URL | What it argues | Best for |
|---|---|---|
| `https://caphive.com/allocation-engine.html` | Every generated number carries its own receipt — the formula and the actual inputs | CFO, COO |
| `https://caphive.com/capital-call-notices.html` | A call notice is a legal instruction to move money and deserves a pre-flight nobody can configure away | CFO |
| `https://caphive.com/distribution-readiness.html` | Five things that must be true before a distribution leaves the building | CFO |
| `https://caphive.com/side-letter-obligations.html` | Your side letters are in a folder; your obligations are on your balance sheet | IR, GC |
| `https://caphive.com/agent-side-letter-obligation.html` | Product page: extraction with source clause, counsel approval gate, then dated tasks | IR |
| `https://caphive.com/agent-distribution-readiness.html` | Product page for the pre-wire gate | CFO |
| `https://caphive.com/agent-call-notice.html` | Product page for the pre-notice gate | CFO |
| `https://caphive.com/document-first-kyc.html` | Read the documents first, pre-fill, confirm — inverts the onboarding form | COO |
| `https://caphive.com/tracking-currency.html` | One fund in one currency, another in another, one report | CFO |
| `https://caphive.com/lp-relationship-crm.html` | Your CRM ends at "Committed" — that's where the work starts | IR |
| `https://caphive.com/portfolio-kpis-at-scale.html` | KPI collection from many companies onto one cycle | COO, IR |
| `https://caphive.com/fund-data-in-your-ai-client.html` | We didn't add a chatbot; we made the fund callable, read-only, under your own key | Technical GP |
| `https://caphive.com/case-capital-drawdowns.html` | Case study: 100+ LPs per call, different rates per close, payments posted in both currencies | CFO, COO |
| `https://caphive.com/case-investor-statements.html` | Case study: 500+ LPs, per-investor statement variations, delivered securely | IR |
| `https://caphive.com/case-portfolio-reports.html` | Case study: 50+ portfolio companies, 50 inbound spreadsheet formats, one output | COO, IR |
| `https://caphive.com/case-multi-currency-close.html` | Case study: three currency layers held simultaneously | CFO |
| `https://caphive.com/pricing.html` | Priced on the funds you run, not per seat; quoted after reviewing structures | Only if asked |
| `https://caphive.com/contact.html` | Book a walkthrough | Only if the booking link (prerequisite A3) is live |

### Do not link

| URL | Reason |
|---|---|
| `https://caphive.com/security.html` | **Currently states SOC 2 Type II and ISO 27001 — both flagged unverified in `website_todos.md`.** Do not send a prospect to an unverified compliance claim. Re-enable once the claims are confirmed or removed |
| `https://caphive.com/carry-and-net-irr.html` | The source draft is flagged in `linkedin_posts/00_post_backlog.md` as needing compliance sign-off because it discusses performance. Published, but hold until signed off |
| `https://caphive.com/case-investor-onboarding.html` | Heavily India-specific — AIF, SEBI, GIFT/IFSC, PAN, CKYC, Aadhaar. Signals exactly the thing we are pre-empting |
| `https://caphive.com/case-multi-party-transactions.html` | Contains Aadhaar e-sign and Indian stamping paragraphs |
| `https://caphive.com/outlook-for-aifs-in-india.html`, `operational-alpha.html`, `agent-rta-reconciliation.html` | India-specific and/or marked draft |
| `https://caphive.com/resources.html` | Links onward to the India AIF outlook piece. Link the specific article instead of the hub |
| `privacy.html`, `terms.html`, `cookies.html` | Marked "NOT LEGAL ADVICE — DO NOT PUBLISH AS-IS" in source; `privacy.html` still carries an unfilled `[number] days` placeholder |
| Any page marked DRAFT FOR REVIEW in source | `ai-is-ready`, `ai-agent-infrastructure`, `portfolio-real-time-insight`, `tech-powered-portfolio-management-vc`, `ai-and-fifa-2026` |

**Case-study framing rule.** All six case studies carry a footer saying the platform mechanics are exactly as CapHive runs them but supporting detail is illustrative. So phrase every citation as **"how this is handled"**, never as **"our client achieved"**. Do not name or imply a client.

`⚠️ distribution-readiness.html is missing from sitemap.xml` — it loads fine and is safe to link, but it is a real indexing bug worth reporting to whoever owns the site build.

---

## 4. Signature, footer and compliance

The CAN-SPAM footer mechanics — postal address, working unsubscribe, suppression on click — are **owned by prerequisite row C6** and are not specified here. These sequences assume the footer is appended by the sequencer and that an unsubscribe click genuinely suppresses the address.

Signature to use, plain text, no logo:

```
{{SenderName}}
{{SenderTitle}}, CapHive
{{BookingLink}}
```

`TODO-VERIFY:` who sends. `us_gtm_zero_budget_notes.md` assumes founder-led outreach but never names the sender, and §11 asks the same question about the LinkedIn engagement block. Sending from a named founder with a real title materially outperforms a generic alias, and it is also the honest option. Decide before the first send — the sender identity cannot be changed mid-test without invalidating the results in [`../message_testing_plan.md`](../message_testing_plan.md).

`TODO-VERIFY:` `{{BookingLink}}` requires prerequisite A3/A4 (booking link live with real US-hours availability). **Until it exists, remove the line rather than substituting the contact page** — sending a prospect to a form that composes an email in their own mail client is worse than no link.

---

## 5. Token reference

| Token | Source |
|---|---|
| `{{FirstName}}` | Email finder, verified against LinkedIn |
| `{{FundName}}`, `{{FundA}}`, `{{MasterName}}`, `{{FeederName}}` | Section 7.B.(1) Q1(a) — **spelled exactly as filed** |
| `{{Admin}}` | Section 7.B.(1) Q26(b) |
| `{{VehicleCount}}` | `pf_count_effective` |
| `{{Jurisdiction}}` | Section 7.B.(1) Q2 |
| `{{NonUSPct}}` | Section 7.B.(1) Q16 — round down, never up |
| `{{SenderName}}`, `{{SenderTitle}}`, `{{BookingLink}}` | Fixed per sender |

A token that cannot be filled means the email does not send. **No fallbacks** — a fallback is how "Hi {{FirstName}}" becomes "Hi there" and the whole account learns it was a mail merge.
