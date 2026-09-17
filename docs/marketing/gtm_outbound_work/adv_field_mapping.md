# Form ADV Field Mapping — List-Build Spec

**Purpose:** map every qualifier in [`us_gtm_zero_budget_notes.md`](../us_gtm_zero_budget_notes.md) §1.1 to the exact Form ADV location that evidences it, so the filtering script (prerequisites row F2) implements the right fields and nobody re-derives this from memory.

**Scope:** this is the *spec*, not the script. The bulk download, the filter code and the qualifying-pool count are owned separately (prerequisite rows F1–F3).

**Provenance — read this before trusting a citation.** Every item number below was checked against the **printed Form ADV Part 1A, revision code `SEC 1707 (07-24)`**, downloaded from `https://www.sec.gov/files/formadv-part1a_1.pdf` on 2026-08-16. Definitions and reporting instructions were checked against a copy of *Form ADV: Instructions for Part 1A* hosted at `iard.com`. The 07-24 Part 1A and the older 07-17 revision carry **identical numbering** for every question cited here (Item 5.A–5.G, Item 7.B, and Schedule D Section 7.B.(1) questions 1–28) — the only Item 5 change between them is the addition of **Item 5.L Marketing Activities**, which we do not use.

> `TODO-VERIFY:` the Instructions PDF used was the iard.com copy, not the sec.gov original (sec.gov returned 403 to the fetcher for that file). The instruction *content* cited below — Instruction 6.a–6.e — was cross-checked against the 07-24 form's own inline notes wherever the form repeats it. Before the script goes to production, re-pull `https://www.sec.gov/files/formadv-instructions.pdf` and confirm Instruction 6.c (series/classes), 6.d (master-feeder single filing) and 6.e.(2)–(3) (fund-type definitions, gross assets basis) still read as described.

> `TODO-VERIFY:` the SEC publishes Form ADV bulk data as period ZIP archives from the IAPD/Adviser Info compilation service, with the private-fund data in a separate Schedule D 7.B.(1) file keyed on the adviser's CRD/SEC number. **Column names in those files are not asserted here** — the compilation page is a JavaScript app and could not be read. The F1/F2 owner should map the item numbers below to the actual column headers on first download and record the mapping back into this file.

---

## 1. The five-line summary

| §1.1 qualifier | Evidenced by ADV? | Where |
|---|---|---|
| AUM $300M–$2B (hard cap $3B) | **Yes, directly** | Item 5.F.(2)(c), cross-checked with Item 5.D.(3)(f) |
| 3+ vehicles | **Yes, directly** | Count of Schedule D Section 7.B.(1) records — *with four counting traps, see §3* |
| …including at least one SPV or parallel fund | **No — heuristic only** | No SPV or parallel-fund field exists. See §5 |
| LPs 150–400 | **Partially** — upper bound only | Section 7.B.(1) Q13, summed. Double-counts LPs in multiple funds |
| Foreign LPs >25% | **Yes, directly, per fund** | Section 7.B.(1) **Q16** |
| 10+ active side letters | **No** | Not collected anywhere in Form ADV. See §6 |
| Multi-currency | **No — heuristic only** | Inferred from Q2 / Q5 / Item 1.M. See §5 |
| Deal-by-deal carry | **No in Part 1A** | Only "charges performance fees at all" (Item 5.E.(6)). See §6 |
| ≤4 stakeholders | **No** | Discovery-call question. Weak headcount proxy in Item 5.A / 5.B.(1) |
| Tech posture | **No** | Item 1.I gives the website + social handles; the research happens off-ADV |

---

## 2. AUM band — $300M–$2B, hard cap $3B

**Primary field: Item 5.F.(2)(c) — "Total" regulatory assets under management (U.S. Dollar Amount).**

Item 5.F.(1) is the yes/no gate ("Do you provide continuous and regular supervisory or management services to securities portfolios?"); 5.F.(2) then reports RAUM split as (a) Discretionary, (b) Non-Discretionary, (c) Total, with matching account counts at (d)/(e)/(f).

**Mandatory cross-check: Item 5.D.(3)(f) — RAUM attributable to "Pooled investment vehicles (other than investment companies and business development companies)".**

Item 5.D is a grid: (1) number of clients, (2) a "fewer than 5 clients" checkbox, (3) RAUM, across client-type rows (a) through (n). Row **(f)** is pooled investment vehicles. The instructions state that Item 5.D.(3) should total to Item 5.F.(2)(c).

