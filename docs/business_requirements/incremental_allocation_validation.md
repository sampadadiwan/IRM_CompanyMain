# Faster allocation runs: validation report and the tracking bug

**Entity:** True North (entity 6349)
**Funds:** 316 True North Fund V LLP, 317 True North Fund V Trust, 318 Indium V (Mauritius),
319 True North Fund VI LLP, 320 True North Fund VI Trust, 321 Indium VI (Mauritius)
**Tested on:** a copy of the production database (13 September 2026 backup), on a developer machine
**Status:** validation complete for all six funds (tested 14 September 2026)
**Technical detail:** `docs/technical/incremental_allocation_history.md` (section 12)

---

## 1. Summary

**The problem.** Every allocation run copies a fund's *entire* history of account entries (back
to 2017 for some funds) into a temporary working file, even when it only calculates one month.
For fund 319 that is 350,000 entries and a 1.2 GB file for a run that produces about 13,000.

**The change.** For "since inception" figures, the engine now starts from the total the previous
run already saved and adds only the new period's movement, instead of re-adding every entry since
inception. That means it no longer needs old history, so the working file only holds the current
financial year. The change is switched on **fund by fund**; funds not switched on behave exactly as
before.

**The verdict.**

- **Same numbers, on all six funds.** We re-ran nine real periods (four on fund 319, one on each of
  the other five funds) with the old and the new engine — between 11,000 and 86,000 entries per
  period. **Every entry matched**, apart from formulas we deliberately fixed (below) and figures
  calculated from them.
- **Less data, usually faster.** The entries copied into the working file fell to between 13% and
  66% of the old number, depending on how far into the financial year the period falls. Run time
  fell by up to 50% on the master funds, but only 0–20% on the feeder funds, where most of the time
  goes on calculation rather than copying.

**A bug found along the way.** A set of "tracking" formulas (figures in the tracking currency,
USD) re-add their whole history on every run. Their stored values grow with the *number of runs*,
not with the data. On fund 319 one figure was stored as **317.2 million** when the correct value is
**52.8 million**. On fund 316 these inflated figures **feed the carry and catch-up waterfall for
USD-class investors**. See section 5.

**Ready to switch on: 316, 317, 318, 319.** Funds 320 and 321 have one formula that reads
further back than the smaller working file holds, and funds 324–328 have two; those formulas need
rewriting first (section 7, findings 6 and 7). The periods we tested on 320 and 321 did not reach
that far back, which is why they matched.

**Nothing has been changed in production.** All testing ran on a copy of production data.

---

## 2. What changed, in plain terms

### How a "since inception" figure used to be calculated

A figure such as *Since Inception Management Fees* for an investor was calculated on every run by
adding up every Management Fees entry since the fund started.

### How it is calculated now

Take the total the previous run saved, and add this period's fees.

**Worked example** — one investor (commitment 13947), Since Inception Management Fees,
quarter ending 31 December 2025:

| | Amount |
| --- | --- |
| Saved by the previous run (as at 30 September 2025) | 47,646.19 |
| Management Fees in October–December 2025 (6 entries) | 2,066.65 |
| **New since-inception total** | **49,712.84** |
| Total from re-adding every fee since inception (old way) | 49,712.84 |

Same answer, but reading 7 entries instead of years of them.

### What the working file keeps now

For a fund that is switched on, the working file keeps:

1. every entry from the **start of the financial year** to the end of the period being run
   (year-to-date and quarterly figures need these),
2. every **uploaded** entry, whatever its date (they are a small share and nothing recreates them),
3. for everything older, only the **most recent entry** of each kind — which is what "latest value"
   lookups read.

### Safety rules built in

- **Missing saved total → the run stops.** If an investor has history but no saved total to start
  from, the run fails with a clear message rather than producing a figure that is silently too low.
- **Skipped days are handled.** If the previous saved total is older than the day before the period
  starts, the entries in between are added from the main database.
- **New investors are fine.** An investor with no earlier entries needs no saved total.
- **Per-fund switch.** Only funds explicitly switched on use the new method. Across the whole system
  43 funds use since-inception totals; every fund not switched on is untouched.

---

## 3. How we tested

### The method (the same for every fund)

