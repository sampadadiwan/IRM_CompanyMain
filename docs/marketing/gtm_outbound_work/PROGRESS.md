# PROGRESS — Cold Email Outbound Assets

**Built:** 2026-08-16 · **Status:** draft, not reviewed by a human, nothing sent · **Scope:** `us_gtm_zero_budget_notes.md` §3.2 (cold email outbound)

**Nothing in this folder has been sent, posted or committed.** No application code, `website_src/`, `public/website/`, `us_gtm_prerequisites.md` or `gtm_prerequisites_work/` was modified — those last two belong to the agent working prerequisite rows F1–F3 and C6.

---

## 1. What was produced

| File | What it is |
|---|---|
| [`adv_field_mapping.md`](adv_field_mapping.md) | List-build spec. Every §1.1 qualifier mapped to a verified Form ADV item, with the four vehicle-counting traps, the heuristics, and the four genuine gaps stated as gaps |
| [`personalization_framework.md`](personalization_framework.md) | The 12-minute timebox, ten Tier 1 hooks with the line each powers, persona routing, a do-not-personalize-on list, pre-send QA, and a clearly-labelled hypothetical worked example |
| [`sequences/README.md`](sequences/README.md) | Binding rules: format limits, the **approved claim list**, the **prohibited claim list**, the **verified link list**, and the do-not-link list |
| [`sequences/cfo_finance.md`](sequences/cfo_finance.md) | 4 emails, 3 subject variants each, 3 hook variants, reply handling |
| [`sequences/coo_operations.md`](sequences/coo_operations.md) | 4 emails, ditto. Email 3 is the configure-first offer — the reachable win trigger |
| [`sequences/ir_director.md`](sequences/ir_director.md) | 4 emails, ditto. Leads on side letters, the shipped two-thirds of this persona's win trigger |
| [`qualification_screen.md`](qualification_screen.md) | 30-minute discovery screen: anchor question, six §1.1 questions, the ≤4-stakeholder question with four phrasings, hard/soft disqualifiers, post-call write-up |
| [`message_testing_plan.md`](message_testing_plan.md) | Sequential-block design against the §5 kill criterion, with the sample-size arithmetic that rules out A/B testing at this volume |

---

## 2. Verification status of product claims

Two research passes over the repo: the website (`website_src/pages/`, `public/website/`, sitemap, deploy config) and the product (`docs/user_guides/`, `docs/features/us_gtm/`, application code).

### Verified — used in the sequences

Every claim on the approved list in `sequences/README.md` §2 traces to shipped code plus a user guide. The load-bearing ones:

- Call Notice Agent and Distribution Readiness Agent pre-flight gates, with their actual named steps
- Side Letter Obligation Agent: extraction with source clause, **mandatory counsel-review gate, nothing auto-activates**
- Allocation engine storing formula **and** input values per generated number
- Tracking currency: per-record restatement at each record's own economic date
- Close-percentage equalisation for late-admitted investors
- Document view tracking ("who opened it and when")
- KYC doc extractor pre-fill + KYC onboarding audit agent
- Master-feeder as a real modelled relationship (`Fund.master_fund_id`, `CapitalCommitment.feeder_fund_id`)
- Fund ratios incl. net-of-carry IRR — **carry deducted is an estimated figure**, wording reflects this
- Report Builder scheduled exports; KPI collection cycle; read-only MCP connection to Claude.ai over OAuth; audit trail; 2FA; documented API

**Every URL cited in the sequences was confirmed to exist as a file in `public/website/`.** Canonical form is `https://caphive.com/<slug>.html` — extensionless paths resolve but do not match the canonical tag.

### Excluded — prohibited in `sequences/README.md` §2

Not built, and therefore absent from every email: SOC 2, ISO 27001, bank verification / Plaid / dual approval / fraud hold, compliance evidence binder, Tax Center / K-1 workflow, W-9/W-8/FATCA collection, closing room, SSO/SAML, MFN comparison, "shadow books", named third-party integrations, US-hours support, unfunded commitment in the LP portal, and every unowned outcome metric.