*Why the cross-check is not optional:* a firm can show $1.4B of total RAUM where $1.2B is separately managed accounts for high-net-worth individuals and $200M sits in one small fund. That firm is a wealth manager, not a GP, and it will pass a naive 5.F filter. **Require Item 5.D.(3)(f) to be the dominant share of 5.F.(2)(c)** — suggested threshold ≥70%, to be tuned once the pool size is known.

**Second cross-check: sum of Section 7.B.(1) Q11 gross asset values.** Instruction 6.e.(3) says Q11 gross assets are computed on the same basis as RAUM (Instruction 5.b), so the sum of Q11 across a firm's funds should land close to Item 5.D.(3)(f). A large divergence means one of: sub-advised funds reported on 7.B.(2) instead, a master-feeder collapsed into a single filing, or stale data.

**Four caveats that will distort the band if ignored:**

1. **RAUM is not "AUM" as a GP says it.** For private funds, RAUM is computed on a gross basis and includes uncalled capital commitments. A GP that markets itself as "$800M AUM" can file $1.1B RAUM. The §1.1 band should therefore be read as *approximately* $300M–$2B on the RAUM basis, and the hard $3B cap should be applied with a margin rather than as a cliff.
2. **Staleness.** RAUM is stated as of the adviser's fiscal-year end and updated on the annual updating amendment, due within 90 days of fiscal year end. Any given record can be up to ~15 months old. A firm at $2.6B on file may be over $3B today.
3. **Umbrella registration.** Item 1.B.(2) checkbox plus Schedule R means one Form ADV covers a filing adviser *and* one or more relying advisers, and Item 5 is reported on a combined basis. A single filing can therefore represent several affiliated management companies. Flag `umbrella_registration = true` records for manual review rather than silently treating them as one firm.
4. **Non-US advisers.** Instruction 6.a lets an adviser whose principal office is outside the US disregard certain non-US funds in Item 7 and Section 7.B. Restrict the list to advisers with a US principal office (Item 1.F) and this mostly goes away — which we want anyway for time-zone reasons.

---

## 3. Vehicle count — "3+ vehicles, non-negotiable"

**Gate: Item 7.B — "Are you an adviser to any private fund? Yes / No."**

**Count: the number of Schedule D Section 7.B.(1) records the adviser files.** One Section 7.B.(1) = one private fund. Each record carries Q1(a) name of the private fund and Q1(b) private fund identification number (the `805-` series ID assigned by IARD, per Instruction 6.b), which is the natural primary key.

**"Private fund" is defined narrowly** (Form ADV glossary, definition 46): *an issuer that would be an investment company under section 3 of the Investment Company Act of 1940 but for section 3(c)(1) or 3(c)(7)*. Section 7.B.(1) **Q4** confirms which exclusion each fund relies on — Q4(1) is 3(c)(1), Q4(2) is 3(c)(7); at least one must be checked. This matters because a GP's *management* entities, GP entities and blocker corps are not private funds and will not appear as 7.B.(1) records, so the ADV count is a count of *investment vehicles*, not of legal entities. That is the number §1.1 actually wants.

### The four counting traps

| Trap | Instruction | Effect on the count | What the script must do |
|---|---|---|---|
| **Sub-advised funds** | Item 7.B instruction: if another SEC-registered adviser or ERA already reports the fund in *its* Section 7.B.(1), you must complete **Section 7.B.(2)** instead | Under-counts. A sub-adviser shows few or zero 7.B.(1) records | Count 7.B.(2) records too, as a separate column. Section 7.B.(2) carries only fund name (1), fund ID (2), the reporting adviser's name + SEC file number (3), and a solicitation flag (4) — no size, type or ownership data |
| **Master-feeder collapsed into one filing** | Instruction 6.d: an adviser **may** file a single 7.B.(1) for a whole master-feeder arrangement under the master fund's name, if the answers to Q8, Q10, Q21 and Q23–28 are the same for all feeders | Under-counts badly — a 1 master + 3 feeder structure can appear as one row | Recover the true count from **Q6** and **Q7**. Q6(a) "Is this a master fund in a master-feeder arrangement?" with Q6(b) listing the feeders' names and fund IDs; Q6(c)/(d) do the same from the feeder side. **Q7(a)–(f)** is the block completed *only* when a single filing covers the arrangement, and it lists each feeder individually. The NOTE under Q6 is explicit: Q6 must be completed for each master-feeder arrangement regardless of which filing style was used |
| **Series and classes split out** | Instruction 6.c: if a fund has issued two or more series/classes whose values are determined against *separate portfolios*, each series is treated as a separate private fund | Over-counts. Mostly a hedge-fund pattern, less common in PE | Detect near-duplicate Q1(a) names differing only by a series/class token and collapse for the count, but keep both rows |
| **Umbrella registration** | General Instruction 5 / Item 1.B.(2) / Schedule R | Over-counts a single manager's vehicles by pooling relying advisers' funds | Q3(b) of Section 7.B.(1) — "if filing an umbrella registration, identify the filing adviser and/or relying adviser(s) that sponsor(s) or manage(s) this private fund" — attributes each fund to a specific adviser. Use it to split |