1. **Back up** the fund's entries as they are (a restore point).
2. **Old engine:** re-run a real period with the fund's original formulas, and save the results.
3. **Apply** the formula changes the fund needs (section 6) and switch the fund on.
4. **New engine:** re-run the same period again, and save the results.
5. **Compare** the two sets of results entry by entry: same entries, same amounts.

### What "matched" means

Every entry is compared on what it is (formula, name, entry type, date, investor, folio, parent)
and its three amounts (amount, folio amount, tracking amount).

Differences of **0.0001 cents or less** are counted separately as rounding: the working file adds
decimals slightly differently in a different order, which can move the eighth decimal place. They
are reported, but not treated as real differences.

We also checked that **nothing outside the period changed**.

### Choosing periods

We used real periods that had been run in production. Older periods on these funds have often been
re-run many times with different, overlapping date ranges, and there are two "regenerate from 2015"
runs, so re-testing those would disturb other periods. We therefore used the **most recent periods
that no differently-dated run overlaps**.

---

## 4. Results by fund

### Overview

| Fund | Period tested | Entries | Old vs new | Run time (old → new) | Entries copied (old → new) |
| --- | --- | --- | --- | --- | --- |
| **319** VI LLP | 1–31 Aug 2026 | 12,792 | ✅ Same, except the tracking fix | 195 s → **127 s** | 349,410 → **121,985** |
| **319** VI LLP | 1–30 Jun 2026 | 13,080 | ✅ Identical | 164 s → **136 s** | 350,736 → **96,476** |
| **319** VI LLP | 1 Jan – 2 Feb 2026 | 12,540 | ✅ Identical | 159 s → **143 s** | 350,736 → **216,196** |
| **319** VI LLP | 1 Apr – 31 May 2025 | 12,252 | ✅ Identical | 243 s → **122 s** | 352,042 → **47,512** |
| **316** V LLP | 1–31 Aug 2026 | 11,154 | ✅ Same, except the tracking fix and what depends on it | 122 s → **105 s** | 235,489 → **78,577** |
| **317** V Trust | 1 Jul – 31 Aug 2026 | 85,655 | ✅ Identical | 1,278 s → **1,100 s** | 2,000,056 → **1,097,048** |
| **318** Indium V | 1 Apr – 30 Jun 2026 | 61,631 | ✅ Identical | 981 s → **789 s** | 1,141,198 → **639,474** |
| **320** VI Trust | 1–31 Jul 2026 | 25,578 | ✅ Identical | 626 s → **534 s** | 932,304 → **509,921** |
| **321** Indium VI | 1–7 Aug 2026 | 21,498 | ✅ Identical | 519 s → 531 s (no gain) | 927,312 → **615,908** |

"Identical" periods ran the fixed formulas on both sides, so even the tracking figures matched.
For the August periods the old run used the original formulas, so the tracking fix shows up as a
difference — by design.

### Fund 319 — True North Fund VI LLP

- **Four periods, all matched.** They include the hardest case: the **first run of a financial
  year** (April–May 2025), where every saved total the run starts from is dated before the start of
  the year.
- **Rounding-only differences:** 40–60 entries per period, all under 0.0001 cents.
- **August 2026 in detail:** 12,745 of 12,792 entries identical. The other 47 were the 6 tracking
  formulas we fixed plus the one figure that adds them up (*Net Current Assets before profit
  distribution to GP tracking*).
- **Tracking fix verified end to end.** We corrected the saved July tracking totals, re-ran August,
  and recomputed each August tracking figure from full history: **all 42 matched to the cent**.

### Fund 316 — True North Fund V LLP

- **August 2026:** 11,154 entries; nothing outside the period changed; 60 rounding-only differences.
- **79 entries across 25 names differed**, and every one traces back to the tracking fix:
  1. the 6 tracking formulas and their total (*Net Current Assets … tracking*) changed;
  2. *Gross Realized amount* reads that total for **USD-class** investors;
  3. the carry waterfall is built on *Gross Realized amount*: *Gross Distributable amount* →
     *Preferred Return* → *Residual Disposition Income* → *Catch up* → *Carry* → *Ending NAV net of
     profit distribution*, and the fund-wide *Catch up Income* and *Carry Income*.