### `TODO-VERIFY:` — a human must confirm before first send

| # | Item | Why it matters |
|---|---|---|
| V1 | **Who sends.** `us_gtm_zero_budget_notes.md` assumes founder-led outreach but never names a sender. `{{SenderName}}` / `{{SenderTitle}}` are unfilled | Sender identity is the largest single driver of cold-email reply rate. It is also held constant across every test block — it cannot change mid-test without invalidating results |
| V2 | **Booking link (prerequisites A3/A4).** `{{BookingLink}}` assumes a live link with genuinely honourable US-hours availability | Until it exists, **delete the line** rather than substituting `contact.html` — that form composes an email in the visitor's own mail client and captures nothing |
| V3 | **`security.html` currently states SOC 2 Type II and ISO 27001, both flagged unverified** in `docs/marketing/website_todos.md` under "published claims that could mislead" | The sequences do **not** link it. Either verify the certifications or remove the claims, then re-enable the link. Sending a prospect to an unverified compliance claim is the worst version of the risk §8 is trying to manage |
| V4 | **`carry-and-net-irr.html` is published but its source draft is flagged as needing compliance sign-off** (it discusses performance) — `linkedin_posts/00_post_backlog.md` | Not linked anywhere here. Confirm sign-off status |
| V5 | **CAN-SPAM footer mechanics** (prerequisite C6, other agent) — real postal address, working unsubscribe, verified suppression | Assumed present. Not specified or tested here |
| V6 | **"300 sends" means 300 *accounts*, not 300 individual emails** — see `message_testing_plan.md` §1 | The two readings differ by ~4×. Confirm the intent before scheduling the Week 12 checkpoint |
| V7 | **Form ADV Instructions PDF** was read from an `iard.com` copy; sec.gov returned 403 for that file. The Part 1A **form** itself was pulled directly from sec.gov (`SEC 1707 (07-24)`) | Instruction 6.c/6.d/6.e citations should be re-checked against the sec.gov original before the filter script depends on them |
| V8 | **SEC Private Fund Adviser Rules status.** Stated in `adv_field_mapping.md` §6.1 as believed vacated by the Fifth Circuit in 2024 | Does not change the conclusion (no public side-letter data either way), but the sentence should not stand unchecked |
| V9 | **Form D field labels and the EDGAR query pattern** for resolving a `021-` file number | Form D is recommended as a companion dataset; the mechanics were not tested |
| V10 | **LinkedIn checks in the Tier 2 research step are assumed manual** | Automated scraping would breach LinkedIn's terms |
| V11 | **ACV assumption** — `us_gtm_zero_budget_notes.md` §11 flags this as unconfirmed | The entire 10–15 min/account budget rests on $60K+ ACV. If it is materially lower, the timebox in `personalization_framework.md` §2 needs rebuilding, not tuning |

---

## 3. Genuine gaps in the ADV field mapping

Stated as gaps in the spec rather than papered over.

| §1.1 qualifier | Status |
|---|---|
| **Side letter count (10+)** | **Not collected anywhere in Form ADV.** No item, schedule or DRP. Form PF is not public; Part 2A mentions side letters only as conflicts boilerplate. Moved to the discovery call (`qualification_screen.md` Q4). Does not break the list build — §1.1 requires only *one* of four complexity signals, and foreign-LP percentage **is** directly filterable via Section 7.B.(1) Q16 |
| **SPV / co-invest vehicle** | **No field.** The only thing on the form called "parallel managed account" is scoped to registered investment companies and BDCs (glossary def. 42, Schedule D Section 5.G.(3)) and is unrelated. Composite name/size/owner-count heuristic supplied, explicitly labelled a guess |
| **Parallel fund** | **No field.** Sibling-name + differing-jurisdiction heuristic supplied. Note Q6 will *not* fire on a true parallel structure — parallel funds do not feed a master |
| **Multi-currency** | **Not collected.** Q11 gross asset values are reported in USD with no currency field. Weak proxies only (Q2 jurisdiction, Q5 foreign regulator, Item 1.M, Schedule D 1.F offices). Discovery-call question |
| **Deal-by-deal carry** | **Not in Part 1A.** Item 5.E.(6) tells you they charge performance fees, nothing about the waterfall. Part 2A brochure text sometimes describes it — a low-yield text-mining project, not recommended. Discovery-call question |
| **≤4 stakeholders** | **Not collected.** Weak proxy: `Item 5.A − Item 5.B.(1)` ≈ non-investment headcount, plus Item 1.J "other titles" (a dual-hatted CFO/CCO is a lean-firm signal). Real answer is `qualification_screen.md` §5 |
| **Tech posture** | Not collected. Item 1.I gives the website and social handles as a research launchpad |
| **Named CFO/COO** | ADV gives the CCO (Item 1.J), an additional regulatory contact (1.K) and Schedule A owners/officers with titles — but a non-owner Head of Fund Operations appears nowhere. This is the paid email-finder step and is where the 10–15 minutes actually goes |