**Recommended derived fields**

- `pf_count_7b1` — raw count of 7.B.(1) records
- `pf_count_7b2` — count of 7.B.(2) records (sub-advised)
- `feeder_names_listed` — union of names from Q6(b), Q6(d), Q7(a)
- `pf_count_effective` = `pf_count_7b1` + count of feeders named in Q6/Q7 that do not themselves appear as a 7.B.(1) record
- **Apply the 3+ test to `pf_count_effective`, not to `pf_count_7b1`.**

---

## 4. Per-fund fields — everything else worth extracting from Section 7.B.(1)

Verified question numbers, in form order. Everything in this table is per-fund; the script should keep the fund-level rows and aggregate to the firm separately.

| Q | Field | Use in the list build / in outreach |
|---|---|---|
| **1(a)/(b)** | Name of the private fund; private fund identification number | Join key. Names are the *only* signal for SPV/parallel detection (§5) |
| **2** | State or country under whose laws the fund is organized | Delaware vs. Cayman/Luxembourg/Jersey. Offshore siblings are the strongest available proxy for a parallel/feeder structure serving non-US or tax-exempt LPs |
| **3(a)** | Name(s) of General Partner, Manager, Trustee or Directors | Groups sibling vehicles under the same GP entity. Useful for parallel-fund detection |
| **3(b)** | Filing/relying adviser sponsoring this fund (umbrella filings only) | De-pools umbrella registrations |
| **4(1)/(2)** | 3(c)(1) / 3(c)(7) exclusion | 3(c)(1) caps beneficial owners at 100 — see the Q13 caveat. A mixed 3(c)(1)/3(c)(7) estate across vehicles is itself a complexity signal |
| **5** | Foreign financial regulatory authority the fund is registered with, and country | Direct evidence of a cross-border vehicle |
| **6(a)–(d)** | Master fund? feeders' names/IDs? feeder fund? master's name/ID? | **The one structural relationship ADV models explicitly.** Use for vehicle counting and as a personalization hook |
| **7(a)–(f)** | Per-feeder detail when a single 7.B.(1) covers the arrangement | Recovers hidden vehicles |
| **8(a)** | Is this a fund of funds? (≥10% of total assets in other pooled vehicles) | Usually a disqualifier for our ICP — FoF operations are a different problem |
| **10** | **Type of fund** — hedge fund / liquidity fund / private equity fund / real estate fund / securitized asset fund / venture capital fund / other private fund | Primary strategy filter. **Read the limitation in the note below** |
| **11** | **Current gross asset value of the private fund** | Per-vehicle size. Instruction 6.e.(3): report on the Instruction 5.b RAUM basis. Instruction 6.d.(1): for a collapsed master-feeder filing this is the *whole arrangement* |
| **12** | Minimum investment commitment required of an investor | Institutional ($5M+) vs. retail-ish ($250K) LP base. Feeds the side-letter *inference* in §6 |
| **13** | **Approximate number of the private fund's beneficial owners** | LP-count proxy. See the caveats below |
| **14** | % beneficially owned by you and your related persons | High GP commitment ⇒ often a small, concentrated, less institutional LP base |
| **15(a)** | % beneficially owned in aggregate by funds of funds | Institutional LP signal; funds of funds negotiate side letters |
| **15(b)** | For 3(c)(1) funds, are sales limited to qualified clients? | Minor |
| **16** | **% of the fund beneficially owned by non-United States persons** | **The direct evidence for the "foreign LPs >25%" complexity qualifier.** Best single field in the whole form for our purposes |
| **17(a)/(b)** | Are you a subadviser to this fund; if so, the adviser's name and SEC file number | Explains a thin 7.B.(1) count |
| **18(a)/(b)** | Do other advisers advise this fund | Co-advised vehicle — extra coordination burden |
| **21 / 22** | Reg D reliance; **Form D file number (`021-`)** | **The highest-value join in this spec.** See §7 |
| **23(b)** | Name of the auditing firm | Big-4 vs. regional signals institutional LP expectations |
| **26(a)** | **Does the private fund use an administrator other than your firm?** | If **No**, they self-administer — a strong CapHive fit signal and a clean email opener |
| **26(b)** | **Name of administrator** | Names their fund admin. The single best personalization field on the form |
| **26(e)/(f)** | Does the administrator send investor account statements (all / some / none), and if not, who does | If the *GP* sends statements, that work sits with the IR/ops team we are selling to |
| **27** | % of fund assets valued by a non-related person | Valuation-outsourcing posture |
| **28(a)–(g)** | Marketer / placement agent used, name, SEC file number, offices, websites | Placement agent ⇒ institutional LPs ⇒ side letters (inference only) |