- **Business impact:** see section 5 — on this fund the tracking bug reaches the carry calculation.
- The saved July tracking totals on 316 have **not yet been corrected**, so the new August figures
  are still built on inflated starting values.

### Fund 317 — True North Fund V Trust (feeder of 316)

- **July–August 2026:** all 85,655 entries identical; 53 rounding-only differences; nothing outside
  the period changed.
- **One formula change** (pattern C, seq 284), which does not change results — confirmed.
- **Smaller speed gain than on 319:** 21 → 18 minutes. A feeder run copies its master fund's data
  too (2.0 million entries, now 1.1 million), but this two-month period generates 85,000 entries,
  so the time spent calculating — which the change does not reduce — dominates. Peak memory fell
  from 2.2 GB to 1.9 GB.

### Fund 318 — Indium V (Mauritius) Holdings Limited (feeder of 316)

- **April–June 2026:** all 61,631 entries identical; 149 rounding-only differences; nothing outside
  the period changed.
- **Six formula changes** applied: seq 301 (pattern C, no change to results — confirmed) and the
  five tracking formulas (pattern A). The tracking formulas are currently **switched off** (disabled)
  on this fund, which is why they have never produced a figure and why they made no difference here.
- 318's financial year starts in **January**, so the working file keeps entries from 1 January.
  Entries copied fell from 1.14 million to 0.64 million; run time from 16 to 13 minutes.

### Fund 320 — True North Fund VI Trust (feeder of 319)

- **July 2026:** all 25,578 entries identical; 5 rounding-only differences; nothing outside the
  period changed.
- **One formula change** (pattern C, seq 286), which does not change results — confirmed.
- Entries copied (320 plus master fund 319) fell from 932,000 to 510,000; run time from 10.4 to
  8.9 minutes.

### Fund 321 — Indium VI (Mauritius) Holdings Limited (feeder of 319)

- **1–7 August 2026:** all 21,498 entries identical; 31 rounding-only differences; nothing outside
  the period changed.
- **Six formula changes** applied: seq 303 (pattern C, no change to results — confirmed) and the
  five tracking formulas (pattern A). As on 318, the tracking formulas are **switched off** on this
  fund, so they made no difference.
- **No speed gain on this period** (519 s → 531 s, within normal run-to-run variation). 321's
  financial year starts in **January**, so a run in August still copies seven months of data
  (927,000 → 616,000 entries, including master fund 319), and the calculation time dominates.

---

## 5. The tracking bug

### What it is

The "tracking" formulas hold since-inception figures in the tracking currency (USD), such as
*Total Amount Invested tracking* or *Portfolio sold tracking*. Each is built as:

> **all entries up to the end of the period** + **the value this formula saved last run**

But the value saved last run *already* includes all entries up to the previous period. Adding both
counts the history twice — and because each run's result becomes the next run's starting value, the
double counting builds up with every run.

### Evidence

Fund 319, one investor (commitment 13905), *Total Amount Invested tracking*, as stored in production:

| Date saved | Stored value | Increase since previous save |
| --- | --- | --- |
| 31 Dec 2025 | 0 | — |
| 31 Mar 2026 | 53.1 M | +53.1 M |
| 12 May 2026 | 106.3 M | +53.2 M |
| 27 May 2026 | 159.4 M | +53.2 M — over a 15-day period |
| 31 May 2026 | 212.6 M | +53.2 M — over a **4-day** period |
| 30 Jun 2026 | 264.9 M | +52.3 M |
| 31 Jul 2026 | **317.2 M** | +52.3 M |

A 4-day period cannot add 53 million invested. Each run re-adds the whole history (~53 million).
**The correct value on 31 July, recomputed from all history, is 52.8 million — the stored figure is
six times too high**, and the gap widens with every run.

### Where it is

| Fund | Tracking formulas | Situation in production |
| --- | --- | --- |
| 319 VI LLP | 6 (seq 230–235) | **Active** — saved values inflated since December 2025 |
| 316 V LLP | 6 (seq 227–232) | **Active** — saved values inflated since March 2026 |
| 318 Indium V | 5 (seq 192–195, 197) | Present but **switched off** — never produced a figure, no damage yet |
| 321 Indium VI | 5 (seq 194–197, 199) | Present but **switched off** — never produced a figure, no damage yet |
| 317, 320 | none | Not affected |