**Precision point worth escalating, because it is easy to get wrong and would silently corrupt the list:** there are three "non-US" fields and only one is right. **Item 5.C.(2)** and **Item 5.F.(3)** measure non-US *advisory clients* — and the Item 5.C/5.D instructions explicitly exclude fund investors from "clients", so for a GP those fields describe whether the *funds* are offshore, not whether the *LPs* are foreign. The correct field for the §1.1 "foreign LPs >25%" qualifier is **Schedule D Section 7.B.(1) Question 16**, which looks through to beneficial ownership. Detail in `adv_field_mapping.md` §6.2.

### Confidence on Form ADV citations

**High.** Every item number was read from the printed **Form ADV Part 1A, `SEC 1707 (07-24)`**, downloaded from `https://www.sec.gov/files/formadv-part1a_1.pdf` and text-extracted locally — not recalled. The numbering was cross-checked against the earlier 07-17 revision and is **identical** for Item 5.A–5.G, Item 7.B and Schedule D Section 7.B.(1) questions 1–28; the only Item 5 difference is the added Item 5.L (Marketing Activities), which is unused. The one residual uncertainty is V7 above: the *Instructions* document (not the form) came from an `iard.com` mirror because sec.gov blocked the fetch, so Instruction 6.c/6.d/6.e should be re-confirmed.

Bulk-data **column names** are deliberately not asserted — the IAPD compilation page is a JavaScript app and could not be read. The mapping is at form-item level; whoever owns F1/F2 should map items to actual column headers on first download and record it back into the spec.

---

## 4. Things in the GTM plan that looked wrong from here

Flagged for the founders, not fixed — these are not this agent's documents to change.

### 4.1 The CFO persona's stated win trigger cannot be demoed

`us_gtm.md` §2.2 gives the CFO win trigger as **"compliance evidence binder demo + bank instruction change control workflow."** Both are roadmap: the evidence binder has no code at all, and bank instruction controls, dual approval, Plaid verification and fraud hold do not exist — there is no bank-account model and no Plaid dependency anywhere in the codebase. `docs/marketing/linkedin_posts/00_post_backlog.md` post #6 also names "bank-fraud controls" as the CFO message.

The CFO sequence therefore works the same underlying anxiety through what *is* shipped — the pre-flight gates on calls and distributions, and the allocation engine's stored formula-plus-inputs. **It is a workaround, and the plan should either reprioritise those two features or restate the CFO trigger.** This is the largest plan-versus-product gap found.

Related wording trap now handled in the copy: the Distribution Readiness Agent checks that bank details are **present**, not that they are **verified**. The verb must not be upgraded.

### 4.2 §5's kill criterion cannot distinguish its own two hypotheses

"Reply rate < 1% after 300 sends → **the list or the message** is wrong" — but reply rate alone cannot tell you which, and the two have opposite fixes. `message_testing_plan.md` §6 adds the diagnostics that separate them; the decisive one is **negative replies versus silence** (read-and-rejected is a message problem; silence is usually deliverability or a dead list).