### Limitation on Q10 (fund type) — read before filtering on strategy

The fund-type definitions in Instruction 6.e.(2) are **residual, not descriptive**. "Private equity fund" is defined as *any private fund that is not a hedge fund, liquidity fund, real estate fund, securitized asset fund or venture capital fund, and that does not provide investors with redemption rights in the ordinary course.* There is no "private credit", "growth equity", "infrastructure", "secondaries" or "co-investment" category. Direct-lending, infra-equity, growth and secondaries funds therefore land in **"private equity fund"** or **"other private fund"** essentially at the filer's discretion.

Consequence: **do not attempt to isolate private credit or growth equity from Q10.** Use Q10 only to exclude what we do not want (hedge fund, liquidity fund, securitized asset fund) and to keep PE / VC / real estate / other. Refine strategy from the firm's own website or the Part 2A brochure, which are prose and can carry the real description.

### Caveats on Q13 (beneficial owners) as an LP-count proxy

§1.1 wants **150–400 LPs across the firm**, meaning distinct investors. Q13 gives beneficial owners *per fund*.

- **Summing Q13 across funds double-counts** every LP who is in more than one vehicle — and re-upping LPs are the norm in this ICP. `SUM(Q13)` is an **upper bound**, not an estimate.
- **`MAX(Q13)` is a lower bound** on distinct LPs.
- **3(c)(1) funds are structurally capped near 100 beneficial owners.** A firm running only 3(c)(1) vehicles cannot show a Q13 above ~100 on any single fund regardless of its real investor base.
- For a collapsed master-feeder filing, Instruction 6.d.(3) says Q13–Q16 are answered by aggregating all investors in the arrangement, *excluding the feeder funds themselves as investors*.
- Practical rule: filter on `MAX(Q13) BETWEEN 60 AND 500` as a loose screen, carry both `MAX` and `SUM` on the row, and **confirm the real distinct-LP count on the discovery call** (see `qualification_screen.md` Q3).

---

## 5. Qualifiers that need heuristics — flag as inferred, never as fact

These have no ADV field. The script may compute them, but the output must be labelled as a *guess* so nobody writes an email asserting them.

### 5.1 SPV / co-investment vehicle

**No field exists.** Form ADV has no "SPV", "co-invest vehicle" or "annex fund" concept, and the only thing on the form called a "parallel managed account" is unrelated — the glossary (definition 42) scopes it to registered investment companies and BDCs, and it is collected in **Schedule D Section 5.G.(3)**, not in private-fund reporting.

Composite heuristic, all from Section 7.B.(1):

- **Name pattern (strongest):** Q1(a) containing `Co-Invest`, `Coinvest`, `SPV`, `Opportunit`, `Overage`, `Annex`, `Sidecar`, `Continuation`, `Access`, or a portfolio-company-looking proper noun that does not match the flagship family name.
- **Size relative to the flagship:** Q11 gross asset value below ~15% of the firm's largest fund.
- **Concentrated ownership:** Q13 beneficial owners under ~30.
- **Exclusion:** Q4(1) 3(c)(1) is more common in small co-invest vehicles.
- **Same sponsor:** Q3(a) GP/Manager name matching the flagship's.

Score these; treat 3 of 5 as "likely SPV", and put the fund *name* — not the inference — into the personalization field. Saying "your co-invest vehicle" to a GP whose Q1(a) name we misread is a credibility loss, and it is unrecoverable.