### Who is affected

- **Fund 319:** the tracking figures themselves, and *Net Current Assets before profit distribution
  to GP tracking*, which adds them up.
- **Fund 316 — more serious:** *Gross Realized amount* for **USD-class investors** is taken from the
  inflated tracking total, and the **carry and catch-up waterfall** is calculated from it. In the
  August test, fixing the formulas changed *Catch up Income* by up to **6.75 million INR** and
  *Carry Income* by up to **1.19 million INR**. Any statement or report showing these figures for
  316's USD classes should be treated as unreliable until corrected.

### The fix

1. **Change the formula** so it adds only the current period's entries to last run's saved value.
   This is a one-word change per formula (see section 6).
2. **Correct the saved starting value.** Otherwise the fixed formula keeps building on an inflated
   total. A tool recomputes the true since-inception value from all history for a chosen date and
   overwrites the saved figure for each investor.

### Status

| Fund | Formula fixed | Starting value corrected | Verified |
| --- | --- | --- | --- |
| 319 | Yes (test copy) | Yes, 31 July 2026 (test copy) | **Yes** — all 42 August figures match full-history totals to the cent |
| 316 | Yes (test copy) | Not yet | Pending |
| 318, 321 | Yes (test copy) | Must be seeded **before the formulas are switched on** | Not applicable while switched off |

---

## 6. Formula changes

The formula changes fall into three patterns. A tool proposes them automatically for each fund, and
backs up the fund's formulas before applying them. No fund needed a hand-written change.

### Pattern A — Tracking formulas (fixes the bug)

| | Wording |
| --- | --- |
| Before | sum of entries with a reporting date **up to** the period end + last saved value |
| After | sum of entries with a reporting date **within** the period + last saved value |

In the formula text this is `reporting_date: ..@end_date` → `reporting_date: @start_date..@end_date`.
**This changes the result** — it removes the double counting.

### Pattern B — One figure made of several since-inception totals

*Since Inception Apportioned Expenses* on the master funds adds up three separate since-inception
totals (Management Fees, Fund Administrative Costs, Others). No saved total exists for each of the
three on its own; only the combined figure is saved. The formula now asks for the three names
together and starts from the combined saved figure.

**This does not change the result** — it is the same total, calculated from the saved value.

### Pattern C — Feeder funds: since-inception total minus a master-fund share

On the feeder funds, *Since Inception Apportioned Expenses* is a since-inception total over six
names **minus** a since-inception total of the master-fund share. It becomes: last saved (net)
figure + this period's movement **minus this period's** master-fund share.

**This does not change the result.**

### Changes by fund

| Fund | Pattern A (tracking, changes numbers) | Pattern B | Pattern C | Total |
| --- | --- | --- | --- | --- |
| 316 V LLP | seq 227, 228, 229, 230, 231, 232 | seq 167 | — | 7 |
| 317 V Trust | — | — | seq 284 | 1 |
| 318 Indium V | seq 192, 193, 194, 195, 197 | — | seq 301 | 6 |
| 319 VI LLP | seq 230, 231, 232, 233, 234, 235 | seq 168 | — | 7 |
| 320 VI Trust | — | — | seq 286 | 1 |
| 321 Indium VI | seq 194, 195, 196, 197, 199 | — | seq 303 | 6 |

Funds 324–328 (Argan, Themis, Catmint, Laurus, Aether) do not use since-inception totals and need
no changes. Funds 346 and 349 have no formulas.

---

## 7. Other findings

