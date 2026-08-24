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

*   **RAG comparator tag** — what should the reported value be measured against? Type the tag
    your fund uses for the comparison report — most commonly **Budget**, but it can be anything
    your reports are tagged with (for example, a "PriorYear" tag to compare against last year's
    figure). Leave this **blank** if the KPI doesn't need a comparison at all — some KPIs (a
    margin percentage, a ratio, a number of months of runway) are judged on their own, with
    nothing to divide against.
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

**Without a comparator tag (blank)** — the reported value is checked directly against your
thresholds, with nothing to divide by. This is the right choice for a KPI that's already a
self-contained number, like a percentage or a ratio.

If the comparison report (e.g. Budget) hasn't been entered yet for that period, the KPI simply
has no RAG status yet — it isn't guessed at. As soon as the comparison value is entered, the flag
appears automatically, even on values that were reported earlier.

---

## Worked Examples

| KPI | Comparator tag | Direction | Red threshold | Green threshold | What it means |
|---|---|---|---|---|---|
| Revenue | Budget | Higher is better | 0.7 | 0.9 | Red if actual revenue is below 70% of budget; green at 90% or above. |
| Net Burn | Budget | Lower is better | 1.2 | 1.0 | Red if spending is more than 120% of the budgeted burn; green at or under budget. |
| Gross Margin % | *(blank)* | Higher is better | 0.40 | 0.55 | Red if margin is below 40%; green at 55% or above — judged directly, no comparator needed. |
| Cash Runway (months) | *(blank)* | Higher is better | 6 | 12 | Red under 6 months of runway; green at 12 months or more. |
| Customer Churn % | Budget | Lower is better | 1.5 | 1.0 | Red if churn is more than 1.5× the budgeted rate. |
| Revenue Growth YoY | PriorYear | Higher is better | 1.10 | 1.20 | Red if this year is below 110% of last year's figure (under 10% growth). |
| Leverage Ratio (debt covenant) | *(blank)* | Lower is better | 4.0 | 3.6 | Red if leverage exceeds the 4.0x covenant limit; green comfortably under it. |

---

## Where You'll See It

*   **The KPI Mapping screen** — the configured rule, in plain language, on both the summary
    list and the individual KPI's detail page.
*   **The KPI reporting grid** — a small colored badge next to any value that has a RAG status.
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