### 5.2 Parallel fund

**No field exists.** Detect from sibling naming plus jurisdiction:

- Two or more 7.B.(1) records whose Q1(a) names are identical up to a suffix — `-A` / `-B`, `(Cayman)`, `Offshore`, `Non-US`, `Ltd` vs `L.P.`, `AIV`, `Alternative Investment Vehicle`, `QP`, `ERISA` — **and**
- differing **Q2** organizing jurisdiction (Delaware vs Cayman is the classic), **and**
- the same **Q10** fund type, **and**
- overlapping **Q3(a)** GP/Manager names.

Note that Q6 will *not* fire on a true parallel structure: parallel funds invest side by side, they do not feed a master, so Q6(a)/(c) are both "No". A high Q6 hit rate with no naming siblings means master-feeder, not parallel.

### 5.3 Multi-currency

**Not collected.** Q11 gross asset value is reported in USD with no currency field. Proxies, weakest to strongest:

- **Item 1.M** — "Are you registered with a foreign financial regulatory authority?" (adviser level), completed in Schedule D Section 1.M
- **Section 1.F of Schedule D** — the adviser's offices other than the principal office; a London or Singapore office is a real signal
- **Item 5.F.(3)** — RAUM attributable to clients who are non-United States persons *(adviser level; note this is about the fund clients, not the LPs — see §6.2)*
- **Section 7.B.(1) Q2** — a Luxembourg, Jersey, Guernsey or Ireland vehicle nearly always implies non-USD or at least cross-border cash management; a Cayman vehicle usually does not, since Cayman feeders are typically USD
- **Section 7.B.(1) Q5** — the fund itself registered with a foreign regulator

Treat multi-currency as **unconfirmable pre-call**. It is a discovery-call question.

### 5.4 Buying-group size (≤4 stakeholders)

**Not collected, and not inferable with any confidence.** The only related fields:

- **Item 5.A** — approximate total employees (excluding clerical)
- **Item 5.B.(1)** — how many of those perform investment advisory functions including research
- `5.A − 5.B.(1)` ≈ non-investment headcount, i.e. roughly the operations + finance + IR + compliance + admin population. A firm with 8 non-investment staff has a small buying group; a firm with 60 does not.
- **Item 1.J** — Chief Compliance Officer name, other titles, phone and address. **The "other titles" line is genuinely useful**: a CCO who is also the CFO or COO is the signature of a lean firm where the buying group is small — and is very often our actual buyer.

This is a screening *hint* only. The real answer comes from the discovery-call question in `qualification_screen.md`.

### 5.5 Tech posture

Not in ADV. **Item 1.I** requires the adviser to list all firm website addresses and firm social-media accounts (Schedule D Section 1.I) — that is the launchpad for the off-ADV research (careers page, job postings for ops/data roles, LinkedIn team page). **Item 1.L** (books and records kept somewhere other than the principal office, detailed in Schedule D Section 1.L) sometimes names a third-party provider.

---

## 6. Genuine gaps — qualifiers that cannot be evidenced from Form ADV at all

### 6.1 Side letter count (the §1.1 "10+ active side letters" signal)

**Form ADV does not collect side letter information in any item, schedule or DRP.** There is no count, no existence flag, and no preferential-terms question anywhere in Part 1A. This is the clearest gap in the §1.1 profile.

Where it is *not* available either:

- **Form PF** collects far more, but Form PF filings are **not public**.
- **Part 2A brochure** occasionally discusses side letters in general terms under conflicts of interest, but almost never gives a count, and the language is boilerplate across thousands of filers.
- `TODO-VERIFY:` the SEC's 2023 Private Fund Adviser Rules included preferential-treatment disclosure requirements that would have produced side-letter-adjacent disclosure. Those rules were challenged and, to the best of the author's knowledge, **vacated by the Fifth Circuit in 2024**. Confirm the current status before anyone builds a plan on them. Either way they would not have created a *public, machine-readable* side letter count.

**Weak inference only** — usable to prioritise, never to assert. Institutional LPs negotiate side letters; institutional LP bases correlate with:
- Q12 minimum investment ≥ $5M
- Q15(a) funds-of-funds ownership > 0%
- Q28(a) uses a marketer / placement agent
- Q23(b) audited by a Big-4 or top-10 firm

