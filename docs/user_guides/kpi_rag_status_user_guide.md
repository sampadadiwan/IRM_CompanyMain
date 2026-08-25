# RAG Status User Guide

RAG status is a red/amber/green flag CapHive can show next to a KPI value, so you and your team
can spot at a glance which numbers are on track and which need attention — without doing the
comparison yourself every time a report comes in.

## 📑 Table of Contents
1. [What RAG Status Does](#what-rag-status-does)
2. [Setting Up a RAG Rule](#setting-up-a-rag-rule)
3. [How It's Calculated](#how-its-calculated)
4. [Worked Examples](#worked-examples)
5. [Where You'll See It](#where-youll-see-it)
6. [Things to Know](#things-to-know)

---

## What RAG Status Does

For any KPI you track, you can tell CapHive what "good," "borderline," and "concerning" look
like. Once that's set up, CapHive checks every new value against your rule automatically — the
moment a number is entered or uploaded — and shows a colored flag:

*   🔴 **Red** — outside the acceptable range, worth a look.
*   🟡 **Amber** — in between; not a problem yet, but trending the wrong way.
*   🟢 **Green** — on track.

You set this up once per KPI. From then on, every reported value for that KPI is flagged
automatically — no one has to re-check it by hand.

---

## Setting Up a RAG Rule

Go to the KPI Mapping screen for the KPI you want to flag (Portfolio Company → KPI Mapping tab →
open the KPI). You'll see four RAG fields:

*   **RAG comparator tag** — what should the reported value be measured against? Choose
    **Prior period** to compare a value against this same KPI's own most recently reported
    period — no separate upload needed, since that value is typically already sitting in CapHive.
    Otherwise, pick (or type) the tag your fund uses for the comparison report — most commonly
    **Budget**, but it can be anything your reports are tagged with (for example, a "PriorYear"
    tag to compare against last year's figure, when that's a genuinely separate report rather
    than simply "whatever was reported before this one"). Leave this **blank** if the KPI doesn't
    need a comparison at all — some KPIs (a margin percentage, a ratio, a number of months of
    runway) are judged on their own, with nothing to divide against.
*   **RAG direction** — is a higher number better, or a lower number better? Revenue and profit
    margins are "higher is better." Customer churn and cash burn are "lower is better."
*   **RAG red threshold** — the cutoff below which (or above which, for "lower is better" KPIs)
    a value is flagged red.
*   **RAG green threshold** — the cutoff at or above which (or at/below which, for "lower is
    better" KPIs) a value is flagged green. Anything between red and green is amber.

Once both thresholds and a direction are filled in, the screen shows your rule back to you in
plain language, e.g. *"Red below 70% of Budget · Green at or above 90%"* — so you can always
confirm what's configured without having to remember the raw numbers.

---

## How It's Calculated

There are two ways a RAG rule can work, depending on whether you filled in a comparator tag:

**With a comparator tag** — the reported value is divided by the matching value from the
comparison report (e.g. this month's Actual ÷ this month's Budget), and that ratio is what gets
checked against your red/green thresholds. A threshold of "0.7" here means "70% of the
comparator."

**With Prior period** — works the same way, except the value it divides by is whichever report
for this same KPI most recently came before the one being checked, however far back that
actually is. It's not a fixed "one month ago" or "one year ago" — it's simply the last time this
KPI was reported before now, so it lines up naturally whether you report monthly, quarterly, or
on some other cadence.

**Without a comparator tag (blank)** — the reported value is checked directly against your
thresholds, with nothing to divide by. This is the right choice for a KPI that's already a
self-contained number, like a percentage or a ratio.

If the comparison value (whether a tagged report like Budget, or the prior period) hasn't been
entered yet, the KPI simply has no RAG status yet — it isn't guessed at. As soon as the
comparison value is entered, the flag appears automatically, even on values that were reported
earlier. This also means: if you enter periods out of order (say, this month before catching up
on a missed earlier one), the earlier value's arrival will retroactively flag the later one.

---

## Worked Examples

| KPI | Comparator tag | Direction | Red threshold | Green threshold | What it means |
|---|---|---|---|---|---|
| Revenue | Budget | Higher is better | 0.7 | 0.9 | Red if actual revenue is below 70% of budget; green at 90% or above. |
| Net Burn | Budget | Lower is better | 1.2 | 1.0 | Red if spending is more than 120% of the budgeted burn; green at or under budget. |
| Gross Margin % | *(blank)* | Higher is better | 0.40 | 0.55 | Red if margin is below 40%; green at 55% or above — judged directly, no comparator needed. |
| Cash Runway (months) | *(blank)* | Higher is better | 6 | 12 | Red under 6 months of runway; green at 12 months or more. |
| Customer Churn % | Budget | Lower is better | 1.5 | 1.0 | Red if churn is more than 1.5× the budgeted rate. |
| Revenue Growth YoY | PriorYear | Higher is better | 1.10 | 1.20 | Red if this year is below 110% of last year's figure (under 10% growth), compared against a separately uploaded prior-year report. |
| Revenue (month-on-month) | Prior period | Higher is better | 0.95 | 1.00 | Red if this month's revenue is below 95% of last month's — compared automatically against whatever was reported last, no extra upload needed. |
| Leverage Ratio (debt covenant) | *(blank)* | Lower is better | 4.0 | 3.6 | Red if leverage exceeds the 4.0x covenant limit; green comfortably under it. |

---

## Where You'll See It

*   **The KPI Mapping screen** — the configured rule, in plain language, on both the summary
    list and the individual KPI's detail page.
*   **The KPI reporting grid** — a small colored badge next to any value that has a RAG status.
*   **A KPI's own detail page** — the value itself is shown in a colored badge (red/amber/green),
    with a one-line note underneath naming the rule that produced it (e.g. *"Amber — Red below
    70% of Budget · Green at or above 90%"*), so you never have to go find the rule separately to
    understand why a value is flagged.
*   **The Workbook check panel**, when a portfolio company uploads a file — a red or amber note
    calling out any value that falls in your red or amber band, right alongside the other checks
    described in the [KPI Management & Workbook Upload User Guide](/user_guides/kpi_upload_user_guide).

---

## Things to Know

*   RAG status updates automatically whenever the reported value or its comparison value changes
    — there's nothing to re-run.
*   A KPI with no RAG rule configured, or one still waiting on its comparison value, simply shows
    no flag rather than a misleading one.
*   RAG status is separate from the plausibility warnings (like "this looks 1,000× off") described
    in the workbook upload guide — RAG tells you whether a value is *good*, plausibility checks
    tell you whether a value was probably *entered correctly*.
*   **Prior period** only ever compares like against like — a monthly report against the
    previous monthly report, a quarterly report against the previous quarterly report, and so on
    (never a month against a quarter). It also only compares an Actual against a prior Actual,
    never against a Budget or other tagged report from an earlier period.
*   **RAG rules only apply to approved figures.** A value still awaiting your approval is never
    flagged itself, and is never used as the comparator for judging another value — a number
    nobody has confirmed yet shouldn't drive a flag someone might act on. Once you approve a
    figure, any flag it's involved in appears (or updates) automatically — you don't need to
    re-enter anything.