Two further problems with §5 as written: **"300 sends" is undefined** (§1 of the testing plan — the per-email and per-account readings differ by ~4×), and **300 is a smoke test, not a measurement** — 3 replies out of 300 carries a 95% CI of roughly 0.34%–2.90%, so it cannot distinguish 1% from 2%. Detecting a doubling would need ~2,320 accounts per arm. Any A/B test at the checkpoint would produce a false conclusion that then gets scaled.

### 4.3 The proof assets the plan leans on are not usable yet

§4 says "a cold email that can link to a named case study converts several times better." Today: no case study has an approved name, quote or before/after number (prerequisite D1); all six carry a footer saying supporting detail is illustrative; and **two of the six cannot be sent to a US buyer at all** — `case-investor-onboarding.html` is built on AIF/SEBI/GIFT/IFSC/PAN/CKYC/Aadhaar, and `case-multi-party-transactions.html` contains Aadhaar e-sign and Indian stamping paragraphs.

The three genuinely clean ones are `case-investor-statements.html`, `case-portfolio-reports.html` and `case-capital-drawdowns.html` — all with **zero** India references, which is better than `us_gtm_prerequisites.md` Group D currently assumes. `case-multi-currency-close.html` has one benign "INR / EUR / GBP" line that reads as global. Worth updating the Group D note.

### 4.4 §1.1 asks for a pool the complexity qualifier may not fill

§1.1 requires 3+ vehicles **including at least one SPV or parallel fund** and calls it non-negotiable — but neither is an ADV field, so at list-build time it can only ever be a *heuristic* on fund names and sizes. The plan reads as though ADV settles it: §3.2 says "Form ADV carries the fund count and vehicle structure directly, so the non-negotiable complexity qualifier can be applied at list-build time." **The fund count, yes. The SPV/parallel qualifier, no.** That sentence should be softened, or the qualifier should be restated as one that ADV can actually evidence (foreign LPs >25% via Q16, or master-feeder via Q6, both of which are exact).

If the F3 pool count comes in short, this spec's opinion is to **loosen the AUM floor before the complexity qualifier** — a $250M GP with four vehicles and a Cayman parallel has our pain; a $900M single-vehicle GP does not.

### 4.5 Smaller observations

- **The configure-first demo is the strongest asset in this whole motion and the plan under-uses it.** It is the COO win trigger, it costs nothing but time, it answers the "they couldn't handle our complexity" objection by proposing the test rather than denying the premise, and — unlike case studies or SOC 2 — it is available *today*. It is currently buried in `us_gtm.md` §4.1 step 4 as a demo-prep note. It deserves to be a headline tactic. Its one constraint is real, though: it must be capped at a number of accounts per week the founder can actually honour.
- **The LP-facing AI assistant exists in code but has no user guide**, and unfunded commitment — the obvious demo question — is specifically not surfaced in the portal. It is named in the IR persona's win trigger. Either document and finish it or stop listing it.
- **`distribution-readiness.html` is missing from `sitemap.xml`** while all twelve sibling articles are listed. It loads and is safe to link; it is an indexing bug worth reporting to whoever owns the site build.
- **§11's open question about reference geography is still the highest-leverage unknown**, and it is upstream of most of this folder. If current customers cannot be US references, the IR and CFO sequences lose their strongest email-3 upgrade path and the emphasis has to shift permanently to structured pilots.

---

## 5. What a human must decide before anything sends

1. **V1** — name the sender.
2. **V3** — resolve the `security.html` SOC 2 / ISO 27001 claims. Nothing outbound should point at that page until then, and no reply should reference either certification.
3. **V6** — confirm "300 sends" means 300 accounts.
4. **§4.1** — accept the CFO sequence's substitute angle, or reprioritise the two roadmap features it works around.
5. **V2/V5** — confirm the booking link and the CAN-SPAM footer are live, or strip the signature line.
6. Read `sequences/README.md` §2 end to end. **The prohibited list is the part that protects the market**, and it is the part most likely to be casually violated in a reply written at speed.