**Operational consequence:** side letters must be a **discovery-call qualifier**, not a list-build filter. This is fine — §1.1 only requires *at least one* of the four complexity signals, and foreign-LP percentage (Q16) *is* directly filterable, so the list can be built without ever touching side letters.

### 6.2 Foreign investors — one precision trap worth stating loudly

There are three "non-US" fields and **two of them are the wrong one**:

| Field | What it actually measures | Use for "foreign LPs >25%"? |
|---|---|---|
| **Item 5.C.(2)** — approximate % of your clients who are non-US persons | Percentage of *advisory clients*. The Item 5.C/5.D instructions say explicitly: *"do not include as 'clients' the investors in a private fund you advise, unless you have a separate advisory relationship with those investors."* For a pure GP the clients are the **funds**, so this measures whether the *funds* are offshore | **No** |
| **Item 5.F.(3)** — RAUM attributable to clients who are non-US persons | Same population as above, weighted by RAUM. Measures offshore *vehicles* | **No** — useful only as a multi-currency hint |
| **Section 7.B.(1) Q16** — approximate % of the private fund beneficially owned by non-United States persons | **Look-through to the actual LPs of each fund** | **Yes. This is the field.** |

Aggregate Q16 to the firm by weighting each fund's Q16 by its Q11 gross asset value. Apply the >25% test to that weighted figure, and also keep the per-fund maximum — a firm with one 90%-foreign offshore parallel vehicle has exactly the pain we solve even if the firm-wide weighted figure is 20%.

"United States person" here takes the rule 203(m)-1 meaning (glossary definition 57), which includes any natural person resident in the US.

### 6.3 Deal-by-deal carry

**Not in Part 1A.** The only carry-adjacent field is **Item 5.E.(6)** — "You are compensated for your investment advisory services by … Performance-based fees" — which tells you they charge carry and nothing about the waterfall. Whole-fund (European) versus deal-by-deal (American) distribution is an LPA term.

Where it *might* be found, at real cost: the adviser's **Part 2A brochure** Item 5 (Fees and Compensation) and Item 6 (Performance-Based Fees and Side-By-Side Management) are free-text and occasionally describe the carry mechanism. That is a text-mining project against thousands of PDFs with a low and unpredictable hit rate.

**Recommendation: do not attempt this at list-build time.** It is a discovery-call question and a good one — see `qualification_screen.md` Q5.

### 6.4 Named contact — the CFO / COO / controller

ADV does **not** give you the buyer. It gives:

- **Item 1.J** — Chief Compliance Officer: name, other titles, phone, address (and an email address in the electronic filing). Often *adjacent* to the buyer and, at a lean firm, frequently the same person as the CFO — check the "other titles" field.
- **Item 1.K** — an additional regulatory contact person, if any.
- **Schedule A** — direct owners and executive officers, with titles. This is the best in-ADV source for a named CFO or COO, but it only covers people who are owners or executive officers, so a non-owner Head of Fund Operations will not appear.
- **Item 1.F** — principal office and place of business, which gives the time zone and the postal address.

Everything else — verified email, LinkedIn, current title — is the paid email-finder step, and it is where the §3.2 estimate of 10–15 minutes per account is actually spent.

---

## 7. Form D as a free companion dataset

**Section 7.B.(1) Q22 gives the fund's Form D file number (`021-…`).** Q21 asks whether the fund has ever relied on Reg D; Q22 captures the file number when it has. That number resolves to the fund's Form D filings on EDGAR, which are public, machine-readable and materially fresher than Form ADV.

Form D adds four things ADV does not have:

1. **Recency of fundraising activity.** The filing date of the most recent Form D or Form D/A tells you whether they are raising *right now*. This is the single best timing trigger available for free, and it maps directly to `us_gtm.md` §4.1 "upcoming closing or LP event that creates urgency".
2. **Total offering amount and total amount sold** — a live read on the current fund's size, months or years ahead of the next ADV annual amendment.
3. **Number of investors who have already invested** in that offering.
4. **Related persons** — Form D names executive officers, directors and promoters. Some of these are the CFO or COO by name.

> `TODO-VERIFY:` the exact Form D field labels and the EDGAR full-text/`/cgi-bin/browse-edgar` query pattern for resolving a `021-` file number were not checked during this pass. Confirm before the script depends on them. Also note that the SEC EDGAR fair-access policy requires a descriptive User-Agent and rate limiting on automated requests.

Because Form D is the freshest signal, treat "filed a new Form D or Form D/A in the last 6 months" as a **priority tier**, not as a qualifier.

