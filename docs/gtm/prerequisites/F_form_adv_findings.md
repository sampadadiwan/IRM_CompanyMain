# F1–F3 — Form ADV Extract and the Answer to the Pool-Size Question

**Checklist rows:** F1, F2, F3 in [`../us_gtm_prerequisites.md`](../us_gtm_prerequisites.md)
**Status:** F1 **DONE** · F2 **DONE** · F3 **DONE** · F4 not started (human research work)
**Script:** [`scripts/adv_filter.py`](scripts/adv_filter.py) — stdlib-only Python 3, no dependencies, re-runnable
**Data vintage:** SEC Form ADV bulk file, **2026-06-01** (newest published as of 2026-08-16)
**Verification:** the headline counts below were computed twice — once by the extract script, once by an independent recount straight off the raw CSV with independently chosen columns. Both agree exactly.

---

## 1. The answer

> **1,354 US-headquartered SEC-registered advisers match the §1.1 profile** ($300M–$2B RAUM **and** 3+ private fund vehicles).

The plan in `us_gtm_zero_budget_notes.md` §6 needs **400–600 targetable accounts**.

**The pool is roughly 2.3–3.4× the requirement. The volume assumption holds, and it holds with room to spare.** No decision is needed on dropping the AUM floor or loosening the complexity qualifier — F3's contingency branch does not fire.

This is the more useful finding, and it changes what the constraint is: the plan is **not** top-of-funnel constrained. It is constrained by contact resolution (F4, at 10–15 min/account) and by cycle length. Adding list volume buys nothing; the 1,354 already exceeds what 15 hrs/week of founder time can work.

---

## 2. Full counts

Base universe: **16,876** SEC-*registered* investment advisers. Zero rows have a blank RAUM, so no row is silently dropped by the filter.

| Filter | All registrants | US main office |
|---|---|---|
| RAUM $300M–$2B | 6,502 | 5,972 |
| ≥3 private funds (Item 7.B.(1)) | 3,639 | 3,362 |
| **Both — the §1.1 pool** | **1,453** (8.6%) | **1,354** (8.0%) |

Use **1,354**. The other 99 rows in the 1,453 break down as **50 with a blank main-office country** and **49 explicitly foreign** (21 UK, 8 Hong Kong, 7 Canada, 4 Australia, 2 Brazil, 2 Singapore, 1 UAE, 1 Israel, …) — SEC-registered, but not US firms, and outside the "US GTM" premise.

**The 50 blank-country rows are worth a second look**, not a silent discard: a blank is missing data, not evidence of being foreign, and some are likely US firms. Similarly, 99 of the 1,354 US matches have a blank *state*. If the pool were tight this would matter; at 1,354 against a 400–600 requirement it does not change any decision, so it is recorded rather than chased.

### What each filter actually removes

The **fund-count qualifier does most of the work**, which is exactly what §1.1 intended ("we tighten on complexity rather than on AUM"). Across all 16,876 registrants: 66.1% run **zero** private funds, 7.8% run one, 4.6% run two. The ≥3 threshold eliminates ~78% of the register before AUM is considered at all.

Within the $300M–$2B band, fund-count distribution:

| Private funds | Firms |
|---|---|
| 3–4 | 456 |
| 5–9 | 541 |
| 10–19 | 316 |
| 20–49 | 120 |
| 50+ | 20 |

Matched-firm profile: **median RAUM $807M, median 6 private funds.** That is squarely the profile §1.1 describes, not the edge of it.

---

## 3. Complexity signal — as far as ADV can carry it

§1.1 requires "3+ vehicles, **including at least one SPV or parallel fund**" and at least one of: foreign LPs >25%, 10+ side letters, multi-currency, deal-by-deal carry.

**None of those five are directly reportable from Form ADV.** "SPV" is not an ADV fund category, and side-letter counts and LP geography are not collected in the bulk file. The closest available proxy is the **per-fund-type breakdown** (Hedge / PE / Real Estate / VC / Liquidity / Securitized / Other), where running 2+ distinct fund types is reasonable evidence of structural complexity.

Of the 1,354 US matches:

| Distinct fund types | Firms |
|---|---|
| 1 | 943 |
| 2 | 317 |
| 3 | 78 |
| 4 | 10 |
| 5 | 6 |
| **2 or more (multi-strategy)** | **411 (30.4%)** |

Strategy mix (firms may appear in more than one): PE 895 · Hedge 421 · Other 258 · Real Estate 207 · VC 195 · Securitized 28 · Liquidity 6.

Geography: NY 371 · CA 193 · TX 141 · FL 99 · IL 78 · CT 66 · MA 57.

**Practical reading:** even the strictest defensible cut — multi-strategy only — leaves **411 accounts**, still inside the 400–600 requirement on its own. So there are two viable list strategies:

- **Tier 1 (411):** multi-strategy firms in the AUM band. Highest prior probability of the §1.1 complexity pain. Start here.
- **Tier 2 (943):** single-fund-type firms in the band. Complexity must be confirmed on the discovery call rather than at list-build time.

That tiering is a genuine finding: §1.1 claims the complexity qualifier "costs nothing extra to target" because ADV carries it. **That is only half true.** ADV carries the *vehicle count* precisely, but the SPV/parallel-fund and side-letter qualifiers are not in the data and remain discovery-call questions.