| # | Finding | Why it matters | Suggested action |
| --- | --- | --- | --- |
| 1 | **Tracking amounts are filled in overnight.** A nightly job converts each new entry's amount into USD. The tracking formulas read those USD amounts during the run, before the job has filled them in for that run's own entries. | The tracking figures depend on *when* the run happened relative to the nightly job. Re-running production's August locally gave different tracking figures for 40 entries for exactly this reason. | Decide whether tracking formulas should convert amounts themselves, or run after the conversion. |
| 2 | **Possible double conversion.** A tracking formula's result is already in USD, but it is saved as the entry's main amount, and the entry's tracking amount is then that figure converted again. | Any report reading the tracking amount of these entries may be showing a doubly-converted number. Not yet confirmed. | Check which amount reports read for tracking entries. |
| 3 | **Likely typo in fund 318's formulas.** The tracking formulas list portfolio company `705` where 318's other formulas use `7705`. | One portfolio company may be missing from 318's tracking figures. | Confirm the intended company and correct the formula. |
| 4 | **Older periods are hard to re-test.** One late-March 2026 period on fund 319 has 58 overlapping runs; two runs regenerate everything from 2015. | Re-running old periods disturbs other periods' figures and locks. | Validation uses the most recent clean periods. |
| 5 | **Tracking formulas on 318 and 321 are switched off and have never run.** | Once fixed, their first run would give one period's movement, not a since-inception total. | Seed their starting values before switching them on. |
| 6 | **Funds 320 and 321 cannot be switched on yet.** Formula seq 34 (*Portfolio Sold* on 320, *Portfolio sold forex gain loss* on 321) adds up sales, income and carry paid **from the start of a distribution's earliest tranche**, a date taken from the data. Distribution 1493 (10 June 2026) has a tranche starting 1 April 2025, a year before the working file starts. | A period that processes a sale linked to such a distribution would silently miss those entries. The periods we tested did not hit this, which is why they matched. | Rewrite seq 34 on both funds before switching them on. The migration tool now refuses both funds until then. |
| 7 | **Funds 324–328 cannot be switched on as they are.** *Total Non Deal Expenses* (seq 19) and *Total Non Deal Income* (seq 48) add up all history with no saved starting value. | On the smaller working file they would silently add up only the current financial year. | Rewrite them to carry forward their own saved total before switching these funds on. The migration tool refuses them until then. |
| 8 | **Corrections do not flow forward on their own.** If an entry is back-dated into an earlier period, later saved totals are not updated until those later periods are re-run in order. | Previously every run re-added all history, so corrections were picked up automatically. | Operational procedure: after a back-dated correction, re-run the following periods in order. |

---

## 8. Before switching on in production

**Ready:** 316, 317, 318, 319. **Not ready:** 320 and 321 (finding 6), 324–328 (finding 7).

The steps below are done in one go by `rake "allocation:enable_incremental[fund,<id>]"` (or
`[entity,<id>]`): a dry run by default, `APPLY=true` to write, and
`allocation:disable_incremental` to switch a fund back off. It refuses any fund with a formula it
cannot safely handle.

For each fund:

- [ ] Deploy the engine change (it does nothing until a fund is switched on).
- [ ] Apply the fund's formula changes (section 6), with the automatic backup.
- [ ] **Tracking funds (316, 319):** correct the saved tracking starting values for the most recent
      saved date, then verify.
- [ ] **318, 321:** seed tracking starting values before those formulas are used.
- [ ] Switch the fund on.
- [ ] Re-run the most recent period and compare with the previous results.
- [ ] Tell the owners of fund 316's carry and catch-up figures about the tracking bug's effect on
      USD classes.
- [ ] Agree the operating procedure for back-dated corrections (finding 8).

---

## Glossary

| Term | Meaning |
| --- | --- |
| **Allocation run** | The job that calculates each investor's figures (fees, income, NAV, carry…) for a date range. |
| **Account entry** | One calculated or uploaded figure for an investor (or the fund) on a date. |
| **Since inception** | A running total from the start of the fund up to a date. |
| **Saved total / carry forward** | The since-inception figure a previous run stored, used as the starting point for the next run. |
| **Working file** | The temporary copy of data an allocation run calculates from (a SQLite file). |
| **Tracking currency** | The second currency figures are reported in — USD for the INR funds (316, 317, 319, 320), INR for the USD funds (318, 321). |
| **Master / feeder fund** | A feeder fund (e.g. 321) invests through a master fund (e.g. 319) and reads some of its data. |
| **Waterfall** | The sequence of calculations that splits distributable proceeds into return of capital, preferred return, catch-up and carry. |
| **Rounding-only difference** | A difference of 0.0001 cents or less, caused by adding decimals in a different order. |
| **Seq** | A formula's sequence number — the order it runs in within the fund. |