---

## 8. What the script should emit, per account

One row per adviser, with a nested or joined per-fund table. Minimum columns for the outreach workflow to be usable:

**Firm level**
`crd` · `sec_file_number` · `legal_name` (Item 1.A) · `primary_business_name` (Item 1.B.(1)) · `umbrella_registration` (Item 1.B.(2)) · `principal_office_city/state` (Item 1.F) · `website_urls` (Item 1.I / Sch D 1.I) · `cco_name`, `cco_other_titles`, `cco_phone` (Item 1.J) · `employees_total` (5.A) · `employees_advisory` (5.B.(1)) · `raum_total` (5.F.(2)(c)) · `raum_pooled_vehicles` (5.D.(3)(f)) · `pooled_client_count` (5.D.(1)(f)) · `performance_fees` (5.E.(6)) · `foreign_reg_authority` (1.M) · `other_offices` (Sch D 1.F) · `filing_date` / `fiscal_year_end`

**Per fund (Section 7.B.(1))**
`fund_id` (Q1(b)) · `fund_name` (Q1(a)) · `org_jurisdiction` (Q2) · `gp_name` (Q3(a)) · `sponsoring_adviser` (Q3(b)) · `exclusion_3c1_3c7` (Q4) · `foreign_regulator` (Q5) · `is_master` / `feeders` / `is_feeder` / `master` (Q6) · `single_filing_feeders` (Q7) · `is_fund_of_funds` (Q8) · `fund_type` (Q10) · `gross_asset_value` (Q11) · `min_investment` (Q12) · `beneficial_owners` (Q13) · `gp_related_ownership_pct` (Q14) · `fof_ownership_pct` (Q15(a)) · `non_us_ownership_pct` (**Q16**) · `is_subadvised` (Q17) · `other_advisers` (Q18) · `form_d_number` (Q22) · `auditor` (Q23(b)) · `uses_external_administrator` (Q26(a)) · `administrator_name` (Q26(b)) · `admin_sends_statements` (Q26(e)) · `uses_marketer` (Q28(a)) · `marketer_name` (Q28(c))

**Derived, clearly labelled as derived**
`pf_count_effective` · `weighted_non_us_pct` · `max_non_us_pct` · `lp_upper_bound` (Σ Q13) · `lp_lower_bound` (max Q13) · `likely_spv_fund_ids` · `likely_parallel_groups` · `self_administered` (Q26(a) = No on any fund) · `filing_age_months`

**Do not emit** anything from Item 11 (disciplinary disclosure) or the DRPs into the outreach workflow. It is public, but referencing it in a cold email — even obliquely — is the fastest way to lose a market where, per §1 of the zero-budget notes, everyone talks to everyone.

---

## 9. Suggested filter order (cheapest exclusions first)

1. Item 7.B = Yes
2. Item 1.F principal office in the United States
3. `pf_count_effective` ≥ 3
4. Item 5.F.(2)(c) between $300M and $3B
5. Item 5.D.(3)(f) ÷ Item 5.F.(2)(c) ≥ 0.70
6. Q10 fund types include at least one of: private equity fund, venture capital fund, real estate fund, other private fund — and exclude firms whose funds are *only* hedge / liquidity / securitized asset
7. Q8(a) fund-of-funds is not true for the majority of the firm's assets
8. `max(Q13)` between 60 and 500
9. Complexity qualifier — **at least one of**: `weighted_non_us_pct` > 25%, `max_non_us_pct` > 25%, `likely_spv_fund_ids` non-empty, `likely_parallel_groups` non-empty, any Q2 outside the US, any Q5 populated
10. `filing_age_months` ≤ 18 (a stale filing means the firm may no longer match, and may no longer exist)

Steps 1–8 are hard filters. Step 9 is the §1.1 complexity gate but rests partly on heuristics, so it should produce a **score and a reason string** rather than a silent pass/fail — the reason string is what the personalization step reads.

**Report both counts** for prerequisite row F3: the count passing 1–8 (the addressable pool) and the count passing 1–10 (the priority pool). If the priority pool is materially under 400, §1.1 says to decide deliberately whether to drop the AUM floor or loosen the complexity qualifier. This spec's opinion, for what it is worth: **loosen the AUM floor before loosening the complexity qualifier** — a $250M GP with four vehicles and a Cayman parallel has our pain; a $900M single-vehicle GP does not.