---

## 4. Contact data available for free

On the 1,354 US matches, straight from ADV:

- **1,354 / 1,354 (100%) have a phone number**
- **1,289 / 1,354 (95%) have a website**
- All have city, state, employee count, SEC status and latest ADV filing date

This directly supports the plan's §3.2 claim that "the real bottleneck is not the firm list — it is the person." The firm layer is complete and free. Only name → verified email needs paid tooling (C5).

---

## 5. Outputs on disk

In `tmp/adv_data/` (**gitignored** — `.gitignore:40:/tmp/*`, so nothing here enters version control):

| File | Contents |
|---|---|
| `ia060126_0.zip` | Raw SEC bulk download, 5.26 MB |
| `IA_SEC_-_FIRM_ROSTER_FOIA_DOWNLOAD_-_34605791.CSV` | Extracted, 42 MB, 16,876 rows × 448 columns |
| `adv_icp_matches.csv` | 1,453 rows — all registrants matching |
| `adv_icp_matches_us.csv` | **1,354 rows — the working target list** |

Columns: `firm_name, crd, raum_usd, private_fund_count, distinct_fund_types, fund_type_mix, gross_private_fund_assets, state, city, country, website, phone, employees, sec_status, latest_adv_filing`.

---

## 6. How to reproduce or refresh

```bash
python3 docs/gtm/prerequisites/scripts/adv_filter.py
```

The script auto-discovers the newest ZIP from the SEC listing page, caches the download, and re-runs the filter. Useful flags:

```bash
# The multi-strategy Tier 1 cut is not a script flag — filter the output CSV on
# distinct_fund_types >= 2.
--min-raum 300000000 --max-raum 2000000000 --min-funds 3   # defaults
--country "United States"                                   # default
--csv-out <path>
--zip <path>      # skip the download and use a file already on disk
```

Column names drift between ADV vintages, so every column is resolved through a case- and punctuation-insensitive candidate list; if one cannot be found the script **exits and dumps all 448 headers** rather than silently producing a wrong number.

### Access notes for whoever re-runs this

- **Working host:** `https://www.sec.gov/files/investment/data/other/information-about-registered-investment-advisers-exempt-reporting-advisers/ia060126_0.zip`. Plain `curl` works with a proper SEC User-Agent (`-A "CapHive Research <email>"`); no other special handling needed.
- **Blocked host:** `reports.adviserinfo.sec.gov/reports/CompilationReports/ia*.zip` returns **403 from Cloudflare** for every filename and header combination tried. Do not waste time there.
- **Landing page** has moved to `sec.gov/data-research/sec-markets-data/information-about-registered-investment-advisers-exempt-reporting-advisers`; the old `/foia/docs/form-adv-archive-data.htm` redirects to it.
- **Naming trap:** the hosting *directory* is named `...registered-investment-advisers-exempt-reporting-advisers/`, so the word "exempt" appears in the path of the **non**-exempt file too. Filter registered-vs-exempt on the **basename**, never the path. The script comments this.

---

## 7. Caveats — read before quoting the 1,354 to anyone

1. **Fund count is the SEC's precomputed `Count of Private Funds - 7B(1)` column**, not a count of Schedule D rows. The 2026-06-01 vintage ships a single roster CSV with no per-fund file. The script prefers row-counting whenever a Schedule D file *is* present, so re-running against an older multi-file vintage would cross-check this.
2. **Umbrella registration inflates some counts.** An adviser filing on behalf of relying advisers reports their funds too; conversely a fund reported by a related adviser may not appear on this filer's row. The tail looks affected — the top row is 127 PE funds against $302M RAUM, which is not a real mid-market GP profile. **Manually review the top ~50 by fund count before they enter outbound.**
3. **RAUM lags.** Item 5.F.(2)(c) is as of each firm's most recent annual updating amendment; most rows here are Q1 2026 filings. A firm that crossed $2B in H1 2026 still reads as in-band.
4. **Fund types are self-reported categories.** The multi-strategy measure in §3 is a proxy for complexity, not a direct SPV or parallel-fund indicator.
5. **Exempt Reporting Advisers are excluded** — they are in a separate `ia060126-exempt.zip`. Many sub-$2B private fund managers file as ERAs rather than registering, so the true addressable universe of small/mid private-fund managers is **larger** than 1,354. Worth a separate run if that segment is in scope. This cuts in the plan's favour, so it does not threaten the conclusion in §1.

---

## 8. F4 — next step, and it is human work

F4 asks for the first 100 accounts with a named CFO/COO/controller and a verified email. That is unblocked now: the firm layer exists.

**TODO-HUMAN:**
- [ ] Review the top ~50 rows by `private_fund_count` and drop umbrella-registration artefacts (caveat 2).
- [ ] Sort `adv_icp_matches_us.csv` to Tier 1 (`distinct_fund_types >= 2`, 411 rows) and work that first.
- [ ] Resolve name → verified email. Needs the C5 email-finder tooling (**BLOCKED — requires payment**).
- [ ] Budget honestly: 100 accounts × 10–15 min ≈ **17–25 hours**. At the ~3 hrs/week the plan allots to outbound in Phase 0–1, that is 6–8 weeks. This is the real Phase 0 critical path, not the website work.
